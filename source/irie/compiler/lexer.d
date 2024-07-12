module irie.compiler.lexer;

import std.utf;
import std.ascii;

public enum TokenType : ubyte {
    Invalid, EndOfFile,

    Identifier, 
    CharLiteral, StringLiteral,
    FloatLiteral, IntLiteral,

    Plus, Minus, Star, Slash, Modulo, Power,
    PlusPlus, MinusMinus,
    Dot, Comma, Semicolon, DoubleDot,
    TwoDots,

    Not,
    Equals,
    
    EqualsEquals,
    NotEquals,
    Greater,
    GreaterEquals,
    Less,
    LessEquals,

    LeftParen, RightParen,
    LeftSquare, RightSquare,
    LeftBrace, RightBrace,

    KeywordVar,
    KeywordFunction,
    KeywordReturn,
    KeywordImport,

    KeywordIf,
    KeywordElse,
    KeywordWhile,
    KeywordTrue,
    KeywordFalse,
    KeywordUnknown,

    KeywordEnum,

    // compile time only!
    KeywordTypeof,
}


public struct Token {
    TokenType type;
    dstring data;
    uint line, column;
    size_t position;

    int getSuffixOpPrec() {
        switch(type) {
            case TokenType.Not:
                return 1;
            default: return 0;
        }
    }
    
    int getUnaryOpPrec() {
        switch(type) {
            case TokenType.Not:
            case TokenType.Minus:
            case TokenType.PlusPlus:
            case TokenType.MinusMinus:
                return 1;
            default: return 0;
        }
    }

    int getBinaryOpPrec() {
        switch(type) {
            case TokenType.Power:
                return 8;
            case TokenType.Modulo:
            case TokenType.Slash:
            case TokenType.Star:
                return 5;
            case TokenType.Plus:
            case TokenType.Minus:
                return 4;
            case TokenType.EqualsEquals:
            case TokenType.NotEquals:
            case TokenType.Greater:
            case TokenType.GreaterEquals:
            case TokenType.Less:
            case TokenType.LessEquals:
                return 2;
            default: return 0;
        }
    }
}

public class Lexer {

    dstring text;
    size_t position;
    uint line, column;
    dchar current;
    TokenType[dstring] keywords;

    this(string text) {
        this.text = toUTF32(text);
        this.position = 0;
        this.line = 1;
        this.column = 1;

        keywords["var"] = TokenType.KeywordVar;
        keywords["let"] = TokenType.KeywordVar;
        keywords["if"] = TokenType.KeywordIf;
        keywords["else"] = TokenType.KeywordElse;
        keywords["while"] = TokenType.KeywordWhile;
        keywords["function"] = TokenType.KeywordFunction;
        keywords["return"] = TokenType.KeywordReturn;
        keywords["import"] = TokenType.KeywordImport;

        keywords["true"] = TokenType.KeywordTrue;
        keywords["false"] = TokenType.KeywordFalse;
        keywords["unknown"] = TokenType.KeywordUnknown;

        
        keywords["typeof"] = TokenType.KeywordTypeof;
        this.nextChar();
    }

    Token next() {
        while (isWhite(current) && current != '\0')
            nextChar();
        if (current == '\0') {
            return makeToken(TokenType.EndOfFile);
        }   

        if (isDigit(current)) {
            dstring acc = "";
            TokenType type = TokenType.IntLiteral;
            while ((current == '.' || isDigit(current)) && current != '\0') {
                if (current == '.') { 
                    nextChar();
                    if (type == TokenType.FloatLiteral)
                        return makeToken(type, acc);
                    acc ~= ".";
                    type = TokenType.FloatLiteral;
                    continue;
                }
                acc ~= nextChar();
            }
            if (current == 'd' || current == 'f') {
                nextChar();
                type = TokenType.FloatLiteral;
            } else if (current == 'i' || current == 'l') {
                nextChar();
                type = TokenType.IntLiteral;
            }
            return makeToken(type, acc);
        }
        if (isAlpha(current) || current == '_') {
            dstring acc = "";
            while ((isAlpha(current) || current == '_' || isDigit(current)) && current != '\0') {
                acc ~= nextChar();
            }
            TokenType* type = acc in keywords;
            return makeToken(type is null ? TokenType.Identifier : *type, acc);
        }
        if (current == '\'' || current == '\"') {
            dchar startCh = current;
            nextChar();
            dstring c = "";
            while (current != startCh && current != '\0') {
                dchar strCurrent = nextChar();
                if (strCurrent == '\\') {
                    switch(current) {
                        case 'n': c~='\n';break;
                        case 't': c~='\t';break;
                        case '"': c~='"';break;
                        case '\'': c~='\'';break;
                        case '\\': c~='\\';break;
                        default: break;
                    }
                    nextChar();
                    continue;
                }
                c ~= strCurrent;
            }
            nextChar(); // skip closing quote
            return makeToken(startCh == '\'' ? TokenType.CharLiteral : TokenType.StringLiteral,
                             startCh == '\'' ? [c[0]] : c);
        }

        switch(current) {
            mixin(tmplSingleCharSymb!('^', "Power"));
            mixin(tmplMultiCharSymb !('+', '+', "Plus", "PlusPlus"));
            mixin(tmplMultiCharSymb !('-', '-', "Minus", "MinusMinus"));
            mixin(tmplSingleCharSymb!('*', "Star"));
            mixin(tmplSingleCharSymb!('/', "Slash"));
            mixin(tmplSingleCharSymb!('%', "Modulo"));
            
            mixin(tmplMultiCharSymb !('.', '.', "Dot", "TwoDots"));
            mixin(tmplSingleCharSymb!(',', "Comma"));
            mixin(tmplSingleCharSymb!(':', "DoubleDot"));
            mixin(tmplSingleCharSymb!(';', "Semicolon"));

            mixin(tmplMultiCharSymb!('=', '=', "Equals", "EqualsEquals"));
            mixin(tmplMultiCharSymb!('!', '=', "Not", "NotEquals"));
            mixin(tmplMultiCharSymb!('>', '=', "Greater", "GreaterEquals"));
            mixin(tmplMultiCharSymb!('<', '=', "Less", "LessEquals"));

            mixin(tmplSingleCharSymb!('(', "LeftParen"));
            mixin(tmplSingleCharSymb!(')', "RightParen"));
            mixin(tmplSingleCharSymb!('{', "LeftBrace"));
            mixin(tmplSingleCharSymb!('}', "RightBrace"));
            mixin(tmplSingleCharSymb!('[', "LeftSquare"));
            mixin(tmplSingleCharSymb!(']', "RightSquare"));
            default:
                return makeToken(TokenType.Invalid, [nextChar()]);
        }
    }

    private:
    Token makeToken(TokenType type, dstring m = "") {
        return Token(type, m, this.line, this.column, this.position);
    }
 
    dchar nextChar() {
        dchar last = current;
        if (position >= text.length) 
            current = '\0';
        else current = text[position++];
        if (current == '\n') {
            this.line++;
            this.column = 1;
        } else {
            this.column++;
        }
        return last;
    }
}

private template tmplSingleCharSymb(char symb, string type) {
    const char[] tmplSingleCharSymb = "
        case '"~symb~"': return makeToken(TokenType."~type~", [nextChar()]);
    ";
}

private template tmplMultiCharSymb(char symb, char additional, string type, string combType) {
    const char[] tmplMultiCharSymb = "
        case '"~symb~"': {
            dchar c = nextChar();
            if (current == '"~additional~"') {
                return makeToken(TokenType."~combType~", [c, nextChar()]);
            }
            return makeToken(TokenType."~type~", [c]);
        }
    ";
}