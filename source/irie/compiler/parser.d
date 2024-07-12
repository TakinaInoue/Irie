module irie.compiler.parser;

import std.utf;
import std.stdio;
import std.string;

import irie.bytes;
import irie.compiler.ast.node;

public class ParserResult {
    dstring filename;
    dstring[] modules;
    FuncNode[] functions;

    IrieExecutable compile(out bool failed) {
        writeln("Building... ", filename);

        IrieExecutable executable = IrieExecutable(-1);
        failed = false;
        foreach (FuncNode func ; functions) {
            func.setup(new Compiler(filename));
        }

        foreach (FuncNode func ; functions) {
            Compiler compiler = func.compiler;
            compiler.parserResult = this;
            func.compile(compiler);
            if (compiler.hadError) {
                failed = true;
                return executable;
            }
            if (func.name.data == "_start" && func.parameters.length == 0) {
                executable.entryPoint = cast(int)executable.chunks.length;
            }
            executable.chunks ~= compiler.chunk;
        }
        return executable;
    }
}

public class Parser {

    Lexer lexer;
    Token current;
    dstring filename;

    bool hadError;

    this(string filename, string source) {
        this.filename = toUTF32(filename);
        this.lexer = new Lexer(source);
        this.next();
        this.hadError = false;
    }

    ParserResult parse() {
        ParserResult parserResult = new ParserResult();
        parserResult.filename = filename;
        dstring[] modules;
        while (current.type != TokenType.EndOfFile) {
            if (consume(TokenType.KeywordImport)) {
                dstring pkgName = "";
                while (true) {
                    pkgName ~= match("Expected a valid package name.", TokenType.Identifier).data;
                    if (current.type == TokenType.Dot) {
                        pkgName ~= "/";
                        next();
                    } else break;
                }
                pkgName ~= ".irie";

                bool hasModule;
                for (size_t i = 0; i < modules.length; i++) 
                    if (modules[i] == pkgName) {
                        hasModule = true;
                        break;
                    }

                if (!hasModule) modules ~= pkgName;
            } else if (consume(TokenType.KeywordFunction))
                parserResult.functions ~= parseFunction();
            else {
                writeError("Unexpected '"~current.data~"' at this time.");
                next();
            }
        }
        parserResult.modules = modules;
        return parserResult;
    }

    private:
    FuncNode parseFunction() {
        FuncNode node = new FuncNode();
        node.name = match("Expected a valid function name.", TokenType.Identifier);
        match("Expected a left parenthesis.", TokenType.LeftParen);
        if (current.type != TokenType.RightParen) {
            do {
                Parameter p = Parameter(match("Expected a valid parameter name.", TokenType.Identifier));
                match("Expected a parameter type.", TokenType.DoubleDot);
                p.type = parseType();
                if (consume(TokenType.TwoDots) && consume(TokenType.Dot)) {
                    node.isLastParamAnArray = true;
                    break;
                }
                node.parameters ~= p;
            } while (consume(TokenType.Comma));
        }
        match("Expected a right parenthesis.", TokenType.RightParen);
        //TODO return type inference
        match("Expected a return type (irie does not support return type inference yet.)", TokenType.DoubleDot);
        node.returnType = parseType();
        node.body_ = parseBlock();
        return node;
    }

    BlockNode parseBlock() {
        match("Expected a left brace.", TokenType.LeftBrace);
        BlockNode node = new BlockNode();
        while (current.type != TokenType.RightBrace && current.type != TokenType.EndOfFile) {
            if (consume(TokenType.Semicolon)) continue;
            node.nodes ~= parseStatement();
        }
        node.end = match("Mismatched block braces.", TokenType.RightBrace);
        return node;
    }

    Node parseStatement() {
        if (current.type == TokenType.LeftBrace) {
            return parseBlock();
        } else if (consume(TokenType.KeywordVar)) {
            return parseVar();
        } else if (current.type == TokenType.KeywordIf) {
            return parseIf();
        } else if (current.type == TokenType.KeywordWhile) {
            return parseWhile();
        } else if (current.type == TokenType.KeywordReturn) {
            ReturnNode nd = new ReturnNode();
            nd.returnToken = next();
            if (!consume(TokenType.Semicolon) && current.type !=  TokenType.RightBrace) {
                if (current.line != nd.returnToken.line) {
                    writeError("This is likely unwanted behaviour, please delete this line.");
                }
                nd.expression = parseExpression();
            }
            return nd;    
        } else {
            return parseExpression();
        }
    }

    WhileNode parseWhile() {
        WhileNode nd = new WhileNode();
        nd.whileToken = next();
        nd.condition = parseExpression();
        nd.body_ = parseStatement();
        nd.eof = current;
        return nd;
    }

    IfNode parseIf() {
        IfNode nd = new IfNode();
        nd.ifToken = next();
        nd.condition = parseExpression();
        nd.body_ = parseStatement();

        if (current.type == TokenType.KeywordElse) {
            nd.elseToken = next();
            if (current.type == TokenType.KeywordIf) {
                nd.nextInChain = parseIf();
            } else {
                nd.nextInChain = parseStatement();
            }
        }   
        return nd;
    }

