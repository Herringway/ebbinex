module textdump;

import std.format;
import std.path;
import std.stdio;

import common;

struct Enum {
    string type;
    string member;
}

enum PointerType {
    text,
    func
}

struct Pointer {
    PointerType type;
    size_t val;
}

string[] parseTextData(string dir, string baseName, string, ubyte[] source, ulong offset, const DumpDoc doc, const CommonData commonData) {
    import std.algorithm.searching : canFind;
    import std.array : empty, front, popFront;
    const jpText = doc.dontUseTextTable;
    const compressedOutput = !jpText && !doc.d;
    auto filename = setExtension(baseName, doc.d ? "d" : "ebtxt");
    auto uncompressedFilename = setExtension(baseName, "ebtxt.uncompressed");
    auto symbolFilename = setExtension(baseName, "symbols.asm");
    auto outFile = File(buildPath(dir, filename), "w");
    File outFileC;
    if (!jpText) {
        outFileC = File(buildPath(dir, uncompressedFilename), "w");
     }
    File symbolFile;
    if (!doc.d) {
        symbolFile = File(buildPath(dir, symbolFilename), "w");
    }
    void writeFormatted(string fmt, T...)(T args) {
        outFile.writefln!fmt(args);
        if (compressedOutput) {
            outFileC.writefln!fmt(args);
        }
    }
    void writeLine(T...)(T args) {
        outFile.writeln(args);
        if (compressedOutput) {
            outFileC.writeln(args);
        }
    }
    if (!doc.d) {
        writeFormatted!".INCLUDE \"%s\"\n"(setExtension(baseName.baseName, "symbols.asm"));
    }
    ubyte[] raw;
    string tmpbuff;
    string tmpCompbuff;
    bool labelPrinted;
    string label(const ulong addr) {
        return addr in doc.renameLabels ? doc.renameLabels[addr] : format!"TEXT_BLOCK_%06X"(addr);
    }
    auto nextByte() {
        labelPrinted = false;
        auto first = source.front;
        source.popFront();
        offset++;
        return first;
    }
    ushort nextShort() {
        return nextByte() + (nextByte()<<8);
    }
    void printValue(T)(File file, T arg, bool printSeparator) {
        static if (is(T == ubyte) || is(T == byte) || is(T == short) || is(T == ushort) || is(T == int) || is(T == uint)) {
            if (!doc.d) {
                import std.conv : text;
                file.writef("$%0"~text(T.sizeof * 2)~"X", arg);
            } else {
                file.writef!"%d"(arg);
            }
        } else static if (is(T == ubyte[])) {
            if (doc.d) {
                file.writef!"[ %(0x%02X, %) ]"(arg);
            } else {
                file.writef!"%($%02X, %)"(arg);
            }
        } else static if (is(T == string)) {
            file.writef!"\"%s\""(arg);
        } else static if (is(T == Pointer)) {
            if (!doc.d) {
                file.write(label(arg.val));
            } else {
                file.write("&", label(arg.val));
            }
        } else static if (is(T == Pointer[])) {
            foreach (i, v; arg) {
                printValue(file, v, printSeparator || (i != (arg.length - 1)));
            }
        } else static if (is(T == Enum)) {
            file.write(arg.type);
            if (doc.d) {
                file.write(".");
            } else {
                file.write("::");
            }
            file.write(arg.member);
        } else {
            static assert(0, "Unhandled type");
        }
        if (printSeparator) {
            file.write(", ");
        }
    }
    void writeCommandToFile(T...)(File file, string name, T args) {
        file.write("\t", name);
        if (doc.d) {
            file.write("(");
        } else if (args.length > 0) {
            file.write(" ");
        }
        foreach (idx, arg; args) {
            printValue(file, arg, idx != (args.length - 1));
        }
        if (doc.d) {
            file.write("),");
        }
        file.writeln();
    }
    void writeCommentedCommandToFile(T...)(File file, string name, T args, string comment) {
        file.write("\t", name);
        if (doc.d) {
            file.write("(");
        } else if (args.length > 0) {
            file.write(" ");
        }
        foreach (idx, arg; args) {
            printValue(file, arg, idx != (args.length - 1));
        }
        if (doc.d) {
            file.write("), //");
        } else {
            file.write(" ;");
        }
        file.writeln(comment);
    }
    void flushBuff() {
        if (tmpbuff == []) {
            return;
        }
        if (jpText) {
            writeCommentedCommandToFile(outFile, ".BYTE", raw, tmpbuff);
        } else if (doc.d) {
            writeCommandToFile(outFile, "EBString", tmpbuff);
        } else {
            writeCommandToFile(outFile, "EBTEXT", tmpbuff);
        }
        raw = [];
        tmpbuff = [];
    }
    void flushCompressedBuff() {
        if ((tmpCompbuff == []) || !compressedOutput) {
            return;
        }
        outFileC.writefln!"\tEBTEXT \"%s\""(tmpCompbuff);
        tmpCompbuff = [];
    }
    void flushBuffs() {
        flushBuff();
        if (compressedOutput) {
            flushCompressedBuff();
        }
    }
    uint localID = 0;
    void printLabel() {
        if (labelPrinted || source.empty) {
            return;
        }
        const labelstr = label(offset);
        flushBuffs();
        if (!doc.d) {
            symbolFile.writefln!".GLOBAL %s: far"(labelstr);
            writeLine();
            writeFormatted!"%s: ;$%06X"(labelstr, offset);
        } else {
            writeLine("];");
            writeLine("");
            writeFormatted!"immutable ubyte[] %s = [ //$%06X"(labelstr, offset);
        }
        labelPrinted = true;
        localID = 0;
    }
    void printLocalLabel() {
        if (labelPrinted || source.empty) {
            return;
        }
        flushBuffs();
        if (!doc.d) {
            writeFormatted!"@local%02d: ;%06X"(localID, offset);
        } else {
            //writeLine("];");
            //writeLine("");
            //writeFormatted!"immutable ubyte[] %s = [ //$%06X"(labelstr, offset);
        }
        localID++;
        labelPrinted = true;
    }
    void writeCommand(T...)(string name, T args) {
        flushBuffs();
        writeCommandToFile(outFile, name, args);
        if (compressedOutput) {
            writeCommandToFile(outFileC, name, args);
        }
    }
    printLabel();
    while (!source.empty) {
        if ((offset in doc.renameLabels) || doc.forceTextLabels.canFind(offset)) {
            printLabel();
        }
        if (doc.forceLocalLabels.canFind(offset)) {
            printLocalLabel();
        }
        auto first = nextByte();
        if (first in doc.textTable) {
            raw ~= first;
            tmpbuff ~= doc.textTable[first];
            tmpCompbuff ~= doc.textTable[first];
            continue;
        }
        switch (first) {
            case 0x00:
                writeCommand("EBTEXT_LINE_BREAK");
                break;
            case 0x01:
                writeCommand("EBTEXT_START_NEW_LINE");
                break;
            case 0x02:
                writeCommand("EBTEXT_END_BLOCK");
                printLabel();
                break;
            case 0x03:
                writeCommand("EBTEXT_HALT_WITH_PROMPT");
                break;
            case 0x04:
                auto flag = nextShort();
                writeCommand("EBTEXT_SET_EVENT_FLAG", Enum(commonData.enums["eventFlags"], commonData.eventFlags[flag]));
                break;
            case 0x05:
                auto flag = nextByte() + (nextByte()<<8);
                writeCommand("EBTEXT_CLEAR_EVENT_FLAG", Enum(commonData.enums["eventFlags"], commonData.eventFlags[flag]));
                break;
            case 0x06:
                auto flag = nextByte() + (nextByte()<<8);
                auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                writeCommand("EBTEXT_JUMP_IF_FLAG_SET", Pointer(PointerType.text, dest), Enum(commonData.enums["eventFlags"], commonData.eventFlags[flag]));
                break;
            case 0x07:
                auto flag = nextByte() + (nextByte()<<8);
                writeCommand("EBTEXT_CHECK_EVENT_FLAG", Enum(commonData.enums["eventFlags"], commonData.eventFlags[flag]));
                break;
            case 0x08:
                auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                writeCommand("EBTEXT_CALL_TEXT", Pointer(PointerType.text, dest));
                break;
            case 0x09:
                auto argCount = nextByte();
                Pointer[] dests;
                while(argCount--) {
                    dests ~= Pointer(PointerType.text, nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24));
                }
                writeCommand("EBTEXT_JUMP_MULTI", dests);
                break;
            case 0x0A:
                auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                writeCommand("EBTEXT_JUMP", Pointer(PointerType.text, dest));
                break;
            case 0x0B:
                writeCommand("EBTEXT_TEST_IF_WORKMEM_TRUE", nextByte());
                break;
            case 0x0C:
                writeCommand("EBTEXT_TEST_IF_WORKMEM_FALSE", nextByte());
                break;
            case 0x0D:
                writeCommand("EBTEXT_COPY_TO_ARGMEM", nextByte());
                break;
            case 0x0E:
                writeCommand("EBTEXT_STORE_TO_ARGMEM", nextByte());
                break;
            case 0x0F:
                writeCommand("EBTEXT_INCREMENT_WORKMEM");
                break;
            case 0x10:
                writeCommand("EBTEXT_PAUSE", nextByte());
                break;
            case 0x11:
                writeCommand("EBTEXT_CREATE_SELECTION_MENU");
                break;
            case 0x12:
                writeCommand("EBTEXT_CLEAR_TEXT_LINE");
                break;
            case 0x13:
                writeCommand("EBTEXT_HALT_WITHOUT_PROMPT");
                break;
            case 0x14:
                writeCommand("EBTEXT_HALT_WITH_PROMPT_ALWAYS");
                break;
            case 0x15: .. case 0x17:
                flushBuff();
                auto arg = nextByte();
                auto id = ((first - 0x15)<<8) + arg;
                writeCommentedCommandToFile(outFile, format!"EBTEXT_COMPRESSED_BANK_%d"(first - 0x14), arg, doc.compressedTextStrings[id]);
                tmpCompbuff ~= doc.compressedTextStrings[id];
                break;
            case 0x18:
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        writeCommand("EBTEXT_CLOSE_WINDOW");
                        break;
                    case 0x01:
                        writeCommand("EBTEXT_OPEN_WINDOW", Enum(commonData.enums["windows"], commonData.windows[nextByte()]));
                        break;
                    case 0x02:
                        writeCommand("EBTEXT_UNKNOWN_CC_18_02");
                        break;
                    case 0x03:
                        writeCommand("EBTEXT_SWITCH_TO_WINDOW", Enum(commonData.enums["windows"], commonData.windows[nextByte()]));
                        break;
                    case 0x04:
                        writeCommand("EBTEXT_CLOSE_ALL_WINDOWS");
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_FORCE_TEXT_ALIGNMENT", arg, arg2);
                        break;
                    case 0x06:
                        writeCommand("EBTEXT_CLEAR_WINDOW");
                        break;
                    case 0x07:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_CHECK_FOR_INEQUALITY", arg, arg2);
                        break;
                    case 0x08:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16);
                        writeCommand("EBTEXT_UNKNOWN_CC_18_08", arg);
                        break;
                    case 0x09:
                        writeCommand("EBTEXT_UNKNOWN_CC_18_09");
                        break;
                    case 0x0A:
                        writeCommand("EBTEXT_SHOW_WALLET_WINDOW");
                        break;
                    default:
                        assert(0, format!"UNHANDLED: 18 %02X"(subCC));
                }
                break;
            case 0x19:
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x02:
                        string payload;
                        while (auto x = nextByte()) {
                            if (x == 1) {
                                writeCommand("EBTEXT_LOAD_STRING_TO_MEMORY_WITH_SELECT_SCRIPT", payload, Pointer(PointerType.text, nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24)));
                                break;
                            } else if (x == 2) {
                                writeCommand("EBTEXT_LOAD_STRING_TO_MEMORY", payload);
                                break;
                            } else {
                                payload ~= doc.textTable[x];
                            }
                        }
                        break;
                    case 0x04:
                        writeCommand("EBTEXT_CLEAR_LOADED_STRINGS");
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto statusGroup = nextByte();
                        auto status = nextByte();
                        writeCommand("EBTEXT_INFLICT_STATUS", Enum(commonData.enums["partyMembersText"], commonData.partyMembers[arg+1]), statusGroup, status);
                        break;
                    case 0x10:
                        writeCommand("EBTEXT_GET_CHARACTER_NUMBER", nextByte());
                        break;
                    case 0x11:
                        writeCommand("EBTEXT_GET_CHARACTER_NAME_LETTER", nextByte());
                        break;
                    case 0x14:
                        writeCommand("EBTEXT_UNKNOWN_CC_19_14");
                        break;
                    case 0x16:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_GET_CHARACTER_STATUS", arg, arg2);
                        break;
                    case 0x18:
                        writeCommand("EBTEXT_UNKNOWN_CC_19_18", nextByte());
                        break;
                    case 0x19:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_ADD_ITEM_ID_TO_WORK_MEMORY", arg, arg2);
                        break;
                    case 0x1A:
                        writeCommand("EBTEXT_UNKNOWN_CC_19_1A", nextByte());
                        break;
                    case 0x1B:
                        writeCommand("EBTEXT_UNKNOWN_CC_19_1B", nextByte());
                        break;
                    case 0x1C:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_UNKNOWN_CC_19_1C", arg, arg2);
                        break;
                    case 0x1D:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_UNKNOWN_CC_19_1D", arg, arg2);
                        break;
                    case 0x1E:
                        writeCommand("EBTEXT_UNKNOWN_CC_19_1E");
                        break;
                    case 0x1F:
                        writeCommand("EBTEXT_UNKNOWN_CC_19_1F");
                        break;
                    case 0x20:
                        writeCommand("EBTEXT_UNKNOWN_CC_19_20");
                        break;
                    case 0x21:
                        writeCommand("EBTEXT_IS_ITEM_DRINK", nextByte());
                        break;
                    case 0x22:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        auto arg3 = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_GET_DIRECTION_OF_OBJECT_FROM_CHARACTER", arg, arg2, arg3);
                        break;
                    case 0x23:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        auto arg3 = nextByte();
                        writeCommand("EBTEXT_GET_DIRECTION_OF_OBJECT_FROM_NPC", arg, arg2, arg3);
                        break;
                    case 0x24:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_GET_DIRECTION_OF_OBJECT_FROM_SPRITE", arg, arg2);
                        break;
                    case 0x25:
                        writeCommand("EBTEXT_IS_ITEM_CONDIMENT", nextByte());
                        break;
                    case 0x26:
                        writeCommand("EBTEXT_UNKNOWN_CC_19_26", nextByte());
                        break;
                    case 0x27:
                        writeCommand("EBTEXT_UNKNOWN_CC_19_27", nextByte());
                        break;
                    case 0x28:
                        writeCommand("EBTEXT_UNKNOWN_CC_19_28", nextByte());
                        break;
                    default:
                        assert(0, format!"UNHANDLED: 19 %02X"(subCC));
                }
                break;
            case 0x1A:
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x01:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto dest2 = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto dest3 = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto dest4 = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto arg5 = nextByte();
                        writeCommand("EBTEXT_PARTY_MEMBER_SELECTION_MENU_UNCANCELLABLE", dest, dest2, dest3, dest4, arg5);
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_SHOW_CHARACTER_INVENTORY", arg, arg2);
                        break;
                    case 0x06:
                        writeCommand("EBTEXT_DISPLAY_SHOP_MENU", nextByte());
                        break;
                    case 0x07:
                        writeCommand("EBTEXT_UNKNOWN_CC_1A_07");
                        break;
                    case 0x0A:
                        writeCommand("EBTEXT_OPEN_PHONE_MENU");
                        break;
                    default:
                        assert(0, format!"UNHANDLED: 1A %02X"(subCC));
                }
                break;
            case 0x1B:
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        writeCommand("EBTEXT_COPY_ACTIVE_MEMORY_TO_STORAGE");
                        break;
                    case 0x01:
                        writeCommand("EBTEXT_COPY_STORAGE_MEMORY_TO_ACTIVE");
                        break;
                    case 0x02:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeCommand("EBTEXT_JUMP_IF_FALSE", Pointer(PointerType.text, dest));
                        break;
                    case 0x03:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeCommand("EBTEXT_JUMP_IF_TRUE", Pointer(PointerType.text, dest));
                        break;
                    case 0x04:
                        writeCommand("EBTEXT_SWAP_WORKING_AND_ARG_MEMORY");
                        break;
                    case 0x05:
                        writeCommand("EBTEXT_COPY_ACTIVE_MEMORY_TO_WORKING_MEMORY");
                        break;
                    case 0x06:
                        writeCommand("EBTEXT_COPY_WORKING_MEMORY_TO_ACTIVE_MEMORY");
                        break;
                    default:
                        assert(0, format!"UNHANDLED: 1B %02X"(subCC));
                }
                break;
            case 0x1C:
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_TEXT_COLOUR_EFFECTS", arg);
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_PRINT_STAT", arg);
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_PRINT_CHAR_NAME", arg);
                        break;
                    case 0x03:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_PRINT_CHAR", arg);
                        break;
                    case 0x04:
                        writeCommand("EBTEXT_OPEN_HP_PP_WINDOWS");
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_PRINT_ITEM_NAME", Enum(commonData.enums["items"], commonData.items[arg]));
                        break;
                    case 0x06:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_PRINT_TELEPORT_DESTINATION_NAME", arg);
                        break;
                    case 0x07:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_PRINT_HORIZONTAL_TEXT_STRING", arg);
                        break;
                    case 0x08:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_PRINT_SPECIAL_GFX", arg);
                        break;
                    case 0x09:
                        writeCommand("EBTEXT_UNKNOWN_CC_1C_09");
                        break;
                    case 0x0A:
                        auto arg =nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeCommand("EBTEXT_PRINT_NUMBER", arg);
                        break;
                    case 0x0B:
                        auto arg =nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeCommand("EBTEXT_PRINT_MONEY_AMOUNT", arg);
                        break;
                    case 0x0C:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_PRINT_VERTICAL_TEXT_STRING", arg);
                        break;
                    case 0x0D:
                        writeCommand("EBTEXT_PRINT_ACTION_USER_NAME");
                        break;
                    case 0x0E:
                        writeCommand("EBTEXT_PRINT_ACTION_TARGET_NAME");
                        break;
                    case 0x0F:
                        writeCommand("EBTEXT_PRINT_ACTION_AMOUNT");
                        break;
                    case 0x11:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_UNKNOWN_CC_1C_11", arg);
                        break;
                    case 0x12:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_PRINT_PSI_NAME", arg);
                        break;
                    case 0x13:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_DISPLAY_PSI_ANIMATION", arg, arg2);
                        break;
                    case 0x14:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_LOAD_SPECIAL", arg);
                        break;
                    case 0x15:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_LOAD_SPECIAL_FOR_JUMP_MULTI", arg);
                        break;
                    default:
                        assert(0, format!"UNHANDLED: 1C %02X"(subCC));
                }
                break;
            case 0x1D:
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_GIVE_ITEM_TO_CHARACTER", arg, Enum(commonData.enums["items"], commonData.items[arg2]));
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_TAKE_ITEM_FROM_CHARACTER", arg, Enum(commonData.enums["items"], commonData.items[arg2]));
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_GET_PLAYER_HAS_INVENTORY_FULL", arg);
                        break;
                    case 0x03:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_GET_PLAYER_HAS_INVENTORY_ROOM", arg);
                        break;
                    case 0x04:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_CHECK_IF_CHARACTER_DOESNT_HAVE_ITEM", arg, Enum(commonData.enums["items"], commonData.items[arg2]));
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_CHECK_IF_CHARACTER_HAS_ITEM", arg, Enum(commonData.enums["items"], commonData.items[arg2]));
                        break;
                    case 0x06:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeCommand("EBTEXT_ADD_TO_ATM", arg);
                        break;
                    case 0x07:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeCommand("EBTEXT_TAKE_FROM_ATM", arg);
                        break;
                    case 0x08:
                        auto arg = nextShort();
                        writeCommand("EBTEXT_ADD_TO_WALLET", arg);
                        break;
                    case 0x09:
                        auto arg = nextShort();
                        writeCommand("EBTEXT_TAKE_FROM_WALLET", arg);
                        break;
                    case 0x0A:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_GET_BUY_PRICE_OF_ITEM", Enum(commonData.enums["items"], commonData.items[arg]));
                        break;
                    case 0x0B:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_GET_SELL_PRICE_OF_ITEM", Enum(commonData.enums["items"], commonData.items[arg]));
                        break;
                    case 0x0C:
                        auto arg = nextShort();
                        writeCommand("EBTEXT_UNKNOWN_CC_1D_0C", arg);
                        break;
                    case 0x0D:
                        auto who = nextByte();
                        auto what = nextByte();
                        auto what2 = nextByte();
                        writeCommand("EBTEXT_CHARACTER_HAS_AILMENT", who, Enum(commonData.enums["statusGroups"], commonData.statusGroups[what - 1]), what2);
                        break;
                    case 0x0E:
                        auto who = nextByte();
                        auto what = nextByte();
                        writeCommand("EBTEXT_GIVE_ITEM_TO_CHARACTER_B", who, Enum(commonData.enums["items"], commonData.items[what]));
                        break;
                    case 0x0F:
                        auto arg = nextShort();
                        writeCommand("EBTEXT_UNKNOWN_CC_1D_0F", arg);
                        break;
                    case 0x10:
                        auto arg = nextShort();
                        writeCommand("EBTEXT_UNKNOWN_CC_1D_10", arg);
                        break;
                    case 0x11:
                        auto arg = nextShort();
                        writeCommand("EBTEXT_UNKNOWN_CC_1D_11", arg);
                        break;
                    case 0x12:
                        auto arg = nextShort();
                        writeCommand("EBTEXT_UNKNOWN_CC_1D_12", arg);
                        break;
                    case 0x13:
                        auto arg = nextShort();
                        writeCommand("EBTEXT_UNKNOWN_CC_1D_13", arg);
                        break;
                    case 0x14:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeCommand("EBTEXT_HAVE_ENOUGH_MONEY", dest);
                        break;
                    case 0x15:
                        auto arg = nextShort();
                        writeCommand("EBTEXT_PUT_VAL_IN_ARGMEM", arg);
                        break;
                    case 0x17:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeCommand("EBTEXT_HAVE_ENOUGH_MONEY_IN_ATM", dest);
                        break;
                    case 0x18:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_UNKNOWN_CC_1D_18", arg);
                        break;
                    case 0x19:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_HAVE_X_PARTY_MEMBERS", arg);
                        break;
                    case 0x20:
                        writeCommand("EBTEXT_TEST_IS_USER_TARGETTING_SELF");
                        break;
                    case 0x21:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_GENERATE_RANDOM_NUMBER", arg);
                        break;
                    case 0x22:
                        writeCommand("EBTEXT_TEST_IF_EXIT_MOUSE_USABLE");
                        break;
                    case 0x23:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_UNKNOWN_CC_1D_23", arg);
                        break;
                    case 0x24:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_UNKNOWN_CC_1D_24", arg);
                        break;
                    default:
                        assert(0, format!"UNHANDLED: 1D %02X"(subCC));
                }
                break;
            case 0x1E:
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_RECOVER_HP_PERCENT", arg, arg2);
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_DEPLETE_HP_PERCENT", arg, arg2);
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_RECOVER_HP_PERCENT", arg, arg2);
                        break;
                    case 0x03:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_DEPLETE_HP_AMOUNT", arg, arg2);
                        break;
                    case 0x04:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_RECOVER_PP_PERCENT", arg, arg2);
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_DEPLETE_PP_PERCENT", arg, arg2);
                        break;
                    case 0x06:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_RECOVER_PP_PERCENT", arg, arg2);
                        break;
                    case 0x07:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_DEPLETE_PP_AMOUNT", arg, arg2);
                        break;
                    case 0x08:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_SET_CHARACTER_LEVEL", arg, arg2);
                        break;
                    case 0x09:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8) + (nextByte()<<16);
                        writeCommand("EBTEXT_GIVE_EXPERIENCE", arg, arg2);
                        break;
                    case 0x0A:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_BOOST_IQ", arg, arg2);
                        break;
                    case 0x0B:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_BOOST_GUTS", arg, arg2);
                        break;
                    case 0x0C:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_BOOST_SPEED", arg, arg2);
                        break;
                    case 0x0D:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_BOOST_VITALITY", arg, arg2);
                        break;
                    case 0x0E:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_BOOST_LUCK", arg, arg2);
                        break;
                    default:
                        assert(0, format!"UNHANDLED: 1E %02X"(subCC));
                }
                break;
            case 0x1F:
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_PLAY_MUSIC", arg, Enum(commonData.enums["musicTracks"], commonData.musicTracks[arg2]));
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_UNKNOWN_CC_1F_01", arg);
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_PLAY_SOUND", Enum(commonData.enums["sfx"], commonData.sfx[arg]));
                        break;
                    case 0x03:
                        writeCommand("EBTEXT_RESTORE_DEFAULT_MUSIC");
                        break;
                    case 0x04:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_SET_TEXT_PRINTING_SOUND", arg);
                        break;
                    case 0x05:
                        writeCommand("EBTEXT_DISABLE_SECTOR_MUSIC_CHANGE");
                        break;
                    case 0x06:
                        writeCommand("EBTEXT_ENABLE_SECTOR_MUSIC_CHANGE");
                        break;
                    case 0x07:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_APPLY_MUSIC_EFFECT", arg);
                        break;
                    case 0x11:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_ADD_PARTY_MEMBER", Enum(commonData.enums["partyMembers"], commonData.partyMembers[arg]));
                        break;
                    case 0x12:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_REMOVE_PARTY_MEMBER", Enum(commonData.enums["partyMembers"], commonData.partyMembers[arg]));
                        break;
                    case 0x13:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_CHANGE_CHARACTER_DIRECTION", arg, arg2);
                        break;
                    case 0x14:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_CHANGE_PARTY_DIRECTION", arg);
                        break;
                    case 0x15:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        auto arg3 = nextByte();
                        writeCommand("EBTEXT_GENERATE_ACTIVE_SPRITE", Enum(commonData.enums["sprites"], commonData.sprites[arg]), Enum(commonData.enums["movements"], commonData.movements[arg2]), arg3);
                        break;
                    case 0x16:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_CHANGE_TPT_ENTRY_DIRECTION", arg, arg2);
                        break;
                    case 0x17:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        auto arg3 = nextByte();
                        writeCommand("EBTEXT_CREATE_ENTITY", arg, Enum(commonData.enums["movements"], commonData.movements[arg2]), arg3);
                        break;
                    case 0x1A:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_CREATE_FLOATING_SPRITE_NEAR_TPT_ENTRY", arg, arg2);
                        break;
                    case 0x1B:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_DELETE_FLOATING_SPRITE_NEAR_TPT_ENTRY", arg);
                        break;
                    case 0x1C:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_CREATE_FLOATING_SPRITE_NEAR_CHARACTER", arg, arg2);
                        break;
                    case 0x1D:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_DELETE_FLOATING_SPRITE_NEAR_CHARACTER", arg);
                        break;
                    case 0x1E:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_DELETE_TPT_INSTANCE", arg, arg2);
                        break;
                    case 0x1F:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_DELETE_GENERATED_SPRITE", Enum(commonData.enums["sprites"], commonData.sprites[arg]), arg2);
                        break;
                    case 0x20:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_TRIGGER_PSI_TELEPORT", arg, arg2);
                        break;
                    case 0x21:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_TELEPORT_TO", arg);
                        break;
                    case 0x23:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_TRIGGER_BATTLE", Enum(commonData.enums["enemyGroups"], commonData.enemyGroups[arg]));
                        break;
                    case 0x30:
                        writeCommand("EBTEXT_USE_NORMAL_FONT");
                        break;
                    case 0x31:
                        writeCommand("EBTEXT_USE_MR_SATURN_FONT");
                        break;
                    case 0x41:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_TRIGGER_EVENT", arg);
                        break;
                    case 0x50:
                        writeCommand("EBTEXT_DISABLE_CONTROLLER_INPUT");
                        break;
                    case 0x51:
                        writeCommand("EBTEXT_ENABLE_CONTROLLER_INPUT");
                        break;
                    case 0x52:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_CREATE_NUMBER_SELECTOR", arg);
                        break;
                    case 0x60:
                        writeCommand(".BYTE $1F, $60");
                        break;
                    case 0x61:
                        writeCommand("EBTEXT_TRIGGER_MOVEMENT_CODE");
                        break;
                    case 0x62:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_UNKNOWN_CC_1F_62", arg);
                        break;
                    case 0x63:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeCommand("EBTEXT_SCREEN_RELOAD_PTR", Pointer(PointerType.text, arg));
                        break;
                    case 0x64:
                        writeCommand("EBTEXT_DELETE_ALL_NPCS");
                        break;
                    case 0x65:
                        writeCommand("EBTEXT_DELETE_FIRST_NPC");
                        break;
                    case 0x66:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        auto arg3 = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeCommand("EBTEXT_ACTIVATE_HOTSPOT", arg, arg2, Pointer(PointerType.text, arg3));
                        break;
                    case 0x67:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_DEACTIVATE_HOTSPOT", arg);
                        break;
                    case 0x68:
                        writeCommand("EBTEXT_STORE_COORDINATES_TO_MEMORY");
                        break;
                    case 0x69:
                        writeCommand("EBTEXT_TELEPORT_TO_STORED_COORDINATES");
                        break;
                    case 0x71:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_REALIZE_PSI", arg, arg2);
                        break;
                    case 0x83:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_EQUIP_ITEM_TO_CHARACTER", arg, arg2);
                        break;
                    case 0xA0:
                        writeCommand("EBTEXT_SET_TPT_DIRECTION_UP");
                        break;
                    case 0xA1:
                        writeCommand("EBTEXT_SET_TPT_DIRECTION_DOWN");
                        break;
                    case 0xA2:
                        writeCommand("EBTEXT_UNKNOWN_CC_1F_A2");
                        break;
                    case 0xB0:
                        writeCommand("EBTEXT_SAVE_GAME");
                        break;
                    case 0xC0:
                        auto argCount = nextByte();
                        Pointer[] dests;
                        while(argCount--) {
                            dests ~= Pointer(PointerType.text, nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24));
                        }
                        writeCommand("EBTEXT_JUMP_MULTI2", dests);
                        break;
                    case 0xD0:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_TRY_FIX_ITEM", arg);
                        break;
                    case 0xD1:
                        writeCommand("EBTEXT_GET_DIRECTION_OF_NEARBY_TRUFFLE");
                        break;
                    case 0xD2:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_SUMMON_WANDERING_PHOTOGRAPHER", arg);
                        break;
                    case 0xD3:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_TRIGGER_TIMED_EVENT", arg);
                        break;
                    case 0xE1:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_CHANGE_MAP_PALETTE", arg, arg2);
                        break;
                    case 0xE4:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_CHANGE_GENERATED_SPRITE_DIRECTION", arg, arg2);
                        break;
                    case 0xE5:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_SET_PLAYER_LOCK", arg);
                        break;
                    case 0xE6:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_DELAY_TPT_APPEARANCE", arg);
                        break;
                    case 0xE7:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_UNKNOWN_CC_1F_E7", arg);
                        break;
                    case 0xE8:
                        auto arg = nextByte();
                        writeCommand("EBTEXT_RESTRICT_PLAYER_MOVEMENT_WHEN_CAMERA_REPOSITIONED", arg);
                        break;
                    case 0xE9:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_UNKNOWN_CC_1F_E9", arg);
                        break;
                    case 0xEA:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_UNKNOWN_CC_1F_EA", arg);
                        break;
                    case 0xEB:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_MAKE_INVISIBLE", arg, arg2);
                        break;
                    case 0xEC:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_MAKE_VISIBLE", arg, arg2);
                        break;
                    case 0xED:
                        writeCommand("EBTEXT_RESTORE_MOVEMENT");
                        break;
                    case 0xEE:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_WARP_PARTY_TO_TPT_ENTRY", arg);
                        break;
                    case 0xEF:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_UNKNOWN_CC_1F_EF", arg);
                        break;
                    case 0xF0:
                        writeCommand("EBTEXT_RIDE_BICYCLE");
                        break;
                    case 0xF1:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_SET_TPT_MOVEMENT_CODE", arg, Enum(commonData.enums["movements"], commonData.movements[arg2]));
                        break;
                    case 0xF2:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_SET_SPRITE_MOVEMENT_CODE", Enum(commonData.enums["sprites"], commonData.sprites[arg]), Enum(commonData.enums["movements"], commonData.movements[arg2]));
                        break;
                    case 0xF3:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeCommand("EBTEXT_CREATE_FLOATING_SPRITE_NEAR_ENTITY", arg, arg2);
                        break;
                    case 0xF4:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeCommand("EBTEXT_DELETE_FLOATING_SPRITE_NEAR_ENTITY", arg);
                        break;
                    default:
                        assert(0, format!"UNHANDLED: 1F %02X"(subCC));
                }
                break;
            default:
                assert(0, format!"\t.BYTE $%02X"(first));
        }
    }
    string[] outFiles = [filename];
    if (compressedOutput) {
        outFiles ~= uncompressedFilename;
    }
    if (!doc.d) {
        outFiles ~= symbolFilename;
    }
    return outFiles;
}
