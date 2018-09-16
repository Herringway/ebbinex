import std.file;
import std.path;
import std.stdio;

import usa;
import jpn;
import common;

bool isHeaderedEBROM(const ubyte[] data) pure @safe {
	return ((data[0x101DC]^data[0x101DE]) == 0xFF) && ((data[0x101DD]^data[0x101DF]) == 0xFF) && //Header checksum
		(data[0x101C0..0x101D5] == "EARTH BOUND          ");
}
bool isUnHeaderedEBROM(const ubyte[] data) pure @safe {
	return ((data[0xFFDC]^data[0xFFDE]) == 0xFF) && ((data[0xFFDD]^data[0xFFDF]) == 0xFF) && //Header checksum
		(data[0xFFC0..0xFFD5] == "EARTH BOUND          ");
}
bool isHeaderedMO2ROM(const ubyte[] data) pure @safe {
	return ((data[0x101DC]^data[0x101DE]) == 0xFF) && ((data[0x101DD]^data[0x101DF]) == 0xFF) && //Header checksum
		(data[0x101C0..0x101D5] == "MOTHER-2             ");
}
bool isUnHeaderedMO2ROM(const ubyte[] data) pure @safe {
	return ((data[0xFFDC]^data[0xFFDE]) == 0xFF) && ((data[0xFFDD]^data[0xFFDF]) == 0xFF) && //Header checksum
		(data[0xFFC0..0xFFD5] == "MOTHER-2             ");
}
void main(string[] args) {
	if (args.length < 2) {
		writefln!"Usage: %s <path to rom> [output dir]"(args[0]);
		return;
	}
    string outPath;
    if (args.length == 3) {
        outPath = args[2];
    } else {
        outPath = "bin";
    }
	auto rom = cast(ubyte[])read(args[1], 0x300200);
	if (rom.length < 0x300000) {
		stderr.writeln("File too small to be an Earthbound ROM.");
		return;
	}
    bool usa;
	if (rom.isHeaderedEBROM) {
		writeln("Detected Earthbound (USA) (With 512 byte copier header)");
		rom = rom[0x200..$];
        usa = true;
	} else if (rom.isUnHeaderedEBROM) {
		writeln("Detected Earthbound (USA)");
        usa = true;
    } else if (rom.isHeaderedMO2ROM) {
        writeln("Detected Mother 2 (JP) (With 512 byte copier header)");
		rom = rom[0x200..$];
	} else if (rom.isUnHeaderedMO2ROM) {
		stderr.writeln("Detected Mother 2 (JP)");
	} else {
		stderr.writeln("Unsupported file. (Header checksum mismatch)");
		return;
	}
	foreach (entry; usa ? usaEntries : jpnEntries) {
        writefln!"Dumping %s/%s"(entry.subdir, entry.name);
		dumpData(rom, entry, outPath, usa);
	}
}

void dumpData(ubyte[] source, const DumpInfo info, string outPath, bool usa) {
	import std.conv : text;
	assert(source.length == 0x300000, "ROM size too small: Got "~source.length.text);
	assert(info.offset <= 0x300000, "Starting offset too high while attempting to write "~info.subdir~"/"~info.name);
	assert(info.offset+info.size <= 0x300000, "Size too high while attempting to write "~info.subdir~"/"~info.name);
	auto outDir = buildPath(outPath, info.subdir);
	if (!outDir.exists) {
		mkdirRecurse(outDir);
	}
	auto outFile = File(buildPath(outDir, setExtension(info.name, "bin")), "w");
	outFile.rawWrite(source[info.offset..info.offset+info.size]);
}