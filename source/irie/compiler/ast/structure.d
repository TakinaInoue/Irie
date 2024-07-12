module irie.compiler.ast.structure;

import irie.compiler.ast.node;

public class FieldGetNode : Node {
    Token fieldName;

    public this() {
        super("FieldGet");
    }

    public override void compile(Compiler compiler) {
        Type t = compiler.pop();

        if (t.isObject(ObjectType.String)) {
            if (fieldName.data != "length"d) {
                compiler.writeError(fieldName, "Strings do not have the field '"~fieldName.data~"'.");
                return;
            }
            compiler.chunk.write(fieldName.line, OpSet.strlenpop);
            compiler.push(CompilationRegistry.intType);
        } else if (t.isArray()) {
            if (fieldName.data != "length"d) {
                compiler.writeError(fieldName, "Arrays do not have the field '"~fieldName.data~"'.");
                return;
            }
            compiler.chunk.write(fieldName.line, OpSet.alengthpop);
            compiler.push(CompilationRegistry.intType);
        } else {
            compiler.writeError(fieldName, "Irie does not know how to access field '"d
            ~fieldName.data~"' from a '"d~t.toString()~"'"d);
        }
    }
}