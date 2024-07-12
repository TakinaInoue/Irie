module irie.obj;

import std.utf;
import std.range : popFront;

import irie.values;

public enum ObjectType : ubyte {
    Array,
    String,
}   

public class ObjectManager {

    public static:
        IrieObject[] objects;

        void reset() {
            objects = null;
        }

        IrieObject getObject(uint offs) {
            if (offs >= objects.length) return null;
            return objects[offs];
        }

        uint addExisting(IrieObject obj) {
            uint of = cast(uint)objects.length;
            objects ~= obj;
            return of;
        }

        template newObject(T, Arg) {
            uint newObject(Arg arg) {
                T t = new T(arg);
                return addExisting(t);
            }
        }

}

public abstract class IrieObject {
    const ObjectType type;

    this(ObjectType t) {
        this.type = t;
    }

    abstract wstring asString();
}

public class ArrayObject : IrieObject {
    Value[] values;

    this(size_t length) {
        super(ObjectType.Array);
        values = new Value[length];
    }

    override wstring asString() {
        wstring a = "[";
        for (size_t i = 0; i < values.length; i++) {
            a ~= toUTF16(values[i].toString());
            if (i + 1 < values.length) a~=',';
        }
        return a ~"]";
    }
}

public class StringObject : IrieObject {
    wchar[] characters;

    this(wstring msg = "") {
        super(ObjectType.String);
        this.characters = cast(wchar[]) msg;
    }

    override wstring asString() {
        return cast(wstring) characters;
    }
}