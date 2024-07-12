import std.utf;
import std.file;
import std.stdio;
import std.string;
import std.algorithm;

import core.stdc.time;

import irie.vm;
import irie.compiler;

enum Operation {
	None,
	CompileOnly,
	RunSave,
	Dissasemble,
	Run
}

void main(string[] args) {
	bool measureTime = false;

	string targetFile;
	string outputFile;
	Operation operation = Operation.None;

	for (size_t i = 1; i < args.length; i++) {
		string arg = args[i];
		if (arg.startsWith("/") || arg.startsWith("-")) {
			string switchName = arg[1 .. $];
			if (switchName == "compileonly" || switchName == "co") {
				operation = Operation.CompileOnly;
			} else if (switchName == "output" || switchName == "o") {
				if (i + 1 >= args.length) {
					writeln("Correct usage: /output <filename>");
					return;
				}
				outputFile = args[++i];
				if (operation != Operation.CompileOnly) operation = Operation.RunSave;
			} else if (switchName == "dissassemble" || switchName == "dism") { 
				operation = Operation.Dissasemble;
			} else if (switchName == "measure" || switchName == "ms") {
				measureTime = true;
			} else {
				writeln("Unknown switch: ", switchName);
			}
		} else if (arg.endsWith(".irie") || arg.endsWith(".iexe")) {
			targetFile = arg;
			if (operation != Operation.CompileOnly && operation != Operation.Dissasemble)
				operation = Operation.Run;
		}
	}

	if (operation == Operation.None || targetFile.length == 0) {
writeln("
                                
 ------------ IrieScript 1.0
 --@----++--- Made with love and ambition by Miyuki
 --@------@-- 
 --++-----+-- 
 ---++++----- https://takina.jp.net/projects/irie
 ------------ 

Usage: irie [options] <filename>

Switches == (use '/' or '-' for switches, example: '-co' or '/co')
compileonly or co    - only assembles an irie executable
output or o          - sets output of compileonly
dissassemble or dism - dissassembles executable
measure or ms        - measures execution time of executable (no effect with /dism or with /co)

p.s: passing just an irie executable results in it being loaded and executed.
 and passing just an irie source file results in it being compiled and executed.
");
		return;
	}

	// shouldn't hurt to load these here
	if (operation != Operation.Dissasemble)
		loadInterrupts();

	if (targetFile.endsWith(".irie")) {
		if (outputFile.length < 1) {
			outputFile = targetFile.replace(".irie", ".iexe");
		}
	}
	debug {
		writeln("Operation: ", operation);
		writeln("Input File: ", targetFile, ", Output File: ", outputFile);
	}
	

	ObjectManager.reset();

	switch(operation) {
		case Operation.CompileOnly: {
			IrieExecutable exe;
			if (targetFile.endsWith(".iexe")) {
				writeln("That's already compiled?");
				return;
			}
			bool hasFailed = false;
			exe = compile(targetFile, hasFailed);
			if (hasFailed) return;
			exe.write(outputFile);
			writeln("Done!");
			break;
		}
		case Operation.Run:
		case Operation.RunSave: {
			IrieExecutable exe;
			bool hasFailed = false;
			if (targetFile.endsWith(".irie")) {
				exe = compile(targetFile, hasFailed);
			} else {
				exe.read(targetFile, hasFailed);
			}

			if (hasFailed) {
				//writeln("Failed to load '", targetFile, "'.");
				return;
			}

			if (operation == Operation.RunSave) {
				exe.write(outputFile);
				writeln("Saved to ", outputFile, "!");
			}

			IrieVM vm = new IrieVM();
			if (measureTime) {
				clock_t begin = clock();
				vm.loadExecutable(exe, true);
				clock_t end = clock();
				double time_spent = cast(double)(end - begin) / CLOCKS_PER_SEC;
				writeln("Took: " , time_spent, " seconds to execute");
			} else {
				vm.loadExecutable(exe, true);
			}
			break;
		}
		case Operation.Dissasemble: {
			IrieExecutable exe;
			if (!targetFile.endsWith(".iexe")) {
				writeln("That's not an irie executable, can't dissassemble that.");
				return;
			}
			bool hasFailed = false;
			exe.read(targetFile, hasFailed);
			if (hasFailed) {
				writeln("Failed to load: " , targetFile);
				return;
			}
			dissasembleIExe(exe);
			break;
		}
		default:
			throw new Exception("CHAOS CHAOS! UNIMPLEMENTED!");
	}
}

string[] builtModules = [];
IrieExecutable[] iLibraries;

IrieExecutable compile(string file, out bool hasFailed) {
	bool b;
	IrieExecutable mainExe = compileRecursive(file, b);
	if (b) {
		hasFailed = true;
		return IrieExecutable();
	}

	if (!CompilationRegistry.performLink()) {
		hasFailed = true;
		return IrieExecutable();	
	}
	
	IrieExecutable finalle;
	finalle.entryPoint = mainExe.entryPoint;

	writeln("Assembling final executable..");
	foreach (IrieExecutable exe ; iLibraries) {
		if (exe.entryPoint != -1) {
			Chunk ee =  exe.chunks[exe.entryPoint];
			writeln("WARN: duplicate entry point found in ", ee.filename,".");
			return IrieExecutable();
		}
		finalle.chunks ~= exe.chunks;
		finalle.entryPoint += exe.chunks.length;
	}
	finalle.chunks ~= mainExe.chunks;
	
    if (finalle.entryPoint == -1) {
        writeln("Error! Irie Executable missing entry point!");
        hasFailed = true;
    }
	return finalle;
}

IrieExecutable compileRecursive(string file, out bool hasFailed) {
	Parser p = new Parser(file, readText(file));
	ParserResult result = p.parse();
	hasFailed = false;

	if (p.hadError) {
		hasFailed = true;
		writeln("Parser errors detected.");
		return IrieExecutable();
	}

	if (result.modules.length > 0) {
		foreach (dstring mod ; result.modules) {
			string moduleName = mod.toUTF8();
			string pth = libraryPath ~ moduleName;
			if (!exists(pth) || !isFile(pth)) {
				pth = "./" ~ moduleName;
				if (!exists(pth) || !isFile(pth)) {
					writeln("Could not locate module ", mod, ".");
					hasFailed = true;
					return IrieExecutable();
				}
			}	

			if (!builtModules.canFind(pth)) {
				bool f;
				IrieExecutable ex = compileRecursive(pth, f);
				if (f) {
					hasFailed = true;
					return IrieExecutable();
				}
				builtModules ~= pth;
				iLibraries ~= ex;
			}
		}
	}

	bool failed;
	IrieExecutable exe = result.compile(failed);
	if (failed) {
		hasFailed = true;
		writeln("Could not build irie executable.");
		return IrieExecutable();
	}	
	return exe;
}