module irie.bytes;

import std.bitmanip;

public import irie.values;
public import irie.exe;

public enum OpSet : ubyte {
    push,
    pushl,
    pop,

    ptrue,
    pfalse,
    pnull,

    add,
    sub,
    mul,
    mod,
    div,
    equ,
    diff,
    greater,
    less,
    lssequ,
    grtrequ,

    concat,
    strlen,
    strlenpop,

    newarr,
    alength,
    alengthpop,
    aload,
    astore,
    aloadpop,
    astorepop,

    neg,
    inv,

    load,
    store,
    incm,
    decm,

    jmp,
    jmpf,
    jmpb,

    invoke,
    invokew,
    interrupt, // yes, Irie has interrupts.
    // in fact, 2^16 of them! (they aren't really interrupts though)

    ret = 0xFF,
}

public struct LineRange {
    uint endOffset;
    uint line;
}

public struct Chunk {
    ubyte memreq;
    ubyte[] instructions;
    Value[] values;
    LineRange[] lines;
    string name, filename;

    void write(int line, ubyte[] op...) {
        this.instructions ~= op;
        if (lines.length > 0 && lines[lines.length - 1].line == line) {
            lines[lines.length-1].endOffset += op.length;
        } else {
            lines ~= LineRange(cast(uint)(instructions.length), line);
        }
    }

    void writePush(int line, Value v) {
        uint i = cast(uint) values.length;
        values ~= v;
        if (i >= ubyte.max) {
            write(line, OpSet.pushl);
            write(line, nativeToLittleEndian((cast(ushort)i)));
        } else {
            write(line, OpSet.push, cast(ubyte) i);
        }
    }

    uint getLine(size_t endOffset) {
        uint lastLine = 0;
        foreach (LineRange range ; lines) {
            if (range.endOffset > endOffset) {
                return range.line;
            }
            lastLine = range.line;
        }
        return lastLine;
    }
}