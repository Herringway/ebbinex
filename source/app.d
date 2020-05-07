import std.file;
import std.path;
import std.stdio;
import std.string;
import std.range;

import usa;
import jpn;
import common;
version = compressedOutput;
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
    const detected = rom.detect();
    final switch (detected.build) {
        case Build.jpn:
            write("Detected Mother 2 (JP)");
            break;
        case Build.usa:
            write("Detected Earthbound (USA)");
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

enum Build {
    unknown,
    jpn,
    usa
}

auto getDumpEntries(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: return jpnData.entries;
        case Build.usa: return usaData.entries;
        case Build.unknown: assert(0);
    }
}
auto getTextTable(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: return jpnData.table;
        case Build.usa: return usaData.table;
        case Build.unknown: assert(0);
    }
}
auto getStaffTextTable(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: return jpnData.staffTable;
        case Build.usa: return usaData.staffTable;
        case Build.unknown: assert(0);
    }
}
auto getRenameLabels(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: return jpnData.renameLabels;
        case Build.usa: return usaData.renameLabels;
        case Build.unknown: assert(0);
    }
}
auto getForcedTextLabels(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: return jpnData.forceTextLabels;
        case Build.usa: return usaData.forceTextLabels;
        case Build.unknown: assert(0);
    }
}
auto getCompressedStrings(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: assert(0);
        case Build.usa: return usaData.compressed;
        case Build.unknown: assert(0);
    }
}
auto supportsCompressedText(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: return false;
        case Build.usa: return true;
        case Build.unknown: assert(0);
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

    switch (info.extension) {
        case "ebtxt":
            writeFile!parseTextData(path, info.extension, data, offset, build);
            break;
        case "npcconfig":
            writeFile!parseNPCConfig(path, info.extension, data, offset, build);
            break;
        case "flyover":
            writeFile!parseFlyover(path, info.extension, data, offset, build);
            break;
        case "enemyconfig":
            writeFile!parseEnemyConfig(path, info.extension, data, offset, build);
            break;
        case "itemconfig":
            writeFile!parseItemConfig(path, info.extension, data, offset, build);
            break;
        case "distortion":
            writeFile!parseDistortion(path, info.extension, data, offset, build);
            break;
        case "movement":
            writeFile!parseMovement(path, info.extension, data, offset, build);
            break;
        case "stafftext":
            writeFile!parseStaffText(path, info.extension, data, offset, build);
            break;
        default:
            writeFile!writeRaw(path, info.extension, data, offset, build);
            break;
    }
}

immutable string[] musicTracks = import("music.txt").split("\n");
immutable string[] movements = import("movements.txt").split("\n");
immutable string[] sprites = import("sprites.txt").split("\n");
immutable string[] items = import("items.txt").split("\n");
immutable string[] partyMembers = import("party.txt").split("\n");
immutable string[] eventFlags = import("eventflags.txt").split("\n");
immutable string[] windows = import("windows.txt").split("\n");
immutable string[] statusGroups = import("statusgroups.txt").split("\n");
immutable string[] sfx = import("sfx.txt").split("\n");
immutable string[] directions = [
    "UP",
    "UP_RIGHT",
    "RIGHT",
    "DOWN_RIGHT",
    "DOWN",
    "DOWN_LEFT",
    "LEFT",
    "UP_LEFT"
];
immutable string[] genders = [
    "NULL",
    "MALE",
    "FEMALE",
    "NEUTRAL"
];
immutable string[] enemyTypes = [
    "NORMAL",
    "INSECT",
    "METAL"
];

immutable string[] itemFlags = [
    "NESS_CAN_USE",
    "PAULA_CAN_USE",
    "JEFF_CAN_USE",
    "POO_CAN_USE",
    "TRANSFORM",
    "CANNOT_GIVE",
    "UNKNOWN",
    "CONSUMED_ON_USE"
];

void writeFile(alias func)(string baseName, string extension, ubyte[] source, ulong offset, Build build) {
    writefln!"Dumping %s.%s"(baseName, extension);
    func(baseName, extension, source, offset, build);
}
void writeRaw(string baseName, string extension, ubyte[] source, ulong offset, Build build) {
	auto outFile = File(setExtension(baseName, extension), "w");
	outFile.rawWrite(source);
}

void parseNPCConfig(string baseName, string, ubyte[] source, ulong offset, Build build) {
    import std.range:  chunks;
    auto outFile = File(setExtension(baseName, "npcconfig"), "w");
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
void parseDistortion(string baseName, string ext, ubyte[] source, ulong offset, Build build) {
    auto outFile = File(setExtension(baseName, ext), "w");
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
}
void parseEnemyConfig(string baseName, string, ubyte[] source, ulong offset, Build build) {
    import std.range:  chunks;
    auto outFile = File(setExtension(baseName, "enemyconfig"), "w");
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
}
void parseItemConfig(string baseName, string, ubyte[] source, ulong offset, Build build) {
    import std.algorithm : map;
    import std.bitmanip : bitsSet;
    import std.range:  chunks;
    auto outFile = File(setExtension(baseName, "itemconfig"), "w");
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
}

void parseMovement(string baseName, string, ubyte[] source, ulong offset, Build build) {
    import std.array : empty, front, popFront;
    auto outFile = File(setExtension(baseName, "movement"), "w");
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
}

void parseTextData(string baseName, string, ubyte[] source, ulong offset, Build build) {
    import std.algorithm.searching : canFind;
    import std.array : empty, front, popFront;
    auto outFile = File(setExtension(baseName, "ebtxt"), "w");
    auto symbolFile = File(setExtension(baseName, "symbols.asm"), "w");
    outFile.writefln!".INCLUDE \"%s\"\n"(setExtension(baseName.baseName, "symbols.asm"));
    string tmpbuff;
    immutable string[ubyte] table = getTextTable(build);
    immutable string[size_t] renameLabels = getRenameLabels(build);
    immutable uint[] forcedLabels = getForcedTextLabels(build);
    bool labelPrinted;
    string label(const ulong addr) {
        return addr in renameLabels ? renameLabels[addr] : format!"TEXT_BLOCK_%06X"(addr);
    }
    auto nextByte() {
        labelPrinted = false;
        auto first = source.front;
        source.popFront();
        offset++;
        return first;
    }
    void flushBuff() {
        if (tmpbuff == []) {
            return;
        }
        outFile.writefln!"\tEBTEXT \"%s\""(tmpbuff);
        tmpbuff = [];
    }
    void printLabel() {
        if (labelPrinted || source.empty) {
            return;
        }
        const labelstr = label(offset);
        flushBuff();
        symbolFile.writefln!".GLOBAL %s: far"(labelstr);
        outFile.writeln();
        outFile.writefln!"%s: ;$%06X"(labelstr, offset);
        labelPrinted = true;
    }
    printLabel();
    while (!source.empty) {
        if (forcedLabels.canFind(offset)) {
            printLabel();
        }
        auto first = nextByte();
        if (first in table) {
            tmpbuff ~= table[first];
            continue;
        }
        switch (first) {
            case 0x00:
                flushBuff();
                outFile.writeln("\tEBTEXT_LINE_BREAK");
                break;
            case 0x01:
                flushBuff();
                outFile.writeln("\tEBTEXT_START_NEW_LINE");
                break;
            case 0x02:
                flushBuff();
                outFile.writeln("\tEBTEXT_END_BLOCK");
                printLabel();
                break;
            case 0x03:
                flushBuff();
                outFile.writeln("\tEBTEXT_HALT_WITH_PROMPT");
                break;
            case 0x04:
                flushBuff();
                auto flag = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBTEXT_SET_EVENT_FLAG EVENT_FLAG::%s"(eventFlags[flag]);
                break;
            case 0x05:
                flushBuff();
                auto flag = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBTEXT_CLEAR_EVENT_FLAG EVENT_FLAG::%s"(eventFlags[flag]);
                break;
            case 0x06:
                flushBuff();
                auto flag = nextByte() + (nextByte()<<8);
                auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                outFile.writefln!"\tEBTEXT_JUMP_IF_FLAG_SET %s, EVENT_FLAG::%s"(label(dest), eventFlags[flag]);
                break;
            case 0x07:
                flushBuff();
                auto flag = nextByte() + (nextByte()<<8);
                outFile.writefln!"\tEBTEXT_CHECK_EVENT_FLAG EVENT_FLAG::%s"(eventFlags[flag]);
                break;
            case 0x08:
                flushBuff();
                auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                outFile.writefln!"\tEBTEXT_CALL_TEXT %s"(label(dest));
                break;
            case 0x09:
                flushBuff();
                auto argCount = nextByte();
                string[] dests;
                while(argCount--) {
                    dests ~= label(nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24));
                }
                outFile.writefln!"\tEBTEXT_JUMP_MULTI %-(%s%|, %)"(dests);
                break;
            case 0x0A:
                flushBuff();
                auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                outFile.writefln!"\tEBTEXT_JUMP %s\n"(label(dest));
                break;
            case 0x0B:
                flushBuff();
                auto arg = nextByte();
                outFile.writefln!"\tEBTEXT_TEST_IF_WORKMEM_TRUE $%02X"(arg);
                break;
            case 0x0C:
                flushBuff();
                auto arg = nextByte();
                outFile.writefln!"\tEBTEXT_TEST_IF_WORKMEM_FALSE $%02X"(arg);
                break;
            case 0x0D:
                flushBuff();
                auto dest = nextByte();
                outFile.writefln!"\tEBTEXT_COPY_TO_ARGMEM $%02X"(dest);
                break;
            case 0x0E:
                flushBuff();
                auto dest = nextByte();
                outFile.writefln!"\tEBTEXT_STORE_TO_ARGMEM $%02X"(dest);
                break;
            case 0x0F:
                flushBuff();
                outFile.writeln("\tEBTEXT_INCREMENT_WORKMEM");
                break;
            case 0x10:
                flushBuff();
                auto time = nextByte();
                outFile.writefln!"\tEBTEXT_PAUSE %d"(time);
                break;
            case 0x11:
                flushBuff();
                outFile.writeln("\tEBTEXT_CREATE_SELECTION_MENU");
                break;
            case 0x12:
                flushBuff();
                outFile.writeln("\tEBTEXT_CLEAR_TEXT_LINE");
                break;
            case 0x13:
                flushBuff();
                outFile.writeln("\tEBTEXT_HALT_WITHOUT_PROMPT");
                break;
            case 0x14:
                flushBuff();
                outFile.writeln("\tEBTEXT_HALT_WITH_PROMPT_ALWAYS");
                break;
            case 0x15: .. case 0x17:
                version (compressedOutput) flushBuff();
                if (build.supportsCompressedText) {
                    auto arg = nextByte();
                    auto id = ((first - 0x15)<<8) + arg;
                    version(compressedOutput) {
                        outFile.writefln!"\tEBTEXT_COMPRESSED_BANK_%d $%02X ;\"%s\""(first-0x14, arg, getCompressedStrings(build)[id]);
                    } else {
                        tmpbuff ~= getCompressedStrings(build)[id];
                    }
                } else {
                    outFile.writefln!"UNHANDLED: %02X"(first);
                }
                break;
            case 0x18:
                flushBuff();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        outFile.writeln("\tEBTEXT_CLOSE_WINDOW");
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_OPEN_WINDOW WINDOW::%s"(windows[arg]);
                        break;
                    case 0x02:
                        outFile.writeln("\tEBTEXT_UNKNOWN_CC_18_02");
                        break;
                    case 0x03:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_SWITCH_TO_WINDOW $%02X"(arg);
                        break;
                    case 0x04:
                        outFile.writeln("\tEBTEXT_CLOSE_ALL_WINDOWS");
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_FORCE_TEXT_ALIGNMENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x06:
                        outFile.writeln("\tEBTEXT_CLEAR_WINDOW");
                        break;
                    case 0x07:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_CHECK_FOR_INEQUALITY $%06X, $%02X"(arg, arg2);
                        break;
                    case 0x08:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16);
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_18_08 $%06X"(arg);
                        break;
                    case 0x09:
                        outFile.writeln("\tEBTEXT_UNKNOWN_CC_18_09");
                        break;
                    case 0x0A:
                        outFile.writeln("\tEBTEXT_SHOW_WALLET_WINDOW");
                        break;
                    default:
                        outFile.writefln!"UNHANDLED: 18 %02X"(subCC);
                        break;
                }
                break;
            case 0x19:
                flushBuff();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x02:
                        outFile.writeln("\tEBTEXT_LOAD_STRING_TO_MEMORY");
                        break;
                    case 0x04:
                        outFile.writeln("\tEBTEXT_CLEAR_LOADED_STRINGS");
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto statusGroup = nextByte();
                        auto status = nextByte();
                        outFile.writefln!"\tEBTEXT_INFLICT_STATUS PARTY_MEMBER_TEXT::%s, $%02X, $%02X"(partyMembers[arg+1], statusGroup, status);
                        break;
                    case 0x10:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_GET_CHARACTER_NUMBER $%02X"(arg);
                        break;
                    case 0x11:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_GET_CHARACTER_NAME_LETTER $%02X"(arg);
                        break;
                    case 0x14:
                        outFile.writeln("\tEBTEXT_UNKNOWN_CC_19_14");
                        break;
                    case 0x16:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_GET_CHARACTER_STATUS $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x18:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_19_18 $%02X"(arg);
                        break;
                    case 0x19:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_ADD_ITEM_ID_TO_WORK_MEMORY $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x1A:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_19_1A $%02X"(arg);
                        break;
                    case 0x1B:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_19_1B $%02X"(arg);
                        break;
                    case 0x1C:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_19_1C $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x1D:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_19_1D $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x1E:
                        outFile.writeln("\tEBTEXT_UNKNOWN_CC_19_1E");
                        break;
                    case 0x1F:
                        outFile.writeln("\tEBTEXT_UNKNOWN_CC_19_1F");
                        break;
                    case 0x20:
                        outFile.writeln("\tEBTEXT_UNKNOWN_CC_19_20");
                        break;
                    case 0x21:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_IS_ITEM_DRINK $%02X"(arg);
                        break;
                    case 0x22:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        auto arg3 = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_GET_DIRECTION_OF_OBJECT_FROM_CHARACTER $%02X, $%02X, $%04X"(arg, arg2, arg3);
                        break;
                    case 0x23:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        auto arg3 = nextByte();
                        outFile.writefln!"\tEBTEXT_GET_DIRECTION_OF_OBJECT_FROM_NPC $%04X, $%04X, $%02X"(arg, arg2, arg3);
                        break;
                    case 0x24:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_GET_DIRECTION_OF_OBJECT_FROM_SPRITE $%04X, $%04X"(arg, arg2);
                        break;
                    case 0x25:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_IS_ITEM_CONDIMENT $%02X"(arg);
                        break;
                    case 0x26:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_19_26 $%02X"(arg);
                        break;
                    case 0x27:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_19_27 $%02X"(arg);
                        break;
                    case 0x28:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_19_28 $%02X"(arg);
                        break;
                    default:
                        outFile.writefln!"UNHANDLED: 19 %02X"(subCC);
                        break;
                }
                break;
            case 0x1A:
                flushBuff();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x01:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto dest2 = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto dest3 = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto dest4 = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto arg5 = nextByte();
                        outFile.writefln!"\tEBTEXT_PARTY_MEMBER_SELECTION_MENU_UNCANCELLABLE $%06X, $%06X, $%06X, $%06X, $%02X"(dest, dest2, dest3, dest4, arg5);
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_SHOW_CHARACTER_INVENTORY $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x06:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_DISPLAY_SHOP_MENU $%02X"(arg);
                        break;
                    case 0x07:
                        outFile.writeln("\tEBTEXT_UNKNOWN_CC_1A_07");
                        break;
                    case 0x0A:
                        outFile.writeln("\tEBTEXT_OPEN_PHONE_MENU");
                        break;
                    default:
                        outFile.writefln!"UNHANDLED: 1A %02X"(subCC);
                        break;
                }
                break;
            case 0x1B:
                flushBuff();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        outFile.writeln("\tEBTEXT_COPY_ACTIVE_MEMORY_TO_STORAGE");
                        break;
                    case 0x01:
                        outFile.writeln("\tEBTEXT_COPY_STORAGE_MEMORY_TO_ACTIVE");
                        break;
                    case 0x02:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        outFile.writefln!"\tEBTEXT_JUMP_IF_FALSE %s"(label(dest));
                        break;
                    case 0x03:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        outFile.writefln!"\tEBTEXT_JUMP_IF_TRUE %s"(label(dest));
                        break;
                    case 0x04:
                        outFile.writeln("\tEBTEXT_SWAP_WORKING_AND_ARG_MEMORY");
                        break;
                    case 0x05:
                        outFile.writeln("\tEBTEXT_COPY_ACTIVE_MEMORY_TO_WORKING_MEMORY");
                        break;
                    case 0x06:
                        outFile.writeln("\tEBTEXT_COPY_WORKING_MEMORY_TO_ACTIVE_MEMORY");
                        break;
                    default:
                        outFile.writefln!"UNHANDLED: 1B %02X"(subCC);
                        break;
                }
                break;
            case 0x1C:
                flushBuff();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_TEXT_COLOUR_EFFECTS $%02X"(arg);
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_PRINT_STAT $%02X"(arg);
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_PRINT_CHAR_NAME $%02X"(arg);
                        break;
                    case 0x03:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_PRINT_CHAR %02X"(arg);
                        break;
                    case 0x04:
                        outFile.writeln("\tEBTEXT_OPEN_HP_PP_WINDOWS");
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_PRINT_ITEM_NAME ITEM::%s"(items[arg]);
                        break;
                    case 0x06:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_PRINT_TELEPORT_DESTINATION_NAME $%02X"(arg);
                        break;
                    case 0x07:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_PRINT_HORIZONTAL_TEXT_STRING $%02X"(arg);
                        break;
                    case 0x08:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_PRINT_SPECIAL_GFX $%02X"(arg);
                        break;
                    case 0x09:
                        outFile.writeln("\tEBTEXT_UNKNOWN_CC_1C_09");
                        break;
                    case 0x0A:
                        auto arg =nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        outFile.writefln!"\tEBTEXT_PRINT_NUMBER $%08X"(arg);
                        break;
                    case 0x0B:
                        auto arg =nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        outFile.writefln!"\tEBTEXT_PRINT_MONEY_AMOUNT $%08X"(arg);
                        break;
                    case 0x0C:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_PRINT_VERTICAL_TEXT_STRING $%02X"(arg);
                        break;
                    case 0x0D:
                        outFile.writeln("\tEBTEXT_PRINT_ACTION_USER_NAME");
                        break;
                    case 0x0E:
                        outFile.writeln("\tEBTEXT_PRINT_ACTION_TARGET_NAME");
                        break;
                    case 0x0F:
                        outFile.writeln("\tEBTEXT_PRINT_ACTION_AMOUNT");
                        break;
                    case 0x11:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1C_11 $%02X"(arg);
                        break;
                    case 0x12:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_PRINT_PSI_NAME $%02X"(arg);
                        break;
                    case 0x13:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_DISPLAY_PSI_ANIMATION $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x14:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_LOAD_SPECIAL $%02X"(arg);
                        break;
                    case 0x15:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_LOAD_SPECIAL_FOR_JUMP_MULTI $%02X"(arg);
                        break;
                    default:
                        outFile.writefln!"UNHANDLED: 1C %02X"(subCC);
                        break;
                }
                break;
            case 0x1D:
                flushBuff();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_GIVE_ITEM_TO_CHARACTER $%02X, ITEM::%s"(arg, items[arg2]);
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_TAKE_ITEM_FROM_CHARACTER $%02X, ITEM::%s"(arg, items[arg2]);
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_GET_PLAYER_HAS_INVENTORY_FULL $%02X"(arg);
                        break;
                    case 0x03:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_GET_PLAYER_HAS_INVENTORY_ROOM $%02X"(arg);
                        break;
                    case 0x04:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_CHECK_IF_CHARACTER_DOESNT_HAVE_ITEM $%02X, ITEM::%s"(arg, items[arg2]);
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_CHECK_IF_CHARACTER_HAS_ITEM $%02X, ITEM::%s"(arg, items[arg2]);
                        break;
                    case 0x06:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        outFile.writefln!"\tEBTEXT_ADD_TO_ATM $%08X"(arg);
                        break;
                    case 0x07:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        outFile.writefln!"\tEBTEXT_TAKE_FROM_ATM $%08X"(arg);
                        break;
                    case 0x08:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_ADD_TO_WALLET $%04X"(arg);
                        break;
                    case 0x09:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_TAKE_FROM_WALLET $%04X"(arg);
                        break;
                    case 0x0A:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_GET_BUY_PRICE_OF_ITEM ITEM::%s"(items[arg]);
                        break;
                    case 0x0B:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_GET_SELL_PRICE_OF_ITEM ITEM::%s"(items[arg]);
                        break;
                    case 0x0C:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1D_0C $%04X"(arg);
                        break;
                    case 0x0D:
                        auto who = nextByte();
                        auto what = nextByte();
                        auto what2 = nextByte();
                        outFile.writefln!"\tEBTEXT_CHARACTER_HAS_AILMENT $%02X, $%02X, $%02X"(who, what, what2);
                        break;
                    case 0x0E:
                        auto who = nextByte();
                        auto what = nextByte();
                        outFile.writefln!"\tEBTEXT_GIVE_ITEM_TO_CHARACTER_B $%02X, ITEM::%s"(who, items[what]);
                        break;
                    case 0x0F:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1D_0F $%04X"(arg);
                        break;
                    case 0x10:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1D_10 $%04X"(arg);
                        break;
                    case 0x11:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1D_11 $%04X"(arg);
                        break;
                    case 0x12:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1D_12 $%04X"(arg);
                        break;
                    case 0x13:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1D_13 $%04X"(arg);
                        break;
                    case 0x14:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        outFile.writefln!"\tEBTEXT_HAVE_ENOUGH_MONEY $%08X"(dest);
                        break;
                    case 0x15:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_PUT_VAL_IN_ARGMEM $%02X"(arg);
                        break;
                    case 0x17:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        outFile.writefln!"\tEBTEXT_HAVE_ENOUGH_MONEY_IN_ATM $%08X"(dest);
                        break;
                    case 0x18:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1D_18 $%02X"(arg);
                        break;
                    case 0x19:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_HAVE_X_PARTY_MEMBERS $%02X"(arg);
                        break;
                    case 0x20:
                        outFile.writeln("\tEBTEXT_TEST_IS_USER_TARGETTING_SELF");
                        break;
                    case 0x21:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_GENERATE_RANDOM_NUMBER $%02X"(arg);
                        break;
                    case 0x22:
                        outFile.writeln("\tEBTEXT_TEST_IF_EXIT_MOUSE_USABLE");
                        break;
                    case 0x23:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1D_23 $%02X"(arg);
                        break;
                    case 0x24:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1D_24 $%02X"(arg);
                        break;
                    default:
                        outFile.writefln!"UNHANDLED: 1D %02X"(subCC);
                        break;
                }
                break;
            case 0x1E:
                flushBuff();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_RECOVER_HP_PERCENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_DEPLETE_HP_PERCENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_RECOVER_HP_PERCENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x03:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_DEPLETE_HP_AMOUNT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x04:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_RECOVER_PP_PERCENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_DEPLETE_PP_PERCENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x06:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_RECOVER_PP_PERCENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x07:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_DEPLETE_PP_AMOUNT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x08:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_SET_CHARACTER_LEVEL $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x09:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8) + (nextByte()<<16);
                        outFile.writefln!"\tEBTEXT_GIVE_EXPERIENCE $%02X, $%06X"(arg, arg2);
                        break;
                    case 0x0A:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_BOOST_IQ $%02X, $%04X"(arg, arg2);
                        break;
                    case 0x0B:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_BOOST_GUTS $%02X, $%04X"(arg, arg2);
                        break;
                    case 0x0C:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_BOOST_SPEED $%02X, $%04X"(arg, arg2);
                        break;
                    case 0x0D:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_BOOST_VITALITY $%02X, $%04X"(arg, arg2);
                        break;
                    case 0x0E:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_BOOST_LUCK $%02X, $%04X"(arg, arg2);
                        break;
                    default:
                        outFile.writefln!"UNHANDLED: 1E %02X"(subCC);
                        break;
                }
                break;
            case 0x1F:
                flushBuff();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_PLAY_MUSIC $%02X, MUSIC::%s"(arg, musicTracks[arg2]);
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1F_01 $%02X"(arg);
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_PLAY_SOUND SFX::%s"(sfx[arg]);
                        break;
                    case 0x03:
                        outFile.writeln("\tEBTEXT_RESTORE_DEFAULT_MUSIC");
                        break;
                    case 0x04:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_SET_TEXT_PRINTING_SOUND $%02X"(arg);
                        break;
                    case 0x05:
                        outFile.writeln("\tEBTEXT_DISABLE_SECTOR_MUSIC_CHANGE");
                        break;
                    case 0x06:
                        outFile.writeln("\tEBTEXT_ENABLE_SECTOR_MUSIC_CHANGE");
                        break;
                    case 0x07:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_APPLY_MUSIC_EFFECT $%02X"(arg);
                        break;
                    case 0x11:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_ADD_PARTY_MEMBER PARTY_MEMBER::%s"(partyMembers[arg]);
                        break;
                    case 0x12:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_REMOVE_PARTY_MEMBER PARTY_MEMBER::%s"(partyMembers[arg]);
                        break;
                    case 0x13:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_CHANGE_CHARACTER_DIRECTION $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x14:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_CHANGE_PARTY_DIRECTION $%02X"(arg);
                        break;
                    case 0x15:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        auto arg3 = nextByte();
                        outFile.writefln!"\tEBTEXT_GENERATE_ACTIVE_SPRITE OVERWORLD_SPRITE::%s, EVENT_SCRIPT::%s, $%02X"(sprites[arg], movements[arg2], arg3);
                        break;
                    case 0x16:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_CHANGE_TPT_ENTRY_DIRECTION $%04X, $%02X"(arg, arg2);
                        break;
                    case 0x17:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        auto arg3 = nextByte();
                        outFile.writefln!"\tEBTEXT_CREATE_ENTITY $%04X, EVENT_SCRIPT::%s, $%02X"(arg, movements[arg2], arg3);
                        break;
                    case 0x1A:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_CREATE_FLOATING_SPRITE_NEAR_TPT_ENTRY $%04X, $%02X"(arg, arg2);
                        break;
                    case 0x1B:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_DELETE_FLOATING_SPRITE_NEAR_TPT_ENTRY $%04X"(arg);
                        break;
                    case 0x1C:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_CREATE_FLOATING_SPRITE_NEAR_CHARACTER $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x1D:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_DELETE_FLOATING_SPRITE_NEAR_CHARACTER $%02X"(arg);
                        break;
                    case 0x1E:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_DELETE_TPT_INSTANCE $%04X, $%02X"(arg, arg2);
                        break;
                    case 0x1F:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_DELETE_GENERATED_SPRITE OVERWORLD_SPRITE::%s, $%02X"(sprites[arg], arg2);
                        break;
                    case 0x20:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_TRIGGER_PSI_TELEPORT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x21:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_TELEPORT_TO $%02X"(arg);
                        break;
                    case 0x23:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_TRIGGER_BATTLE $%04X"(arg);
                        break;
                    case 0x30:
                        outFile.writeln("\tEBTEXT_USE_NORMAL_FONT");
                        break;
                    case 0x31:
                        outFile.writeln("\tEBTEXT_USE_MR_SATURN_FONT");
                        break;
                    case 0x41:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_TRIGGER_EVENT $%02X"(arg);
                        break;
                    case 0x50:
                        outFile.writeln("\tEBTEXT_DISABLE_CONTROLLER_INPUT");
                        break;
                    case 0x51:
                        outFile.writeln("\tEBTEXT_ENABLE_CONTROLLER_INPUT");
                        break;
                    case 0x52:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_CREATE_NUMBER_SELECTOR $%02X"(arg);
                        break;
                    case 0x61:
                        outFile.writeln("\tEBTEXT_TRIGGER_MOVEMENT_CODE");
                        break;
                    case 0x62:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1F_62 $%02X"(arg);
                        break;
                    case 0x63:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        outFile.writefln!"\tEBTEXT_SCREEN_RELOAD_PTR %s"(label(arg));
                        break;
                    case 0x64:
                        outFile.writeln("\tEBTEXT_DELETE_ALL_NPCS");
                        break;
                    case 0x65:
                        outFile.writeln("\tEBTEXT_DELETE_FIRST_NPC");
                        break;
                    case 0x66:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        auto arg3 = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        outFile.writefln!"\tEBTEXT_ACTIVATE_HOTSPOT $%02X, $%02X, %s"(arg, arg2, label(arg3));
                        break;
                    case 0x67:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_DEACTIVATE_HOTSPOT $%02X"(arg);
                        break;
                    case 0x68:
                        outFile.writeln("\tEBTEXT_STORE_COORDINATES_TO_MEMORY");
                        break;
                    case 0x69:
                        outFile.writeln("\tEBTEXT_TELEPORT_TO_STORED_COORDINATES");
                        break;
                    case 0x71:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_REALIZE_PSI $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x83:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_EQUIP_ITEM_TO_CHARACTER $%02X, $%02X"(arg, arg2);
                        break;
                    case 0xA0:
                        outFile.writeln("\tEBTEXT_SET_TPT_DIRECTION_UP");
                        break;
                    case 0xA1:
                        outFile.writeln("\tEBTEXT_SET_TPT_DIRECTION_DOWN");
                        break;
                    case 0xA2:
                        outFile.writeln("\tEBTEXT_UNKNOWN_CC_1F_A2");
                        break;
                    case 0xB0:
                        outFile.writeln("\tEBTEXT_SAVE_GAME");
                        break;
                    case 0xC0:
                        flushBuff();
                        auto argCount = nextByte();
                        string[] dests;
                        while(argCount--) {
                            dests ~= label(nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24));
                        }
                        outFile.writefln!"\tEBTEXT_JUMP_MULTI2 %-(%s%|, %)"(dests);
                        break;
                    case 0xD0:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_TRY_FIX_ITEM ITEM::%s"(items[arg]);
                        break;
                    case 0xD1:
                        outFile.writeln("\tEBTEXT_GET_DIRECTION_OF_NEARBY_TRUFFLE");
                        break;
                    case 0xD2:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_SUMMON_WANDERING_PHOTOGRAPHER $%02X"(arg);
                        break;
                    case 0xD3:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_TRIGGER_TIMED_EVENT $%02X"(arg);
                        break;
                    case 0xE1:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_CHANGE_MAP_PALETTE $%04X, $%02X"(arg, arg2);
                        break;
                    case 0xE4:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_CHANGE_GENERATED_SPRITE_DIRECTION $%04X, $%02X"(arg, arg2);
                        break;
                    case 0xE5:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_SET_PLAYER_LOCK $%02X"(arg);
                        break;
                    case 0xE6:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_DELAY_TPT_APPEARANCE $%04X"(arg);
                        break;
                    case 0xE7:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1F_E7 $%04X"(arg);
                        break;
                    case 0xE8:
                        auto arg = nextByte();
                        outFile.writefln!"\tEBTEXT_RESTRICT_PLAYER_MOVEMENT_WHEN_CAMERA_REPOSITIONED $%02X"(arg);
                        break;
                    case 0xE9:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1F_E9 $%04X"(arg);
                        break;
                    case 0xEA:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1F_EA $%04X"(arg);
                        break;
                    case 0xEB:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_MAKE_INVISIBLE $%02X, $%02X"(arg, arg2);
                        break;
                    case 0xEC:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_MAKE_VISIBLE $%02X, $%02X"(arg, arg2);
                        break;
                    case 0xED:
                        outFile.writeln("\tEBTEXT_RESTORE_MOVEMENT");
                        break;
                    case 0xEE:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_WARP_PARTY_TO_TPT_ENTRY $%04X"(arg);
                        break;
                    case 0xEF:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_UNKNOWN_CC_1F_EF $%04X"(arg);
                        break;
                    case 0xF0:
                        outFile.writeln("\tEBTEXT_RIDE_BICYCLE");
                        break;
                    case 0xF1:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_SET_TPT_MOVEMENT_CODE $%04X, EVENT_SCRIPT::%s"(arg, movements[arg2]);
                        break;
                    case 0xF2:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_SET_SPRITE_MOVEMENT_CODE OVERWORLD_SPRITE::%s, EVENT_SCRIPT::%s"(sprites[arg], movements[arg2]);
                        break;
                    case 0xF3:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        outFile.writefln!"\tEBTEXT_CREATE_FLOATING_SPRITE_NEAR_ENTITY $%04X, $%02X"(arg, arg2);
                        break;
                    case 0xF4:
                        auto arg = nextByte() + (nextByte()<<8);
                        outFile.writefln!"\tEBTEXT_DELETE_FLOATING_SPRITE_NEAR_ENTITY $%04X"(arg);
                        break;
                    default:
                        outFile.writefln!"UNHANDLED: 1F %02X"(subCC);
                        break;
                }
                break;
            default:
                outFile.writefln!"UNHANDLED: %02X"(first);
                break;
        }
    }
}

void parseFlyover(string baseName, string, ubyte[] source, ulong offset, Build build) {
    import std.array : empty, front, popFront;
    auto outFile = File(setExtension(baseName, "flyover"), "w");
    auto symbolFile = File(setExtension(baseName, "symbols.asm"), "w");
    outFile.writefln!".INCLUDE \"%s\"\n"(setExtension(baseName.baseName, "symbols.asm"));
    string tmpbuff;
    immutable string[ubyte] table = getTextTable(build);
    auto nextByte() {
        auto first = source.front;
        source.popFront();
        offset++;
        return first;
    }
    void printLabel() {
        symbolFile.writefln!".GLOBAL FLYOVER_%06X: far"(offset);
        outFile.writefln!"FLYOVER_%06X: ;$%06X"(offset, offset);
    }
    void flushBuff() {
        if (tmpbuff == []) {
            return;
        }
        outFile.writefln!"\tEBTEXT \"%s\""(tmpbuff);
        tmpbuff = [];
    }
    printLabel();
    while (!source.empty) {
        auto first = nextByte();
        if (first in table) {
            tmpbuff ~= table[first];
            continue;
        }
        flushBuff();
        switch (first) {
            case 0x00:
                outFile.writeln("\tEBFLYOVER_END");
                if (!source.empty) {
                    outFile.writeln();
                    printLabel();
                }
                break;
            case 0x01:
                auto arg = nextByte();
                outFile.writefln!"\tEBFLYOVER_01 $%02X"(arg);
                break;
            case 0x02:
                auto arg = nextByte();
                outFile.writefln!"\tEBFLYOVER_02 $%02X"(arg);
                break;
            case 0x08:
                auto arg = nextByte();
                outFile.writefln!"\tEBFLYOVER_08 $%02X"(arg);
                break;
            case 0x09:
                outFile.writeln("\tEBFLYOVER_09");
                break;
            default:
                outFile.writefln!"UNHANDLED: %02X"(first);
                break;
        }
    }
}
void parseStaffText(string baseName, string, ubyte[] source, ulong offset, Build build) {
    import std.array : empty, front, popFront;
    auto outFile = File(setExtension(baseName, "stafftext"), "w");
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
                    tmpbuff ~= table[arg];
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
                    tmpbuff ~= table[arg];
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
}
