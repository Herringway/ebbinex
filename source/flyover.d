module flyover;
import std.file;
import std.path;
import std.stdio;
import std.string;
import std.range;

import common;

string[] parseFlyover(string dir, string baseName, string extension, ubyte[] source, ulong offset, const DumpDoc doc, const CommonData commonData) {
    import std.array : empty, front, popFront;
    auto filename = setExtension(baseName, extension);
    auto symbolFilename = setExtension(baseName, "symbols.asm");
    auto outFile = File(buildPath(dir, filename), "w");
    auto symbolFile = File(buildPath(dir, symbolFilename), "w");
    outFile.writefln!".INCLUDE \"%s\"\n"(setExtension(baseName.baseName, "symbols.asm"));
    string tmpbuff;
    auto nextByte() {
        auto first = source.front;
        source.popFront();
        offset++;
        return first;
    }
    void printLabel() {
        const label = offset in doc.flyoverLabels;
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
        if (first in doc.textTable) {
            tmpbuff ~= doc.textTable[first];
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
    return [filename, symbolFilename];
}
