module irie.dism;

import std.stdio;
import std.bitmanip;

import irie.bytes;

void dissasembleIExe(IrieExecutable exe) {
    writeln("== irie portable executable dissasembly ==");
    writeln("iexe entry point index: ", exe.entryPoint);
    foreach (Chunk c ; exe.chunks) {
        dissasemble(&c);
    }
}

void dissasemble(Chunk* chunk) {
    writeln("== dissassembly of chunk ",chunk.name, " from file ", chunk.filename, " ==");
    writeln("values: ", chunk.values);
    writeln("Line ranges: ", chunk.lines);
    writeln("local count: ", chunk.memreq);
    for (size_t i = 0; i < chunk.instructions.length;) {
        i = dissasembleInstruction(chunk, i);
    }
} 

size_t dissasembleInstruction(Chunk* chunk, size_t i) {
    ubyte it = chunk.instructions[i];
    writef("%03d %03d %s ", i, chunk.getLine(i), cast(OpSet)it);

    switch(it) {
        case OpSet.push: return singleByteOp(chunk, i);
        case OpSet.pushl: return twoByteOp(chunk, i);

        case OpSet.invoke:
        case OpSet.interrupt:
        case OpSet.jmp:
        case OpSet.jmpf:
        case OpSet.jmpb: return twoByteOp(chunk, i);
        
        case OpSet.load: 
        case OpSet.store:
        case OpSet.incm:
        case OpSet.decm:
            return singleByteOp(chunk, i);

        case OpSet.invokew:
            return fourByteOp(chunk, i);
        default:
            writeln();
            return i + 1;
    }
}

private:
size_t singleByteOp(Chunk* chunk, size_t i) {
    writeln(chunk.instructions[i+1]);
    return i + 2;
}
size_t twoByteOp(Chunk* chunk, size_t i) {
    writeln(littleEndianToNative!ushort([chunk.instructions[i+1], chunk.instructions[i+2]]));
    return i + 3;
}
size_t fourByteOp(Chunk* chunk, size_t i) {
    writeln(littleEndianToNative!uint([
        chunk.instructions[i+1], chunk.instructions[i+2],
        chunk.instructions[i+3], chunk.instructions[i+4]
    ]));
    return i + 5;
}