module irie.native;

import std.string;
import std.stdio : write, readln;
import std.file : thisExePath, isDir, isFile, exists, getSize;

import irie.vm;
import irie.compiler.ast.node;

string libraryPath;

alias IrieNativeFunc = int function(IrieVM vm);

struct IrieNativeSymbol {
    // metadata only for the compiler though \/
    dstring name;
    int argCount;
    Type returnType;
    ushort offset;
    // only thing that matters \/
    IrieNativeFunc func;
}

IrieNativeSymbol[] nativeSymbols;

void loadInterrupts() {
    if (nativeSymbols.length > 0) return;
    libraryPath = thisExePath();
    version(Windows) {
        libraryPath = libraryPath[0 .. libraryPath.lastIndexOf("\\")+1] ~ "lib\\";
    } else {
        libraryPath = libraryPath[0 .. libraryPath.lastIndexOf("/")+1] ~"lib/";
    }
    nativeSymbols = [
        IrieNativeSymbol(
            "IVM_STDOUT_Write",
            1,
            CompilationRegistry.voidType,
            cast(ushort)nativeSymbols.length++,
            &ivmWrite
        ),
        IrieNativeSymbol(
            "IVM_STDIN_READLN",
            0,
            CompilationRegistry.stringType,
            cast(ushort)nativeSymbols.length++,
            &ivmReadln
        ),
        IrieNativeSymbol(
            "IVM_FILE_STAT",
            2,
            CompilationRegistry.unknownType,
            cast(ushort)nativeSymbols.length++,
            &ivmFSCheck
        )
    ];
}

private:
int ivmWrite(IrieVM vm) {
    Value v = vm.pop();
    write(v.toString());
    return 0;
}

int ivmReadln(IrieVM vm) {
    vm.push(Value(new StringObject(readln!wstring()[0 .. $-1])));
    return 0;
}

// 0 - exists
// 1 - isFile
// 2 - isDir
// 3 - size
int ivmFSCheck(IrieVM vm) {
    Value op   = vm.pop();
    Value name = vm.pop();

    auto str = name.asString;
    bool fileExists = exists(str);
    if (op.int_ == 0 || !fileExists) {
        vm.push(Value(fileExists));
    } else if (op.int_ == 1) {
        vm.push(Value(isFile(str)));
    } else if (op.int_ == 2) {
        vm.push(Value(isDir(str)));
    } else {
        vm.push(Value(cast(int)getSize(str)));
    }
    return 0;
}