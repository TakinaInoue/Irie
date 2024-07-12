module irie.compiler.ast.interstricts;

import std.bitmanip;

import irie.compiler.ast.node;

public class TypeofNode : Node {
    Node operand;
    Token tk;

    this() {
        super("Typeof");
    }

    public override void compile(Compiler cc) {
        //TODO block operand from actually building?
        operand.compile(cc);
        Type t = cc.pop();
        Token tok = Token(TokenType.StringLiteral, t.toString());
        size_t index = cc.getValueId(tok, t);
        cc.chunk.write(tk.line, OpSet.pop);
        if (index >= ubyte.max) {
            cc.chunk.write(tk.line, OpSet.pushl);
            cc.chunk.write(tk.line, nativeToLittleEndian!ushort(cast(ushort)index));
        } else {
            cc.chunk.write(tk.line, OpSet.push, cast(ubyte) index);
        }
        
    }
}