module flyover;
import std.algorithm;
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
    File symbolFile;
    symbolFile = File(buildPath(dir, symbolFilename), "w");
    outFile.writefln!".INCLUDE \"%s\"\n"(setExtension(baseName.baseName, "symbols.asm"));
    string tmpbuff;
    ubyte[] raw;
    ushort[] raw2;
    auto nextByte() {
        auto first = source.front;
        source.popFront();
        offset++;
        return first;
    }
    void printLabel() {
        const label = offset in doc.flyoverLabels;
        auto symbol = label ? (*label) : format!"FLYOVER_%06X"(offset);
        symbolFile.writefln!".GLOBAL %s: far"(symbol);
        outFile.writefln!"%s: ;$%06X"(symbol, offset);
    }
    void flushBuff() {
        if (tmpbuff == []) {
            return;
        }
        if (doc.dontUseTextTable) {
            if (doc.multibyteFlyovers) {
                outFile.writefln!"\t.WORD %($%04X, %) ;\"%s\""(raw2, tmpbuff);
            } else {
                outFile.writefln!"\t.BYTE %($%02X, %) ;\"%s\""(raw, tmpbuff);
            }
        } else {
            outFile.writefln!"\tEBTEXT \"%s\""(tmpbuff);
        }
        tmpbuff = [];
        raw = [];
        raw2 = [];
    }
    printLabel();
    while (!source.empty) {
        ushort first = nextByte();
        if (doc.multibyteFlyovers && first >= 0x80) {
            first = cast(ushort)((first<<8) | nextByte());
        }
        if (first in doc.flyoverTextTable) {
            tmpbuff ~= doc.flyoverTextTable[first];
            if (doc.multibyteFlyovers) {
                raw2 ~= (first>>8) | ((first&0xFF)<<8);
            } else {
                raw ~= first&0xFF;
            }
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
                if (doc.multibyteFlyovers && first >= 0x80) {
                    outFile.writefln!"\t.WORD $%04X ;???"((first>>8) | ((first&0xFF)<<8));
                } else {
                    outFile.writefln!"\t.BYTE $%02X ;???"(first);
                }
                break;
        }
    }
    return [filename, symbolFilename];
}
