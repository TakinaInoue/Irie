module irie.compiler.ast.array;

import irie.compiler.ast.node;

public class ArrayLiteral : Node {

    Token start, end;
    Node[] elements;

    this() {
        super("ArrayLiteral");
    }

    override void compile(Compiler cc) {
        cc.chunk.writePush(start.line, Value(cast(int)elements.length));
        cc.chunk.write(start.line, OpSet.newarr);

        Type arrayType = CompilationRegistry.unknownType;
        arrayType.objectType  = ObjectType.Array;
        arrayType.logicalType = ValueType.Object;
        arrayType.dimensions  = 0;

        for (int i = 0; i < elements.length; i++) {
            Node nd = elements[i];
            cc.chunk.writePush(start.line, Value(i));
            nd.compile(cc);
            Type vType = cc.pop();
            if (i == 0) {
                if (vType.isArray())
                    arrayType.dimensions = 1;
                arrayType.name = vType.name;
                arrayType.objectType = vType.objectType;
                arrayType.logicalType = vType.logicalType;
            } else if (!cc.areTypesCompatible(vType, arrayType, end)) {
                import std.stdio;
                writeln(vType," ", arrayType);
                continue;
            }
            cc.chunk.write(start.line, OpSet.astore);
        }
        
        // reason it starts off as 0 dimensions is because it supposed to start off like
        // an element type, it only now becomes the actual array's type.
        arrayType.dimensions++;
        cc.push(arrayType);
    }
}

public class ArrayAccessLiteral : Node {

    Node[] operands;
    Token arrayName;

    this() {
        super("ArrayAccessLiteral");
    }

    override void compile(Compiler cc) {
        Variable* v = cc.findVariable(arrayName, true);
        if (v is null)
            return;
        bool isString = v.type.isObject(ObjectType.String) && v.type.dimensions == 0;
        if (!v.type.isArray() && !isString) {
            cc.writeError(arrayName, "Cannot index non-array variable.");;
            return;
        }
        if (isString && v.type.dimensions == 0) v.type.dimensions = 1;
        cc.chunk.write(arrayName.line, OpSet.load, v.index);
        if (operands.length > v.type.dimensions) {
            cc.writeError(arrayName, format("Bad indexing for array of %d dimensions, %u dimension indexes specified."d,
                                    v.type.dimensions, operands.length));
            return;
        }

        int dimensionCount = v.type.dimensions;
        foreach (Node operand ; operands) {
            operand.compile(cc);
            Type t = cc.pop();
            if (t.logicalType != ValueType.Int || t.isArray()) {
                cc.writeError(arrayName, "Cannot use a "d ~ t.toString ~ " to index arrays (must be an integer).");
                return;
            }
            cc.chunk.write(arrayName.line, OpSet.aloadpop);  
            dimensionCount--;
        }
        cc.push(v.type.nDimension(dimensionCount));
    }
}

public class ArrayAssignNode : Node {

    Node value;
    Node[] operands;
    Token arrayName, equSign;

    this() {
        super("ArrayAssign");
    }

    override void compile(Compiler cc) {
        Variable* v = cc.findVariable(arrayName, true);
        if (v is null)
            return;
        bool isString = v.type.isObject(ObjectType.String);
        if (!v.type.isArray() && !isString) {
            cc.writeError(arrayName, "Cannot index non-array variable.");;
            return;
        }
        cc.chunk.write(arrayName.line, OpSet.load, v.index);
        if (isString && v.type.dimensions == 0) v.type.dimensions = 1;
        if (operands.length > v.type.dimensions) {
            cc.writeError(arrayName, format("Bad indexing for array of %d dimensions, %u dimension indexes specified."d,
                                    v.type.dimensions, operands.length));
            return;
        }

        int dimensionCount = v.type.dimensions;
        for (size_t i = 0; i < operands.length; i++) {
            Node operand = operands[i];
            operand.compile(cc);
            Type t = cc.pop();
            if (t.logicalType != ValueType.Int || t.isArray()) {
                cc.writeError(arrayName, "Cannot use a "d ~ t.toString ~ " to index arrays (must be an integer).");
                return;
            }
            dimensionCount--;
            if (i + 1 < operands.length) {
                cc.chunk.write(arrayName.line, OpSet.aloadpop);  
            } else {
                value.compile(cc);
                Type td = cc.pop();
                Type elmType = v.type.nDimension(dimensionCount);
         /*     no longer immutable (immutable strings are annoying.) 
                if (!elmType.isArray() && elmType.isObject(ObjectType.String)) {
                    cc.writeError(equSign, "You cannot change individual chars of strings.");
                    return;
                }*/
                if (!(isString && td.logicalType == ValueType.Char) &&
                    !cc.areTypesCompatible(td, elmType, equSign)) { 
                    return; 
                }
                cc.chunk.write(arrayName.line, OpSet.astorepop);  
            }
        }
    }
}