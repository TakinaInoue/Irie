module irie.compiler.ast.node;

public import std.utf;

import std.stdio;
import std.bitmanip;
import std.conv : to;
import std.algorithm : remove;

public import std.format;

public import irie.vm;

public import irie.compiler.parser : ParserResult;

public import irie.compiler.lexer;
public import irie.compiler.ast.func;
public import irie.compiler.ast.vars;
public import irie.compiler.ast.expr;
public import irie.compiler.ast.type;
public import irie.compiler.ast.array;
public import irie.compiler.ast.structure;
public import irie.compiler.ast.conditional;
public import irie.compiler.ast.interstricts;

public struct Variable {
    dstring name;
    Type type;
    ubyte index;
    uint defLine, scopeDepth;
    bool initialized;
}

public struct Function {
    dstring name;
    Type returnType;
    Type[dstring] parameters;
    dstring filename;

    size_t offset;

    // find better name for this
    bool lastParameterOptionalArray;

    bool isVoid() {return returnType.isVoid();}
}

public struct FunctionCallEntry {
    bool wideCall;
    Token functionName;
    size_t offset;
    Compiler compiler;
}

public struct EnumStructure {
    string name;
    Type type;
    Value[wstring] enumMembers;
}

public class CompilationRegistry {
    public static:
        Type floatType = Type("float", ValueType.Float);
        Type intType = Type("int", ValueType.Int);
        Type boolType = Type("bool", ValueType.Boolean);
        Type charType = Type("char", ValueType.Char);
        Type stringType = Type("string", ValueType.Object, ObjectType.String);
        Type unknownType = Type("unknown", ValueType.Unknown);
        
        Type voidType = Type("void", ValueType.Unknown);
        
        uint[wstring] stringObjectsMap;

        Function[dstring] functions;  
        FunctionCallEntry[] functionCallsToLink;

        bool performLink() {
            writeln("Linking..");

            foreach (FunctionCallEntry fc ; functionCallsToLink) {
                Function* f = fc.functionName.data in functions;
                if (f is null) {
                    fc.compiler.writeError(fc.functionName, format("Undefined reference to '%s' in offset '%0xu16'"d, 
                        fc.functionName, fc.offset-1));
                    return false;
                }
                if (fc.wideCall) {
                    ubyte[4] byts = nativeToLittleEndian(cast(uint)f.offset);
                    fc.compiler.chunk.instructions[fc.offset] = byts[0];  
                    fc.compiler.chunk.instructions[fc.offset+1] = byts[1];
                    fc.compiler.chunk.instructions[fc.offset+2] = byts[2];  
                    fc.compiler.chunk.instructions[fc.offset+3] = byts[3];
                } else {
                    ubyte[2] byts = nativeToLittleEndian(cast(ushort)f.offset);
                    fc.compiler.chunk.instructions[fc.offset] = byts[0];  
                    fc.compiler.chunk.instructions[fc.offset+1] = byts[1];  
                }
            }

            writeln("Linking done.");

            return true;
        }

        uint getStringOffset(wstring str) {
            uint* ofs = str in stringObjectsMap;
            if (ofs is null) {
                uint of = ObjectManager.newObject!StringObject(str);
                stringObjectsMap[str] = of;
                return of;
            }
            return *ofs;
        }  

        IrieNativeSymbol* findNativeSymbol(dstring name) {
            for (int i = 0; i < nativeSymbols.length; i++) {
                IrieNativeSymbol* symbol = &nativeSymbols[i];
                if (symbol.name == name)
                    return symbol;
            }
            return null;
        }
}

public class Compiler {

    Type[32] typeStack;
    Type* stackTop;

    Chunk chunk;
    dstring filename;

    Variable[dstring] variables;
    size_t[dstring] mappings;

    size_t scopeDepth;

    bool hadError;
    bool returnWritten;

    ParserResult parserResult;

    Function currentFunction;

    this(dstring filename) {
        this.filename = filename;
        this.hadError = false;
        this.returnWritten = false;

        this.stackTop = this.typeStack.ptr;

        this.scopeDepth = 0;
    }

    void push(Type v) {
        *this.stackTop++ = v;
    }
    
    Type pop() {
        this.stackTop--;
        return *this.stackTop;
    }

