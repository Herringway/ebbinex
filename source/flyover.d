module flyover;
import std.file;
import std.path;
import std.stdio;
import std.string;
import std.range;

import common;

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
        const label = offset in getFlyoverLabels(build);
        auto symbol = label ? *label : format!"FLYOVER_%06X"(offset);
        symbolFile.writefln!".GLOBAL %s: far"(symbol);
        outFile.writefln!"%s: ;$%06X"(symbol, offset);
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