    VarNode parseVar() {
        VarNode node = new VarNode();
        node.name = match("Expected a valid variable name.", TokenType.Identifier);
        if (consume(TokenType.DoubleDot)) {
            node.type = parseType();
        } else {
            node.type = null;
        }
        if (consume(TokenType.Equals)) {
            node.assignValue = parseExpression();
        }
        return node;
    }

    TypeNode parseType() {
        TypeNode nd = new TypeNode();
        nd.typename = match("Expected a valid typename.", TokenType.Identifier, TokenType.KeywordUnknown);
        while (consume(TokenType.LeftSquare)) {
            match("Expected a ']' for this type.", TokenType.RightSquare);
            nd.dimensions++;
        }
        return nd;
    }

    Node parseExpression(int parentPrecedence = 0) {
        Node left;

        int unaryOperatorPrecedence = current.getUnaryOpPrec();

        if (unaryOperatorPrecedence != 0) {
            Token operatorType = this.next();
            if (operatorType.type == TokenType.PlusPlus || operatorType.type == TokenType.MinusMinus) {
                VarIncDecNode nd = new VarIncDecNode();
                nd.operator = operatorType;
                nd.varName = match("Expected a valid variable name.", TokenType.Identifier);
                nd.opFirstThenPush = true;
                left = nd;    
            } else {
                Node operand = parsePrimary();
                left = new UnaryNode(operatorType, operand);
            }
        } else {
            left = parsePrimary();
        }

        while (true) {
            int precedence = current.getBinaryOpPrec();

            if (precedence == 0 || precedence <= parentPrecedence)
                break;
            
            Token operator = next();
            Node right = parseExpression(precedence);
            left = new BinaryNode(left, operator, right);
        }

        return left;
    }

    Node parsePrimary() {
        CompoundNode checkFieldChain(Node n = null) {
            CompoundNode nd = new CompoundNode();
            if (n !is null) nd.nodes ~= n;
            while (consume(TokenType.Dot)) {
                FieldGetNode fgn = new FieldGetNode();
                fgn.fieldName = match("Expected a valid fieldname.", TokenType.Identifier);
                nd.nodes ~= fgn;
            }
            return nd;
        }
        if (consume(TokenType.LeftParen)) {
            Node n = parseExpression();
            match("Mismatched parenthesis.", TokenType.RightParen);
            return n;
        }
        if (current.type == TokenType.LeftSquare) {
            ArrayLiteral lit = new ArrayLiteral();
            lit.start = next();
            if (current.type != TokenType.RightSquare) {
                do {
                    lit.elements ~= parseExpression();
                } while (consume(TokenType.Comma));
            }
            lit.end = match("Expected a ] to end array.", TokenType.RightSquare);
            return checkFieldChain(lit); 
        }
        if (current.type == TokenType.Identifier) {
            Token id = next();
            if (consume(TokenType.Equals)) {
                VarAssignNode nd = new VarAssignNode();
                nd.name = id;
                nd.expr = parseExpression();
                return nd;
            } else if (current.type == TokenType.LeftSquare) {
                Node[] operands;
                while (consume(TokenType.LeftSquare)) {
                    operands ~= parseExpression();
                    match("Expected a ] to close array indexing.", TokenType.RightSquare);
                }
                if (current.type == TokenType.Equals) {
                    ArrayAssignNode nd = new ArrayAssignNode();
                    nd.arrayName = id;
                    nd.operands = operands;
                    nd.equSign = next();
                    nd.value = parseExpression();
                    return nd;
                }
                ArrayAccessLiteral nd = new ArrayAccessLiteral();
                nd.arrayName = id;
                nd.operands = operands;
                return checkFieldChain(nd);
            } else if (consume(TokenType.LeftParen)) {
                FunctionCallNode nd = new FunctionCallNode();
                nd.name = id;
                if (current.type != TokenType.RightParen) {
                    do {
                        nd.parameters ~= parseExpression();
                    } while (consume(TokenType.Comma));
                }
                match("Expected a mismatched call parenthesis.", TokenType.RightParen);
                return nd;
            } else if (current.type == TokenType.PlusPlus || current.type == TokenType.MinusMinus) {
                VarIncDecNode nd = new VarIncDecNode();
                nd.varName = id;
                nd.operator = next();
                nd.opFirstThenPush = false;
                return nd;
            }
            return checkFieldChain(new LiteralNode(id));
        }
        if (current.type == TokenType.KeywordTypeof) {
            TypeofNode nd = new TypeofNode();
            nd.tk = next();
            nd.operand = parseExpression();
            return nd;
        }
        if (current.type == TokenType.Dot)
            return checkFieldChain();
        return checkFieldChain(new LiteralNode(match("Expected a valid literal.",
            TokenType.FloatLiteral, TokenType.IntLiteral,
            TokenType.CharLiteral, TokenType.StringLiteral,
            TokenType.KeywordUnknown, TokenType.KeywordTrue, TokenType.KeywordFalse,
        )));
    }

    Token match(dstring error, TokenType[] types...) {
        foreach (TokenType t ; types) 
            if (current.type == t) {
                return next();
            }
        writeError(error);
        return next();
    }

    bool consume(TokenType t) {
        if (current.type == t) {
            next();
            return true;
        }
        return false;
    }

    void writeError(dstring error) {
        writeln(filename,  ":", current.line, ":", current.column, ": error: ", error);
        hadError = true;
    }

    Token next() {
        Token last = current;
        current = lexer.next();
        return last;
    }

}