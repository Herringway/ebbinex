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
    if (!doc.d) {
        symbolFile = File(buildPath(dir, symbolFilename), "w");
        outFile.writefln!".INCLUDE \"%s\"\n"(setExtension(baseName.baseName, "symbols.asm"));
    }
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
        if (!doc.d) {
            symbolFile.writefln!".GLOBAL %s: far"(symbol);
            outFile.writefln!"%s: ;$%06X"(symbol, offset);
        }
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
        } else if (doc.d) {
            outFile.write(tmpbuff);
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
                if (doc.d) {
                    outFile.write("\0");
                } else {
                    outFile.writeln("\tEBFLYOVER_END");
                    if (!source.empty) {
                        outFile.writeln();
                        printLabel();
                    }
                }
                break;
            case 0x01:
                auto arg = nextByte();
                if (doc.d) {
                    outFile.writef!"\x01%s"(cast(char)arg);
                } else {
                    outFile.writefln!"\tEBFLYOVER_01 $%02X"(arg);
                }
                break;
            case 0x02:
                auto arg = nextByte();
                if (doc.d) {
                    outFile.writef!"\x02%s"(cast(char)arg);
                } else {
                    outFile.writefln!"\tEBFLYOVER_02 $%02X"(arg);
                }
                break;
            case 0x08:
                auto arg = nextByte();
                if (doc.d) {
                    outFile.writef!"\x08%s"(cast(char)arg);
                } else {
                    outFile.writefln!"\tEBFLYOVER_08 $%02X"(arg);
                }
                break;
            case 0x09:
                if (doc.d) {
                    outFile.write("\x09");
                } else {
                    outFile.writeln("\tEBFLYOVER_09");
                }
                break;
            default:
                if (doc.d) {
                    outFile.write(doc.flyoverTextTable.get(first, ""));
                } else {
                    if (doc.multibyteFlyovers && first >= 0x80) {
                        outFile.writefln!"\t.WORD $%04X ;???"((first>>8) | ((first&0xFF)<<8));
                    } else {
                        outFile.writefln!"\t.BYTE $%02X ;???"(first);
                    }
                }
                break;
        }
    }
    if (doc.d) {
        return [filename];
    } else {
        return [filename, symbolFilename];
    }
}
