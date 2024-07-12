module irie.compiler.ast.func;

import std.bitmanip;
import irie.compiler.ast.node;
import std.encoding;

public class BlockNode : Node {
    
    Node[] nodes;
    Token end;

    this() {
        super("Block");
    }

    override void compile(Compiler compiler) {
        compiler.openScope();
        foreach (Node n ; nodes) {
            Type* stackTop = compiler.stackTop;
            n.compile(compiler);
            if (n.type != "Return" && compiler.stackTop > compiler.typeStack.ptr) {// we only want this clean up if it's not a return statement.
                while (compiler.stackTop > stackTop) {
                    compiler.stackTop--;
                    compiler.chunk.write(end.line, OpSet.pop);
                }
            }
        }
        compiler.closeScope();
    }
}

public struct Parameter {
    Token name;
    TypeNode type;
}

public class FuncNode : Node {

    Token name;
    TypeNode returnType;
    Token eof;
    Parameter[] parameters;
    bool isLastParamAnArray;

    BlockNode body_;

    Function func;

    Compiler compiler;

    this() {
        super("Function");
    }

    void setup(Compiler compiler) {   
        this.compiler = compiler;
        if (parameters.length > 128) {
            compiler.writeError(parameters[0].name,
                "Too many parameters in function (functions may not have more than 128 parameters.)");
            return;
        }
        
        func = Function(name.data);
        if (this.returnType.typename.data == "void"d && this.returnType.dimensions == 0) {
            func.returnType = CompilationRegistry.unknownType;
            func.returnType.name = "void";
        } else {
            func.returnType = this.returnType.asCompilerType(compiler);
        }
        func.filename   = compiler.filename;
        
        size_t s = CompilationRegistry.functions.length;
        if (s > ushort.max) {
            compiler.writeError(name, "More than 2^16 functions defined.");
            return;
        }
        func.offset = cast(ushort) s;
        func.lastParameterOptionalArray = isLastParamAnArray;

        size_t i = 0;
        foreach (Parameter param ; parameters) {
            Type type = param.type.asCompilerType(compiler);    
            if (i++ + 1 > parameters.length && isLastParamAnArray) {
                type.dimensions++;
            }
            func.parameters[param.name.data] = type;
            ubyte offs = cast(ubyte)compiler.variables.length;
            compiler.variables[param.name.data] = Variable(
                param.name.data, type, offs,
                param.name.line, cast(uint)compiler.scopeDepth, true,
            );
            compiler.chunk.write(param.name.line, OpSet.store, offs);
        }
        compiler.chunk.memreq = cast(ubyte) compiler.variables.length;

        compiler.chunk.filename = toUTF8(compiler.filename);
        compiler.chunk.name     = toUTF8(this.name.data);

        compiler.currentFunction = func;
        CompilationRegistry.functions[func.name] = func;
    }

    override void compile(Compiler compiler) {
        body_.compile(compiler);

        if (func.returnType.name != "void" && !compiler.returnWritten) {
            compiler.writeError(name, "Function "d ~ name.data
                ~ " is expected to return a "d ~ func.returnType.toString());
            return;
        }

        compiler.finish(body_.end);
    }
}

public class FunctionCallNode : Node {
    Token name;
    Node[] parameters;

    this() {
        super("FunctionCall");
    }
    
    override void compile(Compiler cc) {
        IrieNativeSymbol* symbol = CompilationRegistry.findNativeSymbol(name.data);
        if (symbol !is null) {
            if (symbol.argCount != parameters.length) {
                cc.writeError(name, format("Interrupt '%s' requires %u parameters, %u were given."d, 
                    symbol.name, symbol.argCount, parameters.length));
                return;
            }    
            foreach (Node param ; parameters) {
                param.compile(cc);
                cc.pop(); // no type checking for interrupts
                // interrupts are not supposed to be called directly
                // by developers, this is why the symbols don't have their types.
                // people are not supposed to use them directly.
            }
            // this is necessary, since depending on the symbol
            // example: in IVM_ReadFile we return an Array of integers.
            cc.chunk.write(name.line, OpSet.interrupt);
            cc.chunk.write(name.line, nativeToLittleEndian!ushort(symbol.offset));
            if (!symbol.returnType.isVoid()) {
                cc.push(symbol.returnType);
            }
            return;
        }
        Function* func = name.data in CompilationRegistry.functions;
        if (func is null) {
            cc.writeError(name, "Undefined reference to function '"d~name.data~"'"d);
            cc.push(CompilationRegistry.unknownType);
            return;
        }
        if (func.parameters.length != parameters.length) {
            cc.writeError(name, format("Function '%s' from '%s' requires %u parameters, %u were given."d, 
                func.name, func.filename, func.parameters.length, parameters.length));
            cc.push(CompilationRegistry.unknownType);
            return;
        }
        size_t i = 0;
        foreach (fParam ; func.parameters) {
            parameters[i++].compile(cc);
            Type t = cc.pop();
            if (!cc.areTypesCompatible(t, fParam, name)) {
                return;
            }
        }
        bool isWide = func.offset > ushort.max;
        if (isWide) {
            cc.chunk.write(name.line, OpSet.invokew, 0xFF, 0xFF, 0xFF, 0xFF);
        } else {
            cc.chunk.write(name.line, OpSet.invoke, 0xFF, 0xFF);
        }
        size_t offs = cc.chunk.instructions.length - 2;
        CompilationRegistry.functionCallsToLink ~= FunctionCallEntry(
            isWide, name, offs, cc
        );

        if (!func.returnType.isVoid())
            cc.push(func.returnType); 
    }
}

public class ReturnNode : Node {
    Token returnToken;
    Node expression;

    this() {
        super("Return");
    }

    override void compile(Compiler compiler) {
        // this is madness, but the rules are
        // if the current function is of type VOID, expression NEEDS TO BE null.
        // if the current function is not of type VOID, expression CANNOT be null.

        if (compiler.currentFunction.isVoid() && expression !is null) {
            compiler.writeError(returnToken,
                "Function "d ~compiler.currentFunction.name ~ " should not return any values.");
            return;
        } else if (!compiler.currentFunction.isVoid() && expression is null) {
            compiler.writeError(returnToken, "Function "d ~ compiler.currentFunction.name
                ~ " is expected to return a "d ~ compiler.currentFunction.returnType.toString());
            return;
        }

        // we also don't want to allow two returns in the same scope.
        if (compiler.returnWritten) {
            compiler.writeError(returnToken, "This scope already has a return statement, delete this.");
            return;
        }

        if (expression !is null) {
            expression.compile(compiler);
            Type rt = compiler.pop();
            if (!compiler.areTypesCompatible(rt, compiler.currentFunction.returnType, returnToken)) {
                return;
            }
        }

        compiler.chunk.write(returnToken.line, OpSet.ret);
        // inform compiler that we wrote a return opcode on the current scope.
        compiler.returnWritten = true;
    }
}