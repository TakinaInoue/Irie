module irie.compiler.ast.type;

import irie.compiler.ast.node;

public struct Type {
    dstring name;
    ValueType logicalType;
    ObjectType objectType;
    int dimensions; 

    Type lowerDimensions() {return Type(name, logicalType, objectType, this.dimensions--);}
    Type zeroDimensions() {return Type(name, logicalType, objectType, this.dimensions);}
    Type nDimension(int nDim) {return Type(name, logicalType, objectType, nDim);}
    
    bool isVoid() {
        return this.name == "void" && logicalType == ValueType.Unknown;
    }

    bool isArray() {return dimensions > 0 || isObject(ObjectType.String);}
    
    bool isObject(ObjectType type) {
        return logicalType == ValueType.Object && objectType == type;
    }

    bool isNumeric() {
        return logicalType == ValueType.Float || logicalType == ValueType.Int ||
               logicalType == ValueType.Char;
    }

    dstring toString() const {
        dstring n = name;
        for (size_t i = 0; i < dimensions; i++) n ~= "[]";
        return n;
    }
}

public class TypeNode : Node {

    Token typename;
    int dimensions;

    this() {
        super("Type");
    }

    Type asCompilerType(Compiler cc) {
        Type primitiveType = cc.findType(typename);
        primitiveType.dimensions = this.dimensions;
        return primitiveType;  
    }

    override void compile(Compiler cc) {}
}