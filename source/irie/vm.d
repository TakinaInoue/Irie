module irie.vm;

import std.stdio;
import std.format;
import std.bitmanip;

public import irie.dism;
public import irie.bytes;
public import irie.native;

public struct CallFrame {
    Chunk* chunk;
    ubyte* ip;
    CallFrame* next;
    CallFrame* prev;
    Value[] memory;
}

public final class IrieVM {
    Value[32] stack;
    Value* stackTop;

    CallFrame* current;

    IrieExecutable executable;

    this() {
        reset();
        loadInterrupts();
    }

    void loadExecutable(IrieExecutable executable, bool shouldRun) {
        this.executable = executable;
        if (shouldRun) {
            if (executable.entryPoint == -1 || executable.entryPoint >= executable.chunks.length) {
                writeln("Cannot execute: no valid entry point in executable.");
                return;
            }
            run(&this.executable.chunks[this.executable.entryPoint]);
        }
    }

    void reset() {
        this.current = null;
        this.stackTop = stack.ptr;
    }

    void run(Chunk* chunk) {
        if (current is null) {
            current = new CallFrame();
        } else {
            if (current.next is null)
                current.next = new CallFrame();
            current.next.prev = current;
            current = current.next;
        }
        current.chunk = chunk;
        current.ip = current.chunk.instructions.ptr;

        if (current.memory.length < current.chunk.memreq) {
            current.memory = new Value[current.chunk.memreq];
        }

        for (;;) {
            debug {
                for (Value* v = stack.ptr; v < stackTop; v++) {
                    write("[", *v, "]");
                }
                writeln();
                dissasembleInstruction(current.chunk,
                    cast(size_t)(this.current.ip - this.current.chunk.instructions.ptr));
            }
            ubyte it = readByte();
            switch(it) {
                case OpSet.push: 
                case OpSet.pushl: {
                    size_t offs = it == OpSet.push ? readByte() : readShort(); 
                    push(current.chunk.values[offs]);
                    break;
                }
                case OpSet.pop:
                    if (stackTop > stack.ptr)
                        pop();
                    break;
                case OpSet.ptrue:
                    push(Value(true));
                    break;
                case OpSet.pfalse:
                    push(Value(false));
                    break;
                case OpSet.pnull:
                    push(Value(ValueType.Unknown));
                    break;
                mixin(tmplMath!("add", "+"));
                mixin(tmplMath!("sub", "-"));
                mixin(tmplMath!("mul", "*"));
                mixin(tmplMath!("mod", "%"));
                mixin(tmplMath!("div", "/"));
                case OpSet.equ: {
                    Value b = pop();
                    Value a = pop();
                    push(Value(a.isEqualTo(b)));
                    break;
                }
                case OpSet.diff: {
                    Value b = pop();
                    Value a = pop();
                    push(Value(!a.isEqualTo(b)));
                    break;
                }
                mixin(tmplBool!("greater", ">"));
                mixin(tmplBool!("less", "<"));
                mixin(tmplBool!("grtrequ", ">="));
                mixin(tmplBool!("lssequ", "<="));
                case OpSet.concat: {
                    Value b = pop();
                    Value a = pop();
                    push(Value(new StringObject(a.asString() ~ b.asString())));
                    break;
                }
                case OpSet.strlen:
                case OpSet.strlenpop: {
                    Value str = pop();
                    if (it != OpSet.strlenpop) push(str);
                    push(Value(cast(int)(str.asString().length)));
                    break;
                }
                case OpSet.newarr: {
                    Value len = pop();
                    push(Value(new ArrayObject(len.int_)));
                    break;
                }
                case OpSet.alength:
                case OpSet.alengthpop: {
                    Value array = pop();
                    if (array.type != ValueType.Object || array.object.type != ObjectType.Array ||
                        array.object.type != ObjectType.String) {
                        raiseFault("GeneralSegmentationProtectionFault",
                            "Opcode attempted to perform an array operation on a non-array.");
                        return;
                    }
                    if (it != OpSet.alengthpop)
                        push(array);
                    push(Value(cast(int)(cast(ArrayObject)array.object).values.length));
                    break;
                }
                case OpSet.aload: 
                case OpSet.aloadpop: {
                    Value index = pop();
                    Value array = pop();
                    Value value;
                    if (array.type == ValueType.Object && array.object().type == ObjectType.String) { 
                        StringObject obj = cast(StringObject) array.object();
                        if (!ensureIndexBounds(index.int_, obj.characters.length)) return;
                        value = Value(cast(dchar)obj.characters[index.int_]);
                    } else if (array.type == ValueType.Object && array.object().type == ObjectType.Array) { 
                        ArrayObject obj = cast(ArrayObject) array.object();
                        if (!ensureIndexBounds(index.int_, obj.values.length)) return;
                        value = obj.values[index.int_];
                    } else {
                        raiseFault("GeneralSegmentationProtectionFault",
                            "Opcode attempted to perform an array operation on a non-array.");
                        return;
                    }
                    if (it != OpSet.aloadpop)
                        push(array);
                    push(value);
                    break;
                }
                case OpSet.astore:
                case OpSet.astorepop: {
                    Value value = pop();
                    Value index = pop();
                    Value array = pop();
                    if (array.type == ValueType.Object && array.object().type == ObjectType.String) { 
                     // this was originally, but not anymore, however this requires some
                     // unfunny conversions.
                     //   raiseFault("GeneralSegmentationProtectionFault",
                     //       "Strings are immutable, may not be modified.");
                        StringObject obj = cast(StringObject) array.object();
                        if (!ensureIndexBounds(index.int_, obj.characters.length)) return;
                        obj.characters[index.int_] = cast(wchar)value.int_;
                        return;
                    } else if (array.type == ValueType.Object && array.object().type == ObjectType.Array) { 
                        ArrayObject obj = cast(ArrayObject) array.object();
                        if (!ensureIndexBounds(index.int_, obj.values.length)) return;
                        obj.values[index.int_] = value;
                    } else {
                        raiseFault("GeneralSegmentationProtectionFault",
                            "Opcode attempted to perform an array operation on a non-array.");
                        return;
                    }
                    if (it != OpSet.astorepop)
                        push(array);
                    break;
                }
                case OpSet.neg: {
                    Value p = pop();
                    if (p.type == ValueType.Float) {
                        p.float_ = -p.float_;
                    } else {
                        p.int_ = -p.int_;
                    }
                    push(p);
                    break;
                }
                case OpSet.inv: {
                    Value a = pop();
                    a.boolean = !a.boolean;
                    push(a);
                    break;
                }
                case OpSet.load: {
                    ubyte of = readByte();
                    if (of >= current.memory.length) {
                        raiseFault("GeneralSegmentationProtectionFault", "");
                        return;
                    }
                    push(current.memory[of]);
                    break;
                }
                case OpSet.store: {
                    ubyte of = readByte();
                    if (of >= current.memory.length) {
                        raiseFault("GeneralSegmentationProtectionFault", "");
                        return;
                    }
                    current.memory[of] = pop();
                    break;
                }
                case OpSet.incm: {
                    ubyte of = readByte();
                    if (of >= current.memory.length) {
                        raiseFault("GeneralSegmentationProtectionFault", "");
                        return;
                    }
                    Value v = current.memory[of];
                    if (v.type == ValueType.Float) {
                        v.float_ += 1;
                    } else {
                        v.int_++;
                    }
                    current.memory[of] = v;
                    break;
                }
                case OpSet.decm: {
                    ubyte of = readByte();
                    if (of >= current.memory.length) {
                        raiseFault("GeneralSegmentationProtectionFault", "");
                        return;
                    }
                    Value v = current.memory[of];
                    if (v.type == ValueType.Float) {
                        v.float_ -= 1;
                    } else {
                        v.int_--;
                    }
                    current.memory[of] = v;
                    break;
                }
                case OpSet.jmp: {
                    ushort sh = readShort();
                    this.current.ip += sh;
                    break;
                }
                case OpSet.jmpf: {
                    ushort sh = readShort();
                    if (!pop().boolean) {
                        this.current.ip += sh;
                    }
                    break;
                }
                case OpSet.jmpb: {
                    ushort sh = readShort();
                    this.current.ip -= sh;
                    break;
                }
                case OpSet.invoke: {
                    run(&executable.chunks[readShort()]);
                    break;
                }
                case OpSet.invokew: {
                    run(&executable.chunks[readInt()]);
                    break;
                }
                case OpSet.interrupt: {
                    ushort offs = readShort();
                    IrieNativeSymbol symb = nativeSymbols[offs];
                    try {
                        int exitCode = symb.func(this);
                        if (exitCode != 0) {
                            return;
                        }
                    } catch(Throwable b) {
                        panic();
                        debug {throw b;}
                        return;
                    }
                    break;
                }
                case OpSet.ret: {
                    current = current.prev;
                    return;
                }
                default:
                    throw new Exception("Unknown opcode.");
            }
        }
    }

    package:
        ubyte  readByte()  {return *current.ip++;}
        ushort readShort() {return littleEndianToNative!ushort([readByte(), readByte()]);}
        uint   readInt() {return littleEndianToNative!uint([readByte(), readByte(),readByte(), readByte()]);}
        
        void push(Value v) {
            *this.stackTop++ = v;
        }
        Value pop() {
            this.stackTop--;
            return *this.stackTop;
        }

        bool ensureIndexBounds(uint ind, size_t len) {
            if (ind >= len || ind < 0) {
                raiseFault("GeneralSegmentationProtectionFault",
                    format("Index %d is outside of bounds for array of length %u.", ind,
                    len));
                return false;
            }
            return true;
        }

        void raiseFault(string faultName, string message) {
            writeln("irie.faults.",faultName,": ", message);
            while (current != null) {
                size_t offs = cast(size_t) (current.ip - current.chunk.instructions.ptr);
                writefln("\tat offset %04u, function %s in file %s at line %d",
                    offs,
                    current.chunk.name,
                    current.chunk.filename,
                    current.chunk.getLine(offs)    
                );
                current = current.prev;
            }
        }

        void panic() {
            writeln("== IVM Panic ==");
            writeln("My god.. is that an IVM bug????");
            writeln("IVM: yes.. somehow you did it?\n");
            writeln("Please send the IVM executable that resulted in this bug to:");
            writeln("http://takina.jp.net/projects/irie/report/");
            writeln("== IVM Panic ==");
            current = null;
        }
}

private:
template tmplMath(string opcode, string op) {
    const char[] tmplMath = "
        case OpSet."~opcode~": {
            Value b = pop();
            Value a = pop();
            if (!a.isNumber() || !b.isNumber()) {
                raiseFault(\"ArithmeticFault\", \"opcode "~opcode~" accessed non-numeric operands in stack.\");
                return;
            }
            ValueType t = a.type > b.type ? a.type : b.type;
            a.castTo(t);
            b.castTo(t);
            if (t == ValueType.Float) {
                a.float_ = a.float_ "~op~" b.float_;
            } else {
                a.int_ = a.int_ "~op~" b.int_;
            }
            push(a);
            break;
        }
    ";
}
template tmplBool(string opcode, string op) {
    const char[] tmplBool = "
        case OpSet."~opcode~": {
            Value b = pop();
            Value a = pop();
            ValueType t = a.type > b.type ? a.type : b.type;
            a.castTo(t);
            b.castTo(t);
            Value r = Value(false);
            if (t == ValueType.Float) {
                r.boolean = a.float_ "~op~" b.float_;
            } else {
                r.boolean = a.int_ "~op~" b.int_;
            }
            push(r);
            break;
        }
    ";
}