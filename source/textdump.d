module textdump;

import std.format;
import std.path;
import std.stdio;

import common;

version = compressedOutput;

immutable string[][] ailments = [
    [
        "UNCONSCIOUS",
        "DIAMONDIZED",
        "PARALYZED",
        "NAUSEOUS",
        "POISONED",
        "SUNSTROKE",
        "COLD"
    ],
    [
        "MUSHROOMIZED",
        "POSSESSED"
    ],
    [
        "ASLEEP",
        "CRYING",
        "IMMOBILIZED",
        "SOLIDIFIED"
    ],
    [
        "STRANGE"
    ],
    [
        "CANT_CONCENTRATE",
        "CANT_CONCENTRATE2",
        "CANT_CONCENTRATE3",
        "CANT_CONCENTRATE4",
    ],
    [
        "HOMESICK"
    ],
    [
        "PSI_SHIELD_POWER",
        "PSI_SHIELD",
        "SHIELD_POWER",
        "SHIELD"
    ]
];

immutable string[] statusGroups = [
    "PERSISTENT_EASYHEAL",
    "PERSISTENT_HARDHEAL",
    "TEMPORARY",
    "STRANGENESS",
    "CONCENTRATION",
    "HOMESICKNESS",
    "SHIELD",
];


string[] parseTextData(string dir, string baseName, string, ubyte[] source, ulong offset, Build build) {
    import std.algorithm.searching : canFind;
    import std.array : empty, front, popFront;
    const jpText = build == Build.jpn;
    auto filename = setExtension(baseName, "ebtxt");
    auto uncompressedFilename = setExtension(baseName, "ebtxt.uncompressed");
    auto symbolFilename = setExtension(baseName, "symbols.asm");
    auto outFile = File(buildPath(dir, filename), "w");
    File outFileC;
    if (!jpText) {
        outFileC = File(buildPath(dir, uncompressedFilename), "w");
     }
    auto symbolFile = File(buildPath(dir, symbolFilename), "w");
    void writeFormatted(string fmt, T...)(T args) {
        outFile.writefln!fmt(args);
        if (!jpText) {
            outFileC.writefln!fmt(args);
        }
    }
    void writeLine(T...)(T args) {
        outFile.writeln(args);
        if (!jpText) {
            outFileC.writeln(args);
        }
    }
    writeFormatted!".INCLUDE \"%s\"\n"(setExtension(baseName.baseName, "symbols.asm"));
    ubyte[] raw;
    string tmpbuff;
    string tmpCompbuff;
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
        if (jpText) {
            outFile.writefln!"\t.BYTE \"%($%02X, %) ;%s\""(raw, tmpbuff);
        } else {
            outFile.writefln!"\tEBTEXT \"%s\""(tmpbuff);
        }
        raw = [];
        tmpbuff = [];
    }
    void flushCompressedBuff() {
        if ((tmpCompbuff == []) || jpText) {
            return;
        }
        outFileC.writefln!"\tEBTEXT \"%s\""(tmpCompbuff);
        tmpCompbuff = [];
    }
    void flushBuffs() {
        flushBuff();
        if (!jpText) {
            flushCompressedBuff();
        }
    }
    void printLabel() {
        if (labelPrinted || source.empty) {
            return;
        }
        const labelstr = label(offset);
        flushBuffs();
        symbolFile.writefln!".GLOBAL %s: far"(labelstr);
        writeLine();
        writeFormatted!"%s: ;$%06X"(labelstr, offset);
        labelPrinted = true;
    }
    printLabel();
    while (!source.empty) {
        if (forcedLabels.canFind(offset)) {
            printLabel();
        }
        auto first = nextByte();
        if (first in table) {
            raw~= first;
            tmpbuff ~= table[first];
            tmpCompbuff ~= table[first];
            continue;
        }
        switch (first) {
            case 0x00:
                flushBuffs();
                writeLine("\tEBTEXT_LINE_BREAK");
                break;
            case 0x01:
                flushBuffs();
                writeLine("\tEBTEXT_START_NEW_LINE");
                break;
            case 0x02:
                flushBuffs();
                writeLine("\tEBTEXT_END_BLOCK");
                printLabel();
                break;
            case 0x03:
                flushBuffs();
                writeLine("\tEBTEXT_HALT_WITH_PROMPT");
                break;
            case 0x04:
                flushBuffs();
                auto flag = nextByte() + (nextByte()<<8);
                writeFormatted!"\tEBTEXT_SET_EVENT_FLAG EVENT_FLAG::%s"(flag >= 0x400 ? format!"OVERFLOW%03X"(flag) : eventFlags[flag]);
                break;
            case 0x05:
                flushBuffs();
                auto flag = nextByte() + (nextByte()<<8);
                writeFormatted!"\tEBTEXT_CLEAR_EVENT_FLAG EVENT_FLAG::%s"(flag >= 0x400 ? format!"OVERFLOW%03X"(flag) : eventFlags[flag]);
                break;
            case 0x06:
                flushBuffs();
                auto flag = nextByte() + (nextByte()<<8);
                auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                //assert(flag < 0x400, "Event flag number too high");
                writeFormatted!"\tEBTEXT_JUMP_IF_FLAG_SET %s, EVENT_FLAG::%s"(label(dest), flag >= 0x400 ? format!"OVERFLOW%03X"(flag) : eventFlags[flag]);
                break;
            case 0x07:
                flushBuffs();
                auto flag = nextByte() + (nextByte()<<8);
                writeFormatted!"\tEBTEXT_CHECK_EVENT_FLAG EVENT_FLAG::%s"(eventFlags[flag]);
                break;
            case 0x08:
                flushBuffs();
                auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                writeFormatted!"\tEBTEXT_CALL_TEXT %s"(label(dest));
                break;
            case 0x09:
                flushBuffs();
                auto argCount = nextByte();
                string[] dests;
                while(argCount--) {
                    dests ~= label(nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24));
                }
                writeFormatted!"\tEBTEXT_JUMP_MULTI %-(%s%|, %)"(dests);
                break;
            case 0x0A:
                flushBuffs();
                auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                writeFormatted!"\tEBTEXT_JUMP %s\n"(label(dest));
                break;
            case 0x0B:
                flushBuffs();
                auto arg = nextByte();
                writeFormatted!"\tEBTEXT_TEST_IF_WORKMEM_TRUE $%02X"(arg);
                break;
            case 0x0C:
                flushBuffs();
                auto arg = nextByte();
                writeFormatted!"\tEBTEXT_TEST_IF_WORKMEM_FALSE $%02X"(arg);
                break;
            case 0x0D:
                flushBuffs();
                auto dest = nextByte();
                writeFormatted!"\tEBTEXT_COPY_TO_ARGMEM $%02X"(dest);
                break;
            case 0x0E:
                flushBuffs();
                auto dest = nextByte();
                writeFormatted!"\tEBTEXT_STORE_TO_ARGMEM $%02X"(dest);
                break;
            case 0x0F:
                flushBuffs();
                writeLine("\tEBTEXT_INCREMENT_WORKMEM");
                break;
            case 0x10:
                flushBuffs();
                auto time = nextByte();
                writeFormatted!"\tEBTEXT_PAUSE %d"(time);
                break;
            case 0x11:
                flushBuffs();
                writeLine("\tEBTEXT_CREATE_SELECTION_MENU");
                break;
            case 0x12:
                flushBuffs();
                writeLine("\tEBTEXT_CLEAR_TEXT_LINE");
                break;
            case 0x13:
                flushBuffs();
                writeLine("\tEBTEXT_HALT_WITHOUT_PROMPT");
                break;
            case 0x14:
                flushBuffs();
                writeLine("\tEBTEXT_HALT_WITH_PROMPT_ALWAYS");
                break;
            case 0x15: .. case 0x17:
                flushBuff();
                if (build.supportsCompressedText) {
                    auto arg = nextByte();
                    auto id = ((first - 0x15)<<8) + arg;
                    outFile.writefln!"\tEBTEXT_COMPRESSED_BANK_%d $%02X ;\"%s\""(first-0x14, arg, getCompressedStrings(build)[id]);
                    tmpCompbuff ~= getCompressedStrings(build)[id];
                } else {
                    writeFormatted!"UNHANDLED: %02X"(first);
                }
                break;
            case 0x18:
                flushBuffs();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        writeLine("\tEBTEXT_CLOSE_WINDOW");
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_OPEN_WINDOW WINDOW::%s"(windows[arg]);
                        break;
                    case 0x02:
                        writeLine("\tEBTEXT_UNKNOWN_CC_18_02");
                        break;
                    case 0x03:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_SWITCH_TO_WINDOW $%02X"(arg);
                        break;
                    case 0x04:
                        writeLine("\tEBTEXT_CLOSE_ALL_WINDOWS");
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_FORCE_TEXT_ALIGNMENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x06:
                        writeLine("\tEBTEXT_CLEAR_WINDOW");
                        break;
                    case 0x07:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_CHECK_FOR_INEQUALITY $%06X, $%02X"(arg, arg2);
                        break;
                    case 0x08:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16);
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_18_08 $%06X"(arg);
                        break;
                    case 0x09:
                        writeLine("\tEBTEXT_UNKNOWN_CC_18_09");
                        break;
                    case 0x0A:
                        writeLine("\tEBTEXT_SHOW_WALLET_WINDOW");
                        break;
                    default:
                        writeFormatted!"UNHANDLED: 18 %02X"(subCC);
                        break;
                }
                break;
            case 0x19:
                flushBuffs();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x02:
                        writeLine("\tEBTEXT_LOAD_STRING_TO_MEMORY");
                        break;
                    case 0x04:
                        writeLine("\tEBTEXT_CLEAR_LOADED_STRINGS");
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto statusGroup = nextByte();
                        auto status = nextByte();
                        writeFormatted!"\tEBTEXT_INFLICT_STATUS PARTY_MEMBER_TEXT::%s, $%02X, $%02X"(partyMembers[arg+1], statusGroup, status);
                        break;
                    case 0x10:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_GET_CHARACTER_NUMBER $%02X"(arg);
                        break;
                    case 0x11:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_GET_CHARACTER_NAME_LETTER $%02X"(arg);
                        break;
                    case 0x14:
                        writeLine("\tEBTEXT_UNKNOWN_CC_19_14");
                        break;
                    case 0x16:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_GET_CHARACTER_STATUS $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x18:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_19_18 $%02X"(arg);
                        break;
                    case 0x19:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_ADD_ITEM_ID_TO_WORK_MEMORY $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x1A:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_19_1A $%02X"(arg);
                        break;
                    case 0x1B:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_19_1B $%02X"(arg);
                        break;
                    case 0x1C:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_19_1C $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x1D:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_19_1D $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x1E:
                        writeLine("\tEBTEXT_UNKNOWN_CC_19_1E");
                        break;
                    case 0x1F:
                        writeLine("\tEBTEXT_UNKNOWN_CC_19_1F");
                        break;
                    case 0x20:
                        writeLine("\tEBTEXT_UNKNOWN_CC_19_20");
                        break;
                    case 0x21:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_IS_ITEM_DRINK $%02X"(arg);
                        break;
                    case 0x22:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        auto arg3 = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_GET_DIRECTION_OF_OBJECT_FROM_CHARACTER $%02X, $%02X, $%04X"(arg, arg2, arg3);
                        break;
                    case 0x23:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        auto arg3 = nextByte();
                        writeFormatted!"\tEBTEXT_GET_DIRECTION_OF_OBJECT_FROM_NPC $%04X, $%04X, $%02X"(arg, arg2, arg3);
                        break;
                    case 0x24:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_GET_DIRECTION_OF_OBJECT_FROM_SPRITE $%04X, $%04X"(arg, arg2);
                        break;
                    case 0x25:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_IS_ITEM_CONDIMENT $%02X"(arg);
                        break;
                    case 0x26:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_19_26 $%02X"(arg);
                        break;
                    case 0x27:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_19_27 $%02X"(arg);
                        break;
                    case 0x28:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_19_28 $%02X"(arg);
                        break;
                    default:
                        writeFormatted!"UNHANDLED: 19 %02X"(subCC);
                        break;
                }
                break;
            case 0x1A:
                flushBuffs();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x01:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto dest2 = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto dest3 = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto dest4 = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        auto arg5 = nextByte();
                        writeFormatted!"\tEBTEXT_PARTY_MEMBER_SELECTION_MENU_UNCANCELLABLE $%06X, $%06X, $%06X, $%06X, $%02X"(dest, dest2, dest3, dest4, arg5);
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_SHOW_CHARACTER_INVENTORY $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x06:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_DISPLAY_SHOP_MENU $%02X"(arg);
                        break;
                    case 0x07:
                        writeLine("\tEBTEXT_UNKNOWN_CC_1A_07");
                        break;
                    case 0x0A:
                        writeLine("\tEBTEXT_OPEN_PHONE_MENU");
                        break;
                    default:
                        writeFormatted!"UNHANDLED: 1A %02X"(subCC);
                        break;
                }
                break;
            case 0x1B:
                flushBuffs();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        writeLine("\tEBTEXT_COPY_ACTIVE_MEMORY_TO_STORAGE");
                        break;
                    case 0x01:
                        writeLine("\tEBTEXT_COPY_STORAGE_MEMORY_TO_ACTIVE");
                        break;
                    case 0x02:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeFormatted!"\tEBTEXT_JUMP_IF_FALSE %s"(label(dest));
                        break;
                    case 0x03:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeFormatted!"\tEBTEXT_JUMP_IF_TRUE %s"(label(dest));
                        break;
                    case 0x04:
                        writeLine("\tEBTEXT_SWAP_WORKING_AND_ARG_MEMORY");
                        break;
                    case 0x05:
                        writeLine("\tEBTEXT_COPY_ACTIVE_MEMORY_TO_WORKING_MEMORY");
                        break;
                    case 0x06:
                        writeLine("\tEBTEXT_COPY_WORKING_MEMORY_TO_ACTIVE_MEMORY");
                        break;
                    default:
                        writeFormatted!"UNHANDLED: 1B %02X"(subCC);
                        break;
                }
                break;
            case 0x1C:
                flushBuffs();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_TEXT_COLOUR_EFFECTS $%02X"(arg);
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_PRINT_STAT $%02X"(arg);
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_PRINT_CHAR_NAME $%02X"(arg);
                        break;
                    case 0x03:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_PRINT_CHAR $%02X"(arg);
                        break;
                    case 0x04:
                        writeLine("\tEBTEXT_OPEN_HP_PP_WINDOWS");
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_PRINT_ITEM_NAME ITEM::%s"(items[arg]);
                        break;
                    case 0x06:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_PRINT_TELEPORT_DESTINATION_NAME $%02X"(arg);
                        break;
                    case 0x07:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_PRINT_HORIZONTAL_TEXT_STRING $%02X"(arg);
                        break;
                    case 0x08:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_PRINT_SPECIAL_GFX $%02X"(arg);
                        break;
                    case 0x09:
                        writeLine("\tEBTEXT_UNKNOWN_CC_1C_09");
                        break;
                    case 0x0A:
                        auto arg =nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeFormatted!"\tEBTEXT_PRINT_NUMBER $%08X"(arg);
                        break;
                    case 0x0B:
                        auto arg =nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeFormatted!"\tEBTEXT_PRINT_MONEY_AMOUNT $%08X"(arg);
                        break;
                    case 0x0C:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_PRINT_VERTICAL_TEXT_STRING $%02X"(arg);
                        break;
                    case 0x0D:
                        writeLine("\tEBTEXT_PRINT_ACTION_USER_NAME");
                        break;
                    case 0x0E:
                        writeLine("\tEBTEXT_PRINT_ACTION_TARGET_NAME");
                        break;
                    case 0x0F:
                        writeLine("\tEBTEXT_PRINT_ACTION_AMOUNT");
                        break;
                    case 0x11:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1C_11 $%02X"(arg);
                        break;
                    case 0x12:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_PRINT_PSI_NAME $%02X"(arg);
                        break;
                    case 0x13:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_DISPLAY_PSI_ANIMATION $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x14:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_LOAD_SPECIAL $%02X"(arg);
                        break;
                    case 0x15:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_LOAD_SPECIAL_FOR_JUMP_MULTI $%02X"(arg);
                        break;
                    default:
                        writeFormatted!"UNHANDLED: 1C %02X"(subCC);
                        break;
                }
                break;
            case 0x1D:
                flushBuffs();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_GIVE_ITEM_TO_CHARACTER $%02X, ITEM::%s"(arg, items[arg2]);
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_TAKE_ITEM_FROM_CHARACTER $%02X, ITEM::%s"(arg, items[arg2]);
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_GET_PLAYER_HAS_INVENTORY_FULL $%02X"(arg);
                        break;
                    case 0x03:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_GET_PLAYER_HAS_INVENTORY_ROOM $%02X"(arg);
                        break;
                    case 0x04:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_CHECK_IF_CHARACTER_DOESNT_HAVE_ITEM $%02X, ITEM::%s"(arg, items[arg2]);
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_CHECK_IF_CHARACTER_HAS_ITEM $%02X, ITEM::%s"(arg, items[arg2]);
                        break;
                    case 0x06:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeFormatted!"\tEBTEXT_ADD_TO_ATM $%08X"(arg);
                        break;
                    case 0x07:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeFormatted!"\tEBTEXT_TAKE_FROM_ATM $%08X"(arg);
                        break;
                    case 0x08:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_ADD_TO_WALLET $%04X"(arg);
                        break;
                    case 0x09:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_TAKE_FROM_WALLET $%04X"(arg);
                        break;
                    case 0x0A:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_GET_BUY_PRICE_OF_ITEM ITEM::%s"(items[arg]);
                        break;
                    case 0x0B:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_GET_SELL_PRICE_OF_ITEM ITEM::%s"(items[arg]);
                        break;
                    case 0x0C:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1D_0C $%04X"(arg);
                        break;
                    case 0x0D:
                        auto who = nextByte();
                        auto what = nextByte();
                        auto what2 = nextByte();
                        writeFormatted!"\tEBTEXT_CHARACTER_HAS_AILMENT $%02X, STATUS_GROUP::%s, $%02X"(who, statusGroups[what - 1], what2);
                        break;
                    case 0x0E:
                        auto who = nextByte();
                        auto what = nextByte();
                        writeFormatted!"\tEBTEXT_GIVE_ITEM_TO_CHARACTER_B $%02X, ITEM::%s"(who, items[what]);
                        break;
                    case 0x0F:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1D_0F $%04X"(arg);
                        break;
                    case 0x10:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1D_10 $%04X"(arg);
                        break;
                    case 0x11:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1D_11 $%04X"(arg);
                        break;
                    case 0x12:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1D_12 $%04X"(arg);
                        break;
                    case 0x13:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1D_13 $%04X"(arg);
                        break;
                    case 0x14:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeFormatted!"\tEBTEXT_HAVE_ENOUGH_MONEY $%08X"(dest);
                        break;
                    case 0x15:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_PUT_VAL_IN_ARGMEM $%02X"(arg);
                        break;
                    case 0x17:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeFormatted!"\tEBTEXT_HAVE_ENOUGH_MONEY_IN_ATM $%08X"(dest);
                        break;
                    case 0x18:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1D_18 $%02X"(arg);
                        break;
                    case 0x19:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_HAVE_X_PARTY_MEMBERS $%02X"(arg);
                        break;
                    case 0x20:
                        writeLine("\tEBTEXT_TEST_IS_USER_TARGETTING_SELF");
                        break;
                    case 0x21:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_GENERATE_RANDOM_NUMBER $%02X"(arg);
                        break;
                    case 0x22:
                        writeLine("\tEBTEXT_TEST_IF_EXIT_MOUSE_USABLE");
                        break;
                    case 0x23:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1D_23 $%02X"(arg);
                        break;
                    case 0x24:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1D_24 $%02X"(arg);
                        break;
                    default:
                        writeFormatted!"UNHANDLED: 1D %02X"(subCC);
                        break;
                }
                break;
            case 0x1E:
                flushBuffs();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_RECOVER_HP_PERCENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_DEPLETE_HP_PERCENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_RECOVER_HP_PERCENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x03:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_DEPLETE_HP_AMOUNT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x04:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_RECOVER_PP_PERCENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_DEPLETE_PP_PERCENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x06:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_RECOVER_PP_PERCENT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x07:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_DEPLETE_PP_AMOUNT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x08:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_SET_CHARACTER_LEVEL $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x09:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8) + (nextByte()<<16);
                        writeFormatted!"\tEBTEXT_GIVE_EXPERIENCE $%02X, $%06X"(arg, arg2);
                        break;
                    case 0x0A:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_BOOST_IQ $%02X, $%04X"(arg, arg2);
                        break;
                    case 0x0B:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_BOOST_GUTS $%02X, $%04X"(arg, arg2);
                        break;
                    case 0x0C:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_BOOST_SPEED $%02X, $%04X"(arg, arg2);
                        break;
                    case 0x0D:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_BOOST_VITALITY $%02X, $%04X"(arg, arg2);
                        break;
                    case 0x0E:
                        auto arg = nextByte();
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_BOOST_LUCK $%02X, $%04X"(arg, arg2);
                        break;
                    default:
                        writeFormatted!"UNHANDLED: 1E %02X"(subCC);
                        break;
                }
                break;
            case 0x1F:
                flushBuffs();
                auto subCC = nextByte();
                switch (subCC) {
                    case 0x00:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_PLAY_MUSIC $%02X, MUSIC::%s"(arg, musicTracks[arg2]);
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1F_01 $%02X"(arg);
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_PLAY_SOUND SFX::%s"(sfx[arg]);
                        break;
                    case 0x03:
                        writeLine("\tEBTEXT_RESTORE_DEFAULT_MUSIC");
                        break;
                    case 0x04:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_SET_TEXT_PRINTING_SOUND $%02X"(arg);
                        break;
                    case 0x05:
                        writeLine("\tEBTEXT_DISABLE_SECTOR_MUSIC_CHANGE");
                        break;
                    case 0x06:
                        writeLine("\tEBTEXT_ENABLE_SECTOR_MUSIC_CHANGE");
                        break;
                    case 0x07:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_APPLY_MUSIC_EFFECT $%02X"(arg);
                        break;
                    case 0x11:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_ADD_PARTY_MEMBER PARTY_MEMBER::%s"(partyMembers[arg]);
                        break;
                    case 0x12:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_REMOVE_PARTY_MEMBER PARTY_MEMBER::%s"(partyMembers[arg]);
                        break;
                    case 0x13:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_CHANGE_CHARACTER_DIRECTION $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x14:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_CHANGE_PARTY_DIRECTION $%02X"(arg);
                        break;
                    case 0x15:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        auto arg3 = nextByte();
                        writeFormatted!"\tEBTEXT_GENERATE_ACTIVE_SPRITE OVERWORLD_SPRITE::%s, EVENT_SCRIPT::%s, $%02X"(sprites[arg], movements[arg2], arg3);
                        break;
                    case 0x16:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_CHANGE_TPT_ENTRY_DIRECTION $%04X, $%02X"(arg, arg2);
                        break;
                    case 0x17:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        auto arg3 = nextByte();
                        writeFormatted!"\tEBTEXT_CREATE_ENTITY $%04X, EVENT_SCRIPT::%s, $%02X"(arg, movements[arg2], arg3);
                        break;
                    case 0x1A:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_CREATE_FLOATING_SPRITE_NEAR_TPT_ENTRY $%04X, $%02X"(arg, arg2);
                        break;
                    case 0x1B:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_DELETE_FLOATING_SPRITE_NEAR_TPT_ENTRY $%04X"(arg);
                        break;
                    case 0x1C:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_CREATE_FLOATING_SPRITE_NEAR_CHARACTER $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x1D:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_DELETE_FLOATING_SPRITE_NEAR_CHARACTER $%02X"(arg);
                        break;
                    case 0x1E:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_DELETE_TPT_INSTANCE $%04X, $%02X"(arg, arg2);
                        break;
                    case 0x1F:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_DELETE_GENERATED_SPRITE OVERWORLD_SPRITE::%s, $%02X"(sprites[arg], arg2);
                        break;
                    case 0x20:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_TRIGGER_PSI_TELEPORT $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x21:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_TELEPORT_TO $%02X"(arg);
                        break;
                    case 0x23:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_TRIGGER_BATTLE $%04X"(arg);
                        break;
                    case 0x30:
                        writeLine("\tEBTEXT_USE_NORMAL_FONT");
                        break;
                    case 0x31:
                        writeLine("\tEBTEXT_USE_MR_SATURN_FONT");
                        break;
                    case 0x41:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_TRIGGER_EVENT $%02X"(arg);
                        break;
                    case 0x50:
                        writeLine("\tEBTEXT_DISABLE_CONTROLLER_INPUT");
                        break;
                    case 0x51:
                        writeLine("\tEBTEXT_ENABLE_CONTROLLER_INPUT");
                        break;
                    case 0x52:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_CREATE_NUMBER_SELECTOR $%02X"(arg);
                        break;
                    case 0x61:
                        writeLine("\tEBTEXT_TRIGGER_MOVEMENT_CODE");
                        break;
                    case 0x62:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1F_62 $%02X"(arg);
                        break;
                    case 0x63:
                        auto arg = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeFormatted!"\tEBTEXT_SCREEN_RELOAD_PTR %s"(label(arg));
                        break;
                    case 0x64:
                        writeLine("\tEBTEXT_DELETE_ALL_NPCS");
                        break;
                    case 0x65:
                        writeLine("\tEBTEXT_DELETE_FIRST_NPC");
                        break;
                    case 0x66:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        auto arg3 = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeFormatted!"\tEBTEXT_ACTIVATE_HOTSPOT $%02X, $%02X, %s"(arg, arg2, label(arg3));
                        break;
                    case 0x67:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_DEACTIVATE_HOTSPOT $%02X"(arg);
                        break;
                    case 0x68:
                        writeLine("\tEBTEXT_STORE_COORDINATES_TO_MEMORY");
                        break;
                    case 0x69:
                        writeLine("\tEBTEXT_TELEPORT_TO_STORED_COORDINATES");
                        break;
                    case 0x71:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_REALIZE_PSI $%02X, $%02X"(arg, arg2);
                        break;
                    case 0x83:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_EQUIP_ITEM_TO_CHARACTER $%02X, $%02X"(arg, arg2);
                        break;
                    case 0xA0:
                        writeLine("\tEBTEXT_SET_TPT_DIRECTION_UP");
                        break;
                    case 0xA1:
                        writeLine("\tEBTEXT_SET_TPT_DIRECTION_DOWN");
                        break;
                    case 0xA2:
                        writeLine("\tEBTEXT_UNKNOWN_CC_1F_A2");
                        break;
                    case 0xB0:
                        writeLine("\tEBTEXT_SAVE_GAME");
                        break;
                    case 0xC0:
                        flushBuffs();
                        auto argCount = nextByte();
                        string[] dests;
                        while(argCount--) {
                            dests ~= label(nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24));
                        }
                        writeFormatted!"\tEBTEXT_JUMP_MULTI2 %-(%s%|, %)"(dests);
                        break;
                    case 0xD0:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_TRY_FIX_ITEM %s"(arg);
                        break;
                    case 0xD1:
                        writeLine("\tEBTEXT_GET_DIRECTION_OF_NEARBY_TRUFFLE");
                        break;
                    case 0xD2:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_SUMMON_WANDERING_PHOTOGRAPHER $%02X"(arg);
                        break;
                    case 0xD3:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_TRIGGER_TIMED_EVENT $%02X"(arg);
                        break;
                    case 0xE1:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_CHANGE_MAP_PALETTE $%04X, $%02X"(arg, arg2);
                        break;
                    case 0xE4:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_CHANGE_GENERATED_SPRITE_DIRECTION $%04X, $%02X"(arg, arg2);
                        break;
                    case 0xE5:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_SET_PLAYER_LOCK $%02X"(arg);
                        break;
                    case 0xE6:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_DELAY_TPT_APPEARANCE $%04X"(arg);
                        break;
                    case 0xE7:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1F_E7 $%04X"(arg);
                        break;
                    case 0xE8:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_RESTRICT_PLAYER_MOVEMENT_WHEN_CAMERA_REPOSITIONED $%02X"(arg);
                        break;
                    case 0xE9:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1F_E9 $%04X"(arg);
                        break;
                    case 0xEA:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1F_EA $%04X"(arg);
                        break;
                    case 0xEB:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_MAKE_INVISIBLE $%02X, $%02X"(arg, arg2);
                        break;
                    case 0xEC:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_MAKE_VISIBLE $%02X, $%02X"(arg, arg2);
                        break;
                    case 0xED:
                        writeLine("\tEBTEXT_RESTORE_MOVEMENT");
                        break;
                    case 0xEE:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_WARP_PARTY_TO_TPT_ENTRY $%04X"(arg);
                        break;
                    case 0xEF:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1F_EF $%04X"(arg);
                        break;
                    case 0xF0:
                        writeLine("\tEBTEXT_RIDE_BICYCLE");
                        break;
                    case 0xF1:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_SET_TPT_MOVEMENT_CODE $%04X, EVENT_SCRIPT::%s"(arg, movements[arg2]);
                        break;
                    case 0xF2:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_SET_SPRITE_MOVEMENT_CODE OVERWORLD_SPRITE::%s, EVENT_SCRIPT::%s"(sprites[arg], movements[arg2]);
                        break;
                    case 0xF3:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_CREATE_FLOATING_SPRITE_NEAR_ENTITY $%04X, $%02X"(arg, arg2);
                        break;
                    case 0xF4:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_DELETE_FLOATING_SPRITE_NEAR_ENTITY $%04X"(arg);
                        break;
                    default:
                        writeFormatted!"UNHANDLED: 1F %02X"(subCC);
                        break;
                }
                break;
            default:
                flushBuffs();
                writeFormatted!"\t.BYTE $%02X"(first);
                break;
        }
    }
    if (jpText) {
        return [filename, symbolFilename];
    } else {
        return [filename, uncompressedFilename, symbolFilename];
    }
}
