module irie.compiler.ast.expr;

import std.bitmanip;

import irie.compiler.ast.node;

public class LiteralNode : Node {

    Token literal;

    this(Token literal) {
        super("Literal");
        this.literal = literal;
    }

    public override void compile(Compiler cc) {
        size_t index = 0;
        Type type;
        switch(literal.type) {
            case TokenType.Identifier: {
                Variable* v = cc.findVariable(literal, true);
                if (v is null) return;
                if (!v.initialized) {
                    cc.push(CompilationRegistry.unknownType);
                    cc.writeError(literal, "'"d ~ v.name ~ "' wasn't initialized."d);
                    return;
                }
                cc.push(v.type);
                cc.chunk.write(literal.line, OpSet.load, v.index);
                return;
            }
            case TokenType.KeywordTrue:
                cc.push(CompilationRegistry.boolType);
                cc.chunk.write(literal.line, OpSet.ptrue);
                return;
            case TokenType.KeywordFalse:
                cc.push(CompilationRegistry.boolType);
                cc.chunk.write(literal.line, OpSet.pfalse);
                return;
            case TokenType.KeywordUnknown:
                cc.push(CompilationRegistry.unknownType);
                cc.chunk.write(literal.line, OpSet.pnull);
                return;
            case TokenType.StringLiteral:
            case TokenType.FloatLiteral:
            case TokenType.IntLiteral:
            case TokenType.CharLiteral:
                index = cc.getValueId(literal, type);
                break;
            default:
                throw new Exception("Literal not implemented.");
        }
        cc.push(type);
        if (index >= ubyte.max) {
            cc.chunk.write(literal.line, OpSet.pushl);
            cc.chunk.write(literal.line, nativeToLittleEndian!ushort(cast(ushort)index));
        } else {
            cc.chunk.write(literal.line, OpSet.push, cast(ubyte) index);
        }
    }
}

public class UnaryNode : Node {

    Node operand;
    Token operator;

    this(Token operator, Node operand) {
        super("Unary");
        this.operator = operator;
        this.operand = operand;
    }

    public override void compile(Compiler cc) {
        operand.compile(cc);
        Type t = cc.pop();
        if (operator.type == TokenType.Minus) {
            if (!t.isNumeric())
                cc.writeError(operator, "Cannot perform unary '"~operator.data~"' when operand isn't numeric.");
            else 
                cc.chunk.write(operator.line, OpSet.neg);
            cc.push(t);
        } else if (operator.type == TokenType.Not) {
            if (!t.logicalType == ValueType.Boolean)
                cc.writeError(operator, "Cannot perform unary '"~operator.data~"' when operand isn't a boolean.");
            else 
                cc.chunk.write(operator.line, OpSet.inv);
            cc.push(CompilationRegistry.boolType);
        } else {
            throw new Exception("Unimplemented Unary Operator");
        }
    }
}

public class BinaryNode : Node {

    Node left, right;
    Token operator;

    this(Node left, Token operator, Node right) {
        super("Binary");
        this.left = left;
        this.operator = operator;
        this.right = right;
    }

    bool isNumericOperator() {
        return operator.type != TokenType.EqualsEquals && operator.type != TokenType.NotEquals;
    }

    public override void compile(Compiler cc){ 
        left.compile(cc);
        right.compile(cc);

        Type b = cc.pop();
        Type a = cc.pop();

        if ((a.isObject(ObjectType.String) || b.isObject(ObjectType.String)) &&
            operator.type == TokenType.Plus) {
            cc.push(CompilationRegistry.stringType);
            if (a.objectType != b.objectType) {
                cc.writeError(operator, "Cannot concatenate a "~ a.toString() ~ " with an " ~ b.toString());
                return;
            }
            cc.chunk.write(operator.line, OpSet.concat);
            return;
        }

        if (isNumericOperator() && (!a.isNumeric() || !b.isNumeric())) {
            cc.writeError(operator, "Cannot perform '"d~operator.data
            ~"' when one of the operands isn't numeric. ("d ~a.name ~  " and "d~b.name~")"d);
        }

        Type dst = a.logicalType > b.logicalType ? a : b;

        switch(operator.type) {
            case TokenType.Plus: cc.chunk.write(operator.line, OpSet.add); break;
            case TokenType.Minus: cc.chunk.write(operator.line, OpSet.sub); break;
            case TokenType.Star: cc.chunk.write(operator.line, OpSet.mul); break;
            case TokenType.Slash: cc.chunk.write(operator.line, OpSet.div); break;
            case TokenType.Modulo: cc.chunk.write(operator.line, OpSet.mod); break;
            
            case TokenType.Greater:
                dst = CompilationRegistry.boolType;
                cc.chunk.write(operator.line, OpSet.greater); break;
            case TokenType.Less:
                dst = CompilationRegistry.boolType;
                cc.chunk.write(operator.line, OpSet.less); break;
            case TokenType.GreaterEquals:
                dst = CompilationRegistry.boolType;
                cc.chunk.write(operator.line, OpSet.grtrequ); break;
            case TokenType.LessEquals:
                dst = CompilationRegistry.boolType;
                cc.chunk.write(operator.line, OpSet.lssequ); break;
            case TokenType.EqualsEquals:
                dst = CompilationRegistry.boolType;
                cc.chunk.write(operator.line, OpSet.equ); break;
            case TokenType.NotEquals:
                dst = CompilationRegistry.boolType;
                cc.chunk.write(operator.line, OpSet.diff); break;
            default: throw new Exception("Unimplemented binary op");
        }
        cc.push(dst);
    }
}