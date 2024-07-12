module irie.values;

import std.utf;
import std.format;

public import irie.obj;

public enum ValueType : ubyte {
    Unknown, Int, Float,
    Boolean, Char,
    Object,
}

public struct Value {
    ValueType type;
    union {
        float float_;
        int int_;
        bool boolean;

        uint offset;
    }

    IrieObject object() {return ObjectManager.getObject(this.offset);}

    bool isNumber() {
        return type == ValueType.Float || type == ValueType.Int;
    }

    this(float float_) {
        this.float_ = float_;
        this.type = ValueType.Float;
    }

    this(int int_) {
        this.int_ = int_;
        this.type = ValueType.Int;
    }

    this(bool b) {
        this.boolean = b;
        this.type = ValueType.Boolean;
    }

    this(dchar c) {
        this.type = ValueType.Char;
        this.int_ = c;
    }

    this(IrieObject object) {
        this.offset = ObjectManager.addExisting(object);
        this.type = ValueType.Object;
    }

    this(ValueType p) {
        this.type = p;
    }

    string toString() {
        return toUTF8(asString());
    }

    wstring asString() {
        switch(type) {
            case ValueType.Float: return format("%gf"w, this.float_);
            case ValueType.Int: return format("%g"w, this.int_);
            case ValueType.Boolean: return this.boolean ? "true"w : "false"w;
            case ValueType.Char: return toUTF16([cast(dchar)this.int_]);
            case ValueType.Object: {
                auto r = this.object;
                if (r is null) return "null-object"w;
                return r.asString();
            }
            case ValueType.Unknown: return "unknown"w;
            default:
                return "unknown"w;
        }
    }

    bool isEqualTo(Value other) {
        if (this.type != other.type) return false;
        switch(this.type) {
            case ValueType.Float:
                return this.float_ == other.float_; // awful idea..
            case ValueType.Char:
            case ValueType.Int:
                return this.int_ == other.int_;
            case ValueType.Boolean:
                return this.boolean == other.boolean;
            case ValueType.Object: {
                IrieObject a = ObjectManager.getObject(this.offset);
                IrieObject b = ObjectManager.getObject(other.offset);
                return (a !is null && b !is null) && ((a == b) || (a.type == b.type));
            }
            default:
                throw new Exception("Cannot check if value is equals to another.");
        }
    }

    void castTo(ValueType type) {
        if (this.type == type) return;
        switch(type) {
            case ValueType.Float: {
                if (this.type == ValueType.Boolean) {
                    this.float_ = cast(float) this.boolean;
                } else {
                    this.float_ = this.int_;
                }
                break;
            }
            default:
                if (this.type == ValueType.Boolean) {
                    this.int_ = cast(int) this.boolean;
                } else if (this.type == ValueType.Char) {
                    // nothing..
                } else {
                    this.int_ = cast(int) this.float_;
                }
                break;
        }
        this.type = type;
    }
}