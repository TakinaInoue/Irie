module irie.exe;

import irie.bytes;
import std.bitmanip;

import std.utf;
import std.stdio;
import std.string : toStringz;

static const uint IRIEVER_HIGH = 0x00000001;
static const uint IRIEVER_LOW  = 0x00000000;

public struct IrieExecutable {

    int entryPoint;
    Chunk[] chunks;

    void read(string filename, out bool failed) {
        Value readValue(ubyte[5] valueData) {
            Value v;
            v.type = cast(ValueType) valueData[0];
            v.offset = littleEndianToNative!uint(valueData[1 .. 5]);
            return v;
        }

        this.chunks = null;
        this.entryPoint = -1;

        File file = File(filename, "rb");
        ubyte[20] PEHeader;
        file.rawRead(PEHeader);
        if (PEHeader[0 .. 4] != ['I','R','I','E']) {
            failed = true;
            writeln("Not an irie executable.");
            return;
        }
        uint irieVer = littleEndianToNative!uint(PEHeader[4 .. 8]);
        if (irieVer > IRIEVER_HIGH ||  irieVer < IRIEVER_LOW) {
            failed = true;
            writeln("Irie Executable incompatible. (VM versions accepted: ",IRIEVER_LOW, " to ", IRIEVER_HIGH,
            ", executable version ",irieVer,")");
            return;
        }
        this.entryPoint = littleEndianToNative!int(PEHeader[8 .. 12]);
        uint chunkCount = littleEndianToNative!uint(PEHeader[12 .. 16]);
        uint objectCount = littleEndianToNative!uint(PEHeader[16 .. 20]);

        // load all executable's objects into VM
        for (uint ob = 0; ob < objectCount; ob++) {
            ubyte[5] objectMeta;
            file.rawRead(objectMeta);
            uint dSize = littleEndianToNative!uint(objectMeta[1 .. 5]);
            ObjectType typ = cast(ObjectType) objectMeta[0];
            switch(typ) {
                case ObjectType.String: {
                    wchar[] str = new wchar[dSize];
                    file.rawRead(str);
                    ObjectManager.objects ~= new StringObject(cast(wstring) str);
                    break;
                }
                case ObjectType.Array: {
                    ArrayObject arr = new ArrayObject(dSize);
                    for (size_t i = 0; i < dSize; i++) {
                        ubyte[5] vData;
                        file.rawRead(vData);
                        arr.values[i] = readValue(vData);
                    }
                    ObjectManager.objects ~= arr;
                    break;
                }
                default:
                    throw new Exception("Unknown object type read.");
            }
        }

        for (uint i = 0; i < chunkCount; i++) {
            Chunk c;
            ubyte[21] lengths;
            file.rawRead(lengths);
            uint filenameLength   = littleEndianToNative!uint(lengths[0 .. 4]);
            uint nameLength       = littleEndianToNative!uint(lengths[4 .. 8]);
            uint linesLength      = littleEndianToNative!uint(lengths[8 .. 12]);
            uint valuesLength     = littleEndianToNative!uint(lengths[12 .. 16]);
            uint instLength       = littleEndianToNative!uint(lengths[16 .. 20]);
            c.memreq              = lengths[20];

            c.filename = cast(string) file.rawRead(new char[filenameLength]);      
            c.name     = cast(string) file.rawRead(new char[nameLength]);
            for (uint lr = 0; lr < linesLength; lr++) {
                ubyte[8] lineData;
                file.rawRead(lineData);
                c.lines ~= LineRange(
                    littleEndianToNative!uint(lineData[0 .. 4]),
                    littleEndianToNative!uint(lineData[4 .. 8])
                );
            }
            for (uint vr = 0; vr < valuesLength; vr++) {
                ubyte[5] valueData;
                file.rawRead(valueData);
                Value v = readValue(valueData);
                c.values ~= v;
            }
            c.instructions = file.rawRead(new ubyte[instLength]);
            chunks ~= c;
        }

        file.close();
    }

    void write(string filename) {
        void WriteValue(ref ubyte[] buff, Value v) {
            buff ~= v.type;
            buff ~= nativeToLittleEndian!uint(v.offset);
        }
        
        ubyte[] PEHeader = [
            'I', 'R', 'I', 'E',
        ];
        PEHeader ~= nativeToLittleEndian!uint(IRIEVER_HIGH);
        PEHeader ~= nativeToLittleEndian!int (cast(int)  entryPoint);
        PEHeader ~= nativeToLittleEndian!uint(cast(uint)chunks.length);
    
        PEHeader ~= nativeToLittleEndian!uint(cast(uint)ObjectManager.objects.length);
        foreach (IrieObject obj ; ObjectManager.objects) {
            PEHeader ~= obj.type;
            switch(obj.type) {
                case ObjectType.String: {
                    StringObject str = cast(StringObject) obj;
                    PEHeader ~= nativeToLittleEndian!uint(cast(uint) str.characters.length);
                    PEHeader ~= cast(ubyte[])str.characters;
                    break;
                }
                case ObjectType.Array: {
                    ArrayObject arr = cast(ArrayObject) obj;
                    PEHeader ~= nativeToLittleEndian!uint(cast(uint) arr.values.length);
                    foreach (Value v; arr.values) {
                        WriteValue(PEHeader, v);
                    }
                    break;
                }
                default: throw new Exception("Unknown object type.");
            }
        }

        File file = File(filename, "wb");
        file.rawWrite(PEHeader);

        foreach (Chunk c ; chunks) {
            ubyte[] PEChunk;
            PEChunk ~= nativeToLittleEndian!uint(cast(uint) c.filename.length);
            PEChunk ~= nativeToLittleEndian!uint(cast(uint) c.name.length);
            PEChunk ~= nativeToLittleEndian!uint(cast(uint) c.lines.length);
            PEChunk ~= nativeToLittleEndian!uint(cast(uint) c.values.length);
            PEChunk ~= nativeToLittleEndian!uint(cast(uint) c.instructions.length);
            PEChunk ~= c.memreq;

            PEChunk ~= cast(ubyte[])(c.filename);
            PEChunk ~= cast(ubyte[])(c.name);
            foreach (LineRange range ; c.lines) {
                PEChunk ~= nativeToLittleEndian!uint(range.endOffset);
                PEChunk ~= nativeToLittleEndian!uint(range.line);
            }
            foreach (Value v ; c.values) {
                WriteValue(PEChunk, v);
            }
            file.rawWrite(PEChunk);
            file.rawWrite(c.instructions);
        }
        file.close();   
    }
}