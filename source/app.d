import std.file;
import std.path;
import std.stdio;
import std.string;
import std.range;

import common;
import dumpinfo;
import flyover;
import textdump;
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
    const detected = rom.detect();
    final switch (detected.build) {
        case Build.jpn:
            write("Detected Mother 2 (JP)");
            break;
        case Build.usa:
            write("Detected Earthbound (USA)");
            break;
        case Build.usa19950327:
            write("Detected Earthbound (1995-03-27 prototype)");
            break;
        case Build.unknown:
            stderr.writeln("Unrecognized ROM.");
            return;
    }
    if (detected.header) {
        rom = rom[0x200 .. $];
        write(" (with 512 byte header)");
    }
    writeln();
	foreach (entry; getDumpEntries(detected.build)) {
        dumpData(rom, entry, outPath, detected.build);
    }
}


auto detect(const ubyte[] data) @safe pure {
    struct Result {
        bool header;
        Build build;
    }
    foreach (headered, base; zip(only(false, true), only(0xFFB0, 0x101B0))) {
        const checksum = (cast(const ushort[])data[base + 46 .. base + 48])[0];
        const checksumComplement = (cast(const ushort[])data[base + 44 .. base + 46])[0];
        if ((checksum ^ checksumComplement) == 0xFFFF) {
            switch (cast(const(char[]))data[base + 16 .. base + 37]) {
                case "01 95.03.27          ": return Result(headered, Build.usa19950327);
                case "EARTH BOUND          ": return Result(headered, Build.usa);
                case "MOTHER-2             ": return Result(headered, Build.jpn);
                default: break;
            }
        }
    }
    return Result(false, Build.unknown);
}

void dumpData(ubyte[] source, const DumpInfo info, string outPath, Build build) {
    import std.conv : text;
    import std.exception : enforce;
    assert(source.length == 0x300000, "ROM size too small: Got "~source.length.text);
    assert(info.offset <= 0x300000, "Starting offset too high while attempting to write "~info.subdir~"/"~info.name);
    assert(info.offset+info.size <= 0x300000, "Size too high while attempting to write "~info.subdir~"/"~info.name);
    auto outDir = buildPath(outPath, info.subdir);
    if (!outDir.exists) {
        mkdirRecurse(outDir);
    }
    auto data = source[info.offset..info.offset+info.size];
    auto offset = info.offset+0xC00000;
    auto path = buildPath(outDir, info.name);

    string temporary = buildPath(tempDir, "ebbinex");
    enforce(!temporary.exists, "Temp folder already exists?");
    mkdir(temporary);

    string[] files;
    switch (info.extension) {
        case "ebtxt":
            files = writeFile!parseTextData(temporary, info.name, info.extension, data, offset, build);
            break;
        case "npcconfig":
            files = writeFile!parseNPCConfig(temporary, info.name, info.extension, data, offset, build);
            break;
        case "flyover":
            files = writeFile!parseFlyover(temporary, info.name, info.extension, data, offset, build);
            break;
        case "enemyconfig":
            files = writeFile!parseEnemyConfig(temporary, info.name, info.extension, data, offset, build);
            break;
        case "itemconfig":
            files = writeFile!parseItemConfig(temporary, info.name, info.extension, data, offset, build);
            break;
        case "distortion":
            files = writeFile!parseDistortion(temporary, info.name, info.extension, data, offset, build);
            break;
        case "movement":
            files = writeFile!parseMovement(temporary, info.name, info.extension, data, offset, build);
            break;
        case "ebctxt":
            files = writeFile!parseCompressedText(temporary, info.name, info.extension, data, offset, build);
            break;
        case "stafftext":
            files = writeFile!parseStaffText(temporary, info.name, info.extension, data, offset, build);
            break;
        default:
            if (info.compressed) {
                files ~= writeFile!writeRaw(temporary, info.name, info.extension ~ ".lzhal", data, offset, build);
                files ~= writeFile!writeCompressed(temporary, info.name, info.extension, data, offset, build);
            } else {
                files = writeFile!writeRaw(temporary, info.name, info.extension, data, offset, build);
            }
            break;
    }
    foreach (file; files) {
        auto target = buildPath(outDir, file);
        auto tempFile = buildPath(temporary, file);
        if (target.exists && !sameFile(tempFile, target)) {
            target.remove();
        }
        if (!target.exists) {
            mkdirRecurse(outDir);
            copy(tempFile, target);
            writeln("Dumped ", target);
        } else {
            //writeln("Skipping ", target);
        }
    }
    rmdirRecurse(temporary);
}

bool sameFile(string file1, string file2) {
    return read(file1) == read(file2);
}

string[] writeFile(alias func)(string dir, string filename, string extension, ubyte[] source, ulong offset, Build build) {
    return func(dir, filename, extension, source, offset, build);
}
string[] writeRaw(string dir, string baseName, string extension, ubyte[] source, ulong offset, Build build) {
    auto filename = setExtension(baseName, extension);
	File(buildPath(dir, filename), "w").rawWrite(source);
    return [filename];
}
string[] writeCompressed(string dir, string baseName, string extension, ubyte[] source, ulong offset, Build build) {
    import compy : decomp, Format;
    auto filename = setExtension(baseName, extension);
    File(buildPath(dir, filename), "w").rawWrite(decomp(Format.HALLZ2, source));
    return [filename];
}

string[] parseNPCConfig(string dir, string baseName, string extension, ubyte[] source, ulong offset, Build build) {
    import std.range:  chunks;
    auto filename = setExtension(baseName, extension);
    auto outFile = File(buildPath(dir, filename), "w");
    void printPointer(ubyte[] data) {
        auto ptr = data[0] + (data[1]<<8) + (data[2]<<16);
        if (ptr == 0) {
            outFile.writefln!"  .DWORD NULL"();
        } else {
            outFile.writefln!"  .DWORD TEXT_BLOCK_%06X"(ptr);
        }
    }
    foreach (entry; source.chunks(17)) {
        string npcType;
        bool secondaryPointer;
        switch (entry[0]) {
            case 1:
                npcType = "PERSON";
                break;
            case 2:
                npcType = "ITEM_BOX";
                break;
            case 3:
                npcType = "OBJECT";
                secondaryPointer = true;
                break;
            default: npcType = "ERROR"; break;
        }
        outFile.writefln!"  .BYTE NPC_TYPE::%s"(npcType);
        outFile.writefln!"  .WORD $%04X"(entry[1] + (entry[2]<<8));
        outFile.writefln!"  .BYTE DIRECTION::%s"(directions[entry[3]]);
        outFile.writefln!"  .BYTE $%02X"(entry[4]);
        outFile.writefln!"  .BYTE $%02X"(entry[5]);
        outFile.writefln!"  .WORD EVENT_FLAG::%s"(eventFlags[entry[6] + (entry[7]<<8)]);
        outFile.writefln!"  .BYTE $%02X"(entry[8]);
        printPointer(entry[9..13]);
        if (secondaryPointer) {
            printPointer(entry[13..17]);
        } else {
            outFile.writefln!"  .BYTE $%02X, $%02X, $%02X, $%02X"(entry[13], entry[14], entry[15], entry[16]);
        }
        outFile.writeln();
    }
    return [filename];
}
auto decodeText(const ubyte[] data, const string[ubyte] table) {
    struct Result {
        void toString(T)(T sink) const if (isOutputRange!(T, const(char))) {
            import std.conv : text;
            foreach (chr; data) {
                if (chr in table) {
                    put(sink, table[chr]);
                } else {
                    if (chr != 0) {
                        //assert(0, "???: "~chr.text);
                    }
                }
            }
        }
    }
    return Result();
}
immutable string[] distortionStyles = [
    "NONE",
    "HORIZONTAL_SMOOTH",
    "HORIZONTAL_INTERLACED",
    "VERTICAL_SMOOTH",
    "UNKNOWN"
];
string[] parseCompressedText(string dir, string baseName, string extension, ubyte[] source, ulong offset, Build build) {
    import std.algorithm.searching : canFind;
    import std.array : empty, front, popFront;
    auto filename = setExtension(baseName, extension);
    auto outFile = File(buildPath(dir, filename), "w");
    immutable string[ubyte] table = getTextTable(build);
    size_t id;
    //outFile.writef!"COMPRESSED_TEXT_DATA:\nCOMPRESSED_TEXT_CHUNK_%d:\n\tEBTEXTZ \""(id);
    foreach (c; source) {
        if (c == 0x00) {
            //outFile.writef!"\"\nCOMPRESSED_TEXT_CHUNK_%d:\n\tEBTEXTZ \""(++id);
            outFile.writeln();
            continue;
        }
        outFile.write(table.get(c, "ERROR!!!"));
    }
    outFile.writeln();
    return [filename];
}
string[] parseDistortion(string dir, string baseName, string ext, ubyte[] source, ulong offset, Build build) {
    auto filename = setExtension(baseName, ext);
    auto outFile = File(buildPath(dir, filename), "w");
    foreach (entry; source.chunks(17)) {
        size_t index;
        ubyte nextByte() {
            scope(exit) index++;
            return entry[index];
        }
        ushort nextShort() {
            scope(exit) index += 2;
            return entry[index] + (entry[index+1]<<8);
        }
        uint nextInt() {
            scope(exit) index += 4;
            return entry[index] + (entry[index+1]<<8) + (entry[index+2]<<16) + (entry[index+3]<<24);
        }
        outFile.writefln!"  .BYTE $%02X ;Unknown"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Unknown"(nextByte());
        outFile.writefln!"  .BYTE DISTORTION_STYLE::%s"(distortionStyles[nextByte()]);
        outFile.writefln!"  .WORD $%04X ;Ripple frequency"(nextShort());
        outFile.writefln!"  .WORD $%04X ;Ripple amplitude"(nextShort());
        outFile.writefln!"  .BYTE $%02X ;Unknown"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Unknown"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Unknown"(nextByte());
        outFile.writefln!"  .WORD $%04X ;Ripple frequency acceleration"(nextShort());
        outFile.writefln!"  .WORD $%04X ;Ripple amplitude acceleration"(nextShort());
        outFile.writefln!"  .BYTE $%02X ;Speed"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Unknown"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Unknown"(nextByte());
        outFile.writeln();
    }
    return [filename];
}
string[] parseEnemyConfig(string dir, string baseName, string extension, ubyte[] source, ulong offset, Build build) {
    import std.range:  chunks;
    auto filename = setExtension(baseName, extension);
    auto outFile = File(buildPath(dir, filename), "w");
    immutable string[ubyte] table = getTextTable(build);
    void printPointer(uint ptr) {
        //auto ptr = data[0] + (data[1]<<8) + (data[2]<<16);
        if (ptr == 0) {
            outFile.writefln!"  .DWORD NULL"();
        } else {
            outFile.writefln!"  .DWORD TEXT_BLOCK_%06X"(ptr);
        }
    }
    foreach (entry; source.chunks(94)) {
        size_t index;
        ubyte nextByte() {
            scope(exit) index++;
            return entry[index];
        }
        ushort nextShort() {
            scope(exit) index += 2;
            return entry[index] + (entry[index+1]<<8);
        }
        uint nextInt() {
            scope(exit) index += 4;
            return entry[index] + (entry[index+1]<<8) + (entry[index+2]<<16) + (entry[index+3]<<24);
        }
        outFile.writefln!"  .BYTE $%02X ;The Flag"(nextByte());
        outFile.writefln!"  PADDEDEBTEXT \"%s\", 25"(decodeText(entry[1..25], table));
        index = 26;
        outFile.writefln!"  .BYTE GENDER::%s"(genders[nextByte()]);
        outFile.writefln!"  .BYTE ENEMYTYPE::%s"(enemyTypes[nextByte()]);
        outFile.writefln!"  .WORD $%04X ;Battle sprite"(nextShort());
        outFile.writefln!"  .WORD $%04X ;Out-of-battle sprite"(nextShort());
        outFile.writefln!"  .BYTE $%02X ;Run flag"(nextByte());
        outFile.writefln!"  .WORD %s ;HP"(nextShort());
        outFile.writefln!"  .WORD %s ;PP"(nextShort());
        outFile.writefln!"  .DWORD %s ;Experience"(nextInt());
        outFile.writefln!"  .WORD %s ;Money"(nextShort());
        outFile.writefln!"  .WORD $%04X ;Movement"(nextShort());
        printPointer(nextInt());
        printPointer(nextInt());
        //index = 53;
        outFile.writefln!"  .BYTE $%02X ;Palette"(nextByte());
        outFile.writefln!"  .BYTE %s ;Level"(nextByte());
        outFile.writefln!"  .BYTE MUSIC::%s"(musicTracks[nextByte()]);
        outFile.writefln!"  .WORD %s ;Offense"(nextShort());
        outFile.writefln!"  .WORD %s ;Defense"(nextShort());
        outFile.writefln!"  .BYTE %s ;Speed"(nextByte());
        outFile.writefln!"  .BYTE %s ;Guts"(nextByte());
        outFile.writefln!"  .BYTE %s ;Luck"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Weakness to fire"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Weakness to ice"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Weakness to flash"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Weakness to paralysis"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Weakness to hypnosis/brainshock"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Miss rate"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Action order"(nextByte());
        outFile.writefln!"  .WORD $%04X ;Action 1"(nextShort());
        outFile.writefln!"  .WORD $%04X ;Action 2"(nextShort());
        outFile.writefln!"  .WORD $%04X ;Action 3"(nextShort());
        outFile.writefln!"  .WORD $%04X ;Action 4"(nextShort());
        outFile.writefln!"  .WORD $%04X ;Final action"(nextShort());
        outFile.writefln!"  .BYTE $%02X ;Action 1 argument"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Action 2 argument"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Action 3 argument"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Action 4 argument"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Final action argument"(nextByte());
        outFile.writefln!"  .BYTE %s ;IQ"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Boss flag"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Item drop rate"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Item dropped"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Initial status"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Death style"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Row"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Max number of allies called"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Mirror success rate"(nextByte());
        outFile.writeln();
    }
    return [filename];
}
string[] parseItemConfig(string dir, string baseName, string extension, ubyte[] source, ulong offset, Build build) {
    import std.algorithm : map;
    import std.bitmanip : bitsSet;
    import std.range:  chunks;
    auto filename = setExtension(baseName, extension);
    auto outFile = File(buildPath(dir, filename), "w");
    immutable string[ubyte] table = getTextTable(build);
    void printPointer(uint ptr) {
        if (ptr == 0) {
            outFile.writefln!"  .DWORD NULL"();
        } else {
            outFile.writefln!"  .DWORD TEXT_BLOCK_%06X"(ptr);
        }
    }
    foreach (entry; source.chunks(39)) {
        size_t index;
        ubyte nextByte() {
            scope(exit) index++;
            return entry[index];
        }
        ushort nextShort() {
            scope(exit) index += 2;
            return entry[index] + (entry[index+1]<<8);
        }
        uint nextInt() {
            scope(exit) index += 4;
            return entry[index] + (entry[index+1]<<8) + (entry[index+2]<<16) + (entry[index+3]<<24);
        }
        outFile.writefln!"  PADDEDEBTEXT \"%s\", 25"(decodeText(entry[0..24], table));
        index = 25;
        outFile.writefln!"  .BYTE $%02X ;Type"(nextByte());
        outFile.writefln!"  .WORD %s ;Cost"(nextShort());
        auto flags = nextByte();
        if (flags == 0) {
            outFile.writeln("  .BYTE $00 ;Flags");
        } else {
            outFile.writefln!"  .BYTE %-(ITEM_FLAGS::%s | %)"(flags.bitsSet().map!(x => itemFlags[x]));
        }
        outFile.writefln!"  .WORD $%04X ;Effect"(nextShort());
        outFile.writefln!"  .BYTE $%02X ;Strength"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;EPI"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;EP"(nextByte());
        outFile.writefln!"  .BYTE $%02X ;Special"(nextByte());
        printPointer(nextInt());
        outFile.writeln();
    }
    return [filename];
}

string[] parseMovement(string dir, string baseName, string extension, ubyte[] source, ulong offset, Build build) {
    import std.array : empty, front, popFront;
    auto filename = setExtension(baseName, extension);
    auto outFile = File(buildPath(dir, filename), "w");
    auto nextByte() {
        auto first = source.front;
        source.popFront();
        offset++;
        return first;
    }
    while (!source.empty) {
        auto cc = nextByte();
        switch (cc) {
            case 0x00:
                outFile.writeln("\tEBMOVE_END");
                break;
            case 0x01:
                auto arg = nextByte();
                outFile.writefln!"\tEBMOVE_LOOP $%02X"(arg);
                break;
            case 0x02:
                outFile.writeln("\tEBMOVE_LOOP_END");
                break;
            case 0x03:
                auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16);
                outFile.writefln!"\tEBMOVE_LONGJUMP $%06X"(arg);
                break;
            case 0x04:
                auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16);
                outFile.writefln!"\tEBMOVE_LONGCALL $%06X"(arg);
                break;
            case 0x05:
                outFile.writeln("\tEBMOVE_LONG_RETURN");
                break;
            case 0x06:
                auto arg = nextByte();
                outFile.writefln!"\tEBMOVE_PAUSE %d"(arg);
                break;
            case 0x07:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SHORTJUMP_UNKNOWN $%04X"(arg);
                break;
            case 0x08:
                auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16);
                outFile.writefln!"\tEBMOVE_UNKNOWN_08 $%06X"(arg);
                break;
            case 0x09:
                outFile.writeln("\tEBMOVE_HALT");
                break;
            case 0x0A:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SHORTCALL_CONDITIONAL $%04X"(arg);
                break;
            case 0x0B:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SHORTCALL_CONDITIONAL_NOT $%04X"(arg);
                break;
            case 0x0C:
                outFile.writeln("\tEBMOVE_END_UNKNOWN");
                break;
            case 0x0D:
                auto arg1 = nextByte() + (nextByte()<<8);
                auto arg2 = nextByte();
                auto arg3 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_BINOP_WRAM $%04X, $%02X, $%04X"(arg1, arg2, arg3);
                break;
            case 0x0E:
                auto arg1 = nextByte();
                auto arg2 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_WRITE_WORD_TO_9AF9_ENTRY $%02X, $%04X"(arg1, arg2);
                break;
            case 0x0F:
                outFile.writeln("\tEBMOVE_UNKNOWN_08_3B_94_C0");
                break;
            case 0x10:
                auto numStatements = nextByte();
                ushort[] dests;
                foreach (i; 0..numStatements) {
                    dests ~= nextByte() + (nextByte()<<8);
                }
                outFile.writefln!"\tEBMOVE_SWITCH_JUMP_TEMPVAR %($%04X, %)"(dests);
                break;
            case 0x11:
                auto numStatements = nextByte();
                ushort[] dests;
                foreach (i; 0..numStatements) {
                    dests ~= nextByte() + (nextByte()<<8);
                }
                outFile.writefln!"\tEBMOVE_SWITCH_CALL_TEMPVAR %($%04X, %)"(dests);
                break;
            case 0x12:
                auto arg1 = nextByte() + (nextByte()<<8);
                auto arg2 = nextByte();
                outFile.writefln!"\tEBMOVE_WRITE_BYTE_WRAM $%04X, $%02X"(arg1, arg2);
                break;
            case 0x13:
                outFile.writeln("\tEBMOVE_END_UNKNOWN2");
                break;
            case 0x14:
                auto arg1 = nextByte();
                auto arg2 = nextByte();
                auto arg3 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_BINOP_9AF9 $%02X, $%02X, $%04X"(arg1, arg2, arg3);
                break;
            case 0x15:
                auto arg1 = nextByte() + (nextByte()<<8);
                auto arg2 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_WRITE_WORD_WRAM $%04X, $%04X"(arg1, arg2);
                break;
            case 0x16:
                auto arg1 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_16 $%04X"(arg1);
                break;
            case 0x17:
                auto arg1 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_17 $%04X"(arg1);
                break;
            case 0x18:
                auto arg1 = nextByte() + (nextByte()<<8);
                auto arg2 = nextByte();
                auto arg3 = nextByte();
                outFile.writefln!"\tEBMOVE_BINOP_WRAM $%04X, $%02X, $%02X"(arg1, arg2, arg3);
                break;
            case 0x19:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SHORTJUMP $%04X"(arg);
                break;
            case 0x1A:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SHORTCALL $%04X"(arg);
                break;
            case 0x1B:
                outFile.writeln("\tEBMOVE_SHORT_RETURN");
                break;
            case 0x1C:
                auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16);
                outFile.writefln!"\tEBMOVE_WRITE_PTR_UNKNOWN $%06X"(arg);
                break;
            case 0x1D:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_WRITE_WORD_TEMPVAR $%04X"(arg);
                break;
            case 0x1E:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_WRITE_WRAM_TEMPVAR $%04X"(arg);
                break;
            case 0x1F:
                auto arg = nextByte();
                outFile.writefln!"\tEBMOVE_WRITE_TEMPVAR_9AF9 $%02X"(arg);
                break;
            case 0x20:
                auto arg = nextByte();
                outFile.writefln!"\tEBMOVE_WRITE_9AF9_TEMPVAR $%02X"(arg);
                break;
            case 0x21:
                auto arg = nextByte();
                outFile.writefln!"\tEBMOVE_WRITE_9AF9_WAIT_TIMER $%02X"(arg);
                break;
            case 0x22:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_WRITE_11E2 $%04X"(arg);
                break;
            case 0x23:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_WRITE_11A6 $%04X"(arg);
                break;
            case 0x24:
                outFile.writeln("\tEBMOVE_LOOP_TEMPVAR");
                break;
            case 0x25:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_WRITE_121E $%04X"(arg);
                break;
            case 0x26:
                auto arg = nextByte();
                outFile.writefln!"\tEBMOVE_WRITE_9AF9_10F2 $%02X"(arg);
                break;
            case 0x27:
                auto arg1 = nextByte();
                auto arg2 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_BINOP_TEMPVAR $%02X, $%04X"(arg1, arg2);
                break;
            case 0x28:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SET_X $%04X"(arg);
                break;
            case 0x29:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SET_Y $%04X"(arg);
                break;
            case 0x2A:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SET_Z $%04X"(arg);
                break;
            case 0x2B:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SET_X_RELATIVE $%04X"(arg);
                break;
            case 0x2C:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SET_Y_RELATIVE $%04X"(arg);
                break;
            case 0x2D:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SET_Z_RELATIVE $%04X"(arg);
                break;
            case 0x2E:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SET_X_VELOCITY_RELATIVE $%04X"(arg);
                break;
            case 0x2F:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SET_Y_VELOCITY_RELATIVE $%04X"(arg);
                break;
            case 0x30:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SET_Z_VELOCITY_RELATIVE $%04X"(arg);
                break;
            case 0x31:
                auto arg1 = nextByte();
                auto arg2 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_31 $%02X, $%04X"(arg1, arg2);
                break;
            case 0x32:
                auto arg1 = nextByte();
                auto arg2 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_32 $%02X, $%04X"(arg1, arg2);
                break;
            case 0x33:
                auto arg1 = nextByte();
                auto arg2 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_33 $%02X, $%04X"(arg1, arg2);
                break;
            case 0x34:
                auto arg1 = nextByte();
                auto arg2 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_34 $%02X, $%04X"(arg1, arg2);
                break;
            case 0x35:
                auto arg1 = nextByte();
                auto arg2 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_35 $%02X, $%04X"(arg1, arg2);
                break;
            case 0x36:
                auto arg1 = nextByte();
                auto arg2 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_36 $%02X, $%04X"(arg1, arg2);
                break;
            case 0x37:
                auto arg1 = nextByte();
                auto arg2 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_37 $%02X, $%04X"(arg1, arg2);
                break;
            case 0x38:
                auto arg1 = nextByte();
                auto arg2 = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_UNKNOWN_38 $%02X, $%04X"(arg1, arg2);
                break;
            case 0x39:
                outFile.writeln("\tEBMOVE_SET_VELOCITIES_ZERO");
                break;
            case 0x3A:
                auto arg = nextByte();
                outFile.writefln!"\tEBMOVE_UNKNOWN_3A $%02X"(arg);
                break;
            case 0x3B:
                auto arg = nextByte();
                outFile.writefln!"\tEBMOVE_SET_10F2 $%02X"(arg);
                break;
            case 0x3C:
                outFile.writeln("\tEBMOVE_INC_10F2");
                break;
            case 0x3D:
                outFile.writeln("\tEBMOVE_DEC_10F2");
                break;
            case 0x3E:
                auto arg = nextByte();
                outFile.writefln!"\tEBMOVE_INC_10F2_BY $%02X"(arg);
                break;
            case 0x3F:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SET_X_VELOCITY $%04X"(arg);
                break;
            case 0x40:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SET_Y_VELOCITY $%04X"(arg);
                break;
            case 0x41:
                auto arg = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBMOVE_SET_Z_VELOCITY $%04X"(arg);
                break;
            case 0x42:
                auto routine = nextByte() + (nextByte()<<8) + (nextByte()<<16);
                ulong argCount;
                ubyte[] args;
                switch (routine) {
                    case 0xC0AA07, 0xC0AA23, 0xC0A9B3, 0xC0A9CF, 0xC0A9EB:
                        argCount = 6;
                        break;
                    case 0xC0A912:
                        argCount = 5;
                        break;
                    case 0xC05E76, 0xC0A87A, 0xC0A88D, 0xC0A8A0, 0xC0A8B3, 0xC0A964, 0xC0A98B, 0xC0AAB5, 0xC0A977, 0xC0A99F:
                        argCount = 4;
                        break;
                    case 0xC0AA3F, 0xC0AAD5:
                        argCount = 3;
                        break;
                    case 0xC09E71, 0xC09FAE, 0xC09FBB, 0xC0A643, 0xC0A685, 0xC0A6A2, 0xC0A6AD, 0xC0A841, 0xC0A84C, 0xC0A857, 0xC0A86F, 0xC0A92D, 0xC0A938, 0xC0A94E, 0xC0A959, 0xC0AA6E:
                        argCount = 2;
                        break;
                    case 0xC0A651, 0xC0A679, 0xC0A697, 0xC0A864, 0xC0A907, 0xC0A943:
                        argCount = 1;
                        break;
                    case 0xC09F82:
                        args ~= nextByte();
                        argCount = args[0]*2;
                        break;
                    case 0xC020F1, 0xC0F3B2, 0xC0F3E8, 0xC46E46, 0xC2DB3F, 0xC0ED5C, 0xC09451, 0xC0A4A8, 0xC0A4BF, 0xC0D77F, 0xC2654C, 0xC03F1E, 0xC0A82F, 0xC0D7C7, 0xC0C48F, 0xC0C7DB,
                        0xC0A65F, 0xC0A8FF, 0xC0A8F7, 0xC0A8C6, 0xC474A8, 0xC47A9E, 0xC0A6B8, 0xC0C6B6, 0xC0C83B, 0xC468A9, 0xC46C45, 0xC468B5, 0xC0C4AF, 0xC0A673, 0xC0C682, 0xC46B0A,
                        0xC0CC11, 0xC47044, 0xC4978E, 0xC46E74, 0xC20000, 0xC30100, 0xC49EC4, 0xC46B2D, 0xC0A4B2, 0xC0CCCC, 0xC0D0D9, 0xC2EACF, 0xC1FFD3, 0xC2EA15, 0xC46ADB, 0xC46B65,
                        0xC0C62B, 0xC0A8DC, 0xC46B51, 0xC4248A, 0xC423DC, 0xC4730E, 0xC0A8E7, 0xC09FA8, 0xC0A6D1, 0xC0D0E6, 0xC0C353, 0xC0A6DA, 0xC0CD50, 0xC0A6E3, 0xEF027D, 0xC03DAA,
                        0xC4ECE7, 0xC425F3, 0xC47333, 0xC47499, 0xC04EF0, 0xEF0C87, 0xEF0C97, 0xC4258C, 0xEFE556, 0xC0C4F7, 0xC47B77, 0xC46D4B, 0xC4800B, 0xC0AAAC, 0xEF0D46, 0xC4733C,
                        0xC4734C, 0xC4981F, 0xC0A838, 0xC468DC, 0xEF0D73, 0xC46A6E, 0xC47369, 0xC4E2D7, 0xC4DDD0:
                        break;
                    default:
                        writefln!"UNKNOWN ROUTINE %06X, ASSUMING 0 ARGS"(routine);
                        break;
                }
                foreach (i; 0..argCount) {
                    args ~= nextByte();
                }
                outFile.writefln!"\tEBMOVE_CALLROUTINE $%06X%(, $%02X%)"(routine, args);
                break;
            case 0x43:
                auto arg = nextByte();
                outFile.writefln!"\tEBMOVE_UNKNOWN_43 $%02X"(arg);
                break;
            case 0x44:
                outFile.writeln("\tEBMOVE_WRITE_TEMPVAR_WAITTIMER");
                break;
            default:
                outFile.writefln!"UNHANDLED: %02X"(cc);
                break;
        }
    }
    return [filename];
}


string[] parseStaffText(string dir, string baseName, string extension, ubyte[] source, ulong offset, Build build) {
    import std.array : empty, front, popFront;
    auto filename = setExtension(baseName, extension);
    auto outFile = File(buildPath(dir, filename), "w");
    immutable string[ubyte] table = getStaffTextTable(build);
    auto nextByte() {
        auto first = source.front;
        source.popFront();
        offset++;
        return first;
    }
    while (!source.empty) {
        auto first = nextByte();
        switch (first) {
            case 0x01:
                string tmpbuff;
                auto arg = nextByte();
                while (arg != 0) {
                    if (arg !in table) {
                        writeln(arg);
                    }
                    tmpbuff ~= table.get(arg, format!"[%02X]"(arg));
                    arg = nextByte();
                }
                outFile.writefln!"\tEBSTAFF_SMALLTEXT \"%s\""(tmpbuff);
                break;
            case 0x02:
                string tmpbuff;
                auto arg = nextByte();
                while (arg != 0) {
                    if (arg !in table) {
                        writeln(arg);
                    }
                    tmpbuff ~= table.get(arg, format!"[%02X]"(arg));
                    arg = nextByte();
                }
                outFile.writefln!"\tEBSTAFF_BIGTEXT \"%s\""(tmpbuff);
                break;
            case 0x03:
                auto arg = nextByte();
                outFile.writefln!"\tEBSTAFF_VERTICALSPACE $%02X"(arg);
                break;
            case 0x04:
                outFile.writefln!"\tEBSTAFF_PRINTPLAYER"();
                break;
            case 0xFF:
                outFile.writefln!"\tEBSTAFF_ENDCREDITS"();
                break;
            default:
                outFile.writefln!"UNHANDLED: %02X"(first);
                break;
        }
    }
    return [filename];
}