    size_t getValueId(Token v, out Type outType) {
        dstring keyName = v.data;
        if (v.type == TokenType.FloatLiteral) {
            keyName ~= 'f';
            outType = CompilationRegistry.floatType;
        } else if (v.type == TokenType.IntLiteral) {
            keyName ~= 'i';
            outType = CompilationRegistry.intType;
        } else if (v.type == TokenType.StringLiteral) {
            outType = CompilationRegistry.stringType;
        } else {
            outType = CompilationRegistry.charType;
        }
        size_t* i = keyName in mappings;
        if (i is null) {
            mappings[keyName] = chunk.values.length;
            Value value;
            if (v.type == TokenType.FloatLiteral) {
                value = Value(v.data.to!float);
            } else if (v.type == TokenType.IntLiteral) {
                value = Value(v.data.to!int);
            } else if (v.type == TokenType.StringLiteral) {
                value = Value(ValueType.Object);
                value.offset = CompilationRegistry.getStringOffset(toUTF16(v.data));
            } else {
                value = Value(toUTF32(v.data)[0]);
            }
            chunk.values ~= value;
            return mappings[keyName];
        }
        return *i;
    }

    Type findType(Token token) {
        switch(token.data) {
            case "int": return CompilationRegistry.intType;
            case "float": return CompilationRegistry.floatType;
            case "bool": return CompilationRegistry.boolType;
            case "char": return CompilationRegistry.charType;
            case "string": return CompilationRegistry.stringType;
            case "unknown": return CompilationRegistry.unknownType;
            default:
                writeError(token, "Unrecognized typename.");
                return CompilationRegistry.unknownType;
        }
    }
    
    bool areTypesCompatible(Type a, Type b, Token equSign) {

        bool isCompatible = (a.logicalType == b.logicalType || (a.isNumeric() && b.isNumeric())) 
                            && a.dimensions == b.dimensions;
        if (isCompatible) return true;
        // here's the thing..
        // we can automatically treat A or B as compatible.
        // sence Unknown in irie is equivalent to typescript's "any"
        if (b.logicalType == ValueType.Unknown ||
            a.logicalType == ValueType.Unknown) return true;

        writeError(equSign, "Cannot convert from "d ~ a.toString() ~ " to a "d ~ b.toString());
        return false;
    }

    size_t writeJump(uint line, OpSet jump) {
        size_t of = chunk.instructions.length+1;
        chunk.write(line, jump, 0xFF, 0xFF);
        return of;
    }
    
    void patchJump(Token tk, size_t offset) {
        size_t m = (chunk.instructions.length - offset) - 2;
        if (m > ushort.max) {
            writeError(tk, "Too large of a body.");
            return;
        }
        auto bts = nativeToLittleEndian!ushort(cast(ushort) m);
        chunk.instructions[offset  ] = bts[0];
        chunk.instructions[offset+1] = bts[1];
    }

    void patchLoop(Token tk, size_t offs) {
        size_t m = (chunk.instructions.length - offs) + 3;
        if (m > ushort.max) {
            writeError(tk, "Too large of a body.");
            return;
        }
        chunk.write(tk.line, OpSet.jmpb);
        chunk.write(tk.line, nativeToLittleEndian!ushort(cast(ushort)(m)));
    }

    void openScope() {
        this.scopeDepth++;
    }

    void closeScope() {
        this.scopeDepth--;
        if (this.scopeDepth > 0)
            this.returnWritten = false;
        foreach (dstring k ; variables.byKey()) {
            if (variables[k].scopeDepth > scopeDepth) {
                variables.remove(k);
            }
        }
    }

    Variable* findVariable(Token name, bool writeErrorOnFail) {
        Variable* var = name.data in variables;
        if (var is null && writeErrorOnFail) {
            writeError(name, "Could not find variable '" ~ name.data ~ "'.");
        }   
        return var;
    }

    void finish(Token eof) {
        if (returnWritten)
            return;
        chunk.write(eof.line, OpSet.ret);
    }
    
    void writeError(Token t, dstring error) {
        writeln(filename,  ":", t.line, ":", t.column, ": error: ", error);
        hadError = true;
    }
}

public abstract class Node {
    const string type;

    this(string type) {
        this.type = type;
    }

    abstract void compile(Compiler compiler);
}

public class CompoundNode : Node {
    Node[] nodes;

    this(Node[] nodes ...) {
        super("Compound");
        this.nodes = nodes;
    }

    public override void compile(Compiler cc) {
        foreach (Node n ; nodes) {
            n.compile(cc);
        }
    }
}