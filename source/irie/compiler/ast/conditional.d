module irie.compiler.ast.conditional;

import irie.compiler.ast.node;

public class WhileNode : Node {

    Token whileToken, eof;
    Node condition;
    Node body_;

    this() {
        super("While");
    }
    
    public override void compile(Compiler compiler) {
        size_t loopStart = compiler.chunk.instructions.length;

        condition.compile(compiler);
        
        Type t = compiler.pop();
        if (t.logicalType != ValueType.Boolean) {
            compiler.writeError(whileToken, "While statement condition expression does not result in a boolean.");
            return;
        }

        size_t exitJmp = compiler.writeJump(whileToken.line, OpSet.jmpf);
        body_.compile(compiler);
        
        compiler.patchLoop(eof, loopStart);
        compiler.patchJump(whileToken, exitJmp);
    }
}

public class IfNode : Node {

    Token ifToken;
    Node condition;
    Node body_;

    Token elseToken;
    Node nextInChain;

    this() {
        super("If");
    }

    public override void compile(Compiler compiler) {
        condition.compile(compiler);
        Type t = compiler.pop();
        if (t.logicalType != ValueType.Boolean) {
            compiler.writeError(ifToken, "If statement condition expression does not result in a boolean.");
            return;
        }

        size_t exitJmp = compiler.writeJump(ifToken.line, OpSet.jmpf);

        body_.compile(compiler);

        size_t nextInChainIgnore;
        if (nextInChain !is null) {
            nextInChainIgnore = compiler.writeJump(elseToken.line, OpSet.jmp);
        }
        
        compiler.patchJump(ifToken, exitJmp);

        if (nextInChain !is null)  {
            nextInChain.compile(compiler);
            compiler.patchJump(elseToken, nextInChainIgnore);
        }
    }

}