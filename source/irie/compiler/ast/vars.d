module irie.compiler.ast.vars;

import irie.compiler.ast.node;

public class VarNode : Node {

    Token name;
    TypeNode type;
    Node assignValue;

    this() {
        super("Var");
    }

    override void compile(Compiler compiler) {
        Variable* var = name.data in compiler.variables;
        if (var !is null) {
            compiler.writeError(name,
                format("Local redefinition is disallowed, local already defined in line %u"d, var.defLine)
            );
            return;
        }

        if (assignValue is null && type is null) {
            compiler.writeError(name, "Local has no type identifier.");
            return;
        }
        Type t = CompilationRegistry.unknownType;
        if (type !is null) {
            t = type.asCompilerType(compiler);
            if (t.logicalType == ValueType.Unknown)
                return;
        }
        if (assignValue !is null) {
            assignValue.compile(compiler);
            Type typ = compiler.pop();
            if (type !is null &&
                !compiler.areTypesCompatible(typ, t, type.typename)) {
                return;
            }
            compiler.chunk.write(name.line, OpSet.store, cast(ubyte) compiler.variables.length);
            t = typ;
        }
        if (compiler.variables.length > ubyte.max) {
            compiler.writeError(name, "Too many local variables (over 255 local variables defined.)");
            return;
        }
        Variable v = Variable(name.data, t, cast(ubyte) compiler.variables.length,
            name.line, cast(uint)compiler.scopeDepth, assignValue !is null);
        compiler.variables[v.name] = v;

        if (compiler.chunk.memreq < compiler.variables.length) {
            compiler.chunk.memreq = cast(ubyte) compiler.variables.length;
        }
    }
}

public class VarAssignNode : Node {
    
    Token name;
    Node expr;

    this() {
        super("VarAssign");
    }

    public override void compile(Compiler compiler) {
        Variable* v = compiler.findVariable(name, true);
        if (v is null) return;
        expr.compile(compiler);
        Type t = compiler.pop();
        if (!compiler.areTypesCompatible(t, v.type, name)) {
            return;
        }
        v.initialized = true;
        compiler.chunk.write(name.line, OpSet.store, v.index);
    }
}

public class VarIncDecNode : Node {

    Token varName;
    Token operator;
    bool opFirstThenPush;

    this() {
        super("VarIncDec");
    }
    
    public override void compile(Compiler compiler) {
        Variable* v = compiler.findVariable(varName, true);
        if (v is null) return;    

        OpSet op = operator.type == TokenType.PlusPlus ? OpSet.incm : OpSet.decm;

        if (!v.type.isNumeric()) {
            compiler.writeError(varName, "Cannot increment variable '"d~v.name~"' of type '"d~v.type.toString()~"'"d);
            return;
        }

        compiler.push(v.type);

        if (opFirstThenPush) {
            compiler.chunk.write(varName.line, op, v.index);
            compiler.chunk.write(varName.line, OpSet.load, v.index);
        } else {
            compiler.chunk.write(varName.line, OpSet.load, v.index);
            compiler.chunk.write(varName.line, op, v.index);
        }
    }
}