module textdump;

import std.exception;
import std.format;
import std.path;
import std.stdio;

import siryul;
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


string[] parseTextData(string dir, string baseName, string, ubyte[] source, ulong offset, const DumpDoc doc, const CommonData commonData) {
    import std.algorithm.searching : canFind;
    import std.array : empty, front, popFront;
    const jpText = doc.dontUseTextTable;
    auto filename = setExtension(baseName, "yaml");
    auto uncompressedFilename = setExtension(baseName, "uncompressed.yaml");
    StructuredText[][string] result;
    StructuredText[][string] resultUncompressed;
    StructuredText[] currentScript;
    StructuredText[] currentScriptUncompressed;
    ubyte[] raw;
    string tmpbuff;
    string tmpCompbuff;
    bool labelPrinted;
    string label(const ulong addr) {
        return addr in doc.renameLabels ? doc.renameLabels[addr] : format!"textBlock%06X"(addr);
    }
    string nextLabel = label(offset);
    auto nextByte() {
        labelPrinted = false;
        auto first = source.front;
        source.popFront();
        offset++;
        return first;
    }
    ushort nextShort() {
        return nextByte() + (nextByte() << 8);
    }
    uint nextInt() {
        return nextShort() + (nextShort() << 16);
    }
    void addEntry(StructuredText txt) {
        currentScript ~= txt;
        currentScriptUncompressed ~= txt;
    }
    void flushBuff() {
        if (tmpbuff == []) {
            return;
        }
        StructuredText entry = { text: tmpbuff };
        addEntry(entry);
        raw = [];
        tmpbuff = [];
    }
    void flushCompressedBuff() {
        if ((tmpCompbuff == []) || jpText) {
            return;
        }
        StructuredText entry;
        entry.text = tmpCompbuff;
        currentScriptUncompressed ~= entry;
        tmpCompbuff = [];
    }
    void flushBuffs() {
        flushBuff();
        if (!jpText) {
            flushCompressedBuff();
        }
    }
    void nextScript() {
        if (labelPrinted || source.empty) {
            return;
        }
        flushBuffs();
        result[nextLabel] = currentScript;
        currentScript = [];
        resultUncompressed[nextLabel] = currentScriptUncompressed;
        nextLabel = label(offset);
        currentScriptUncompressed = [];
        labelPrinted = true;
    }
    while (!source.empty) {
        if (doc.forceTextLabels.canFind(offset)) {
            nextScript();
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
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.lineBreak };
                addEntry(entry);
                break;
            case 0x01:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.startBlankLine };
                addEntry(entry);
                break;
            case 0x02:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.halt };
                addEntry(entry);
                nextScript();
                break;
            case 0x03:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.haltVariablePrompt };
                addEntry(entry);
                break;
            case 0x04:
                flushBuffs();
                const flag = nextShort();
                enforce(flag < 0x400, format!"Event flag %02X out of range (%06X)"(flag, offset));
                StructuredText entry = { mainCC: MainCC.setFlag, eventFlag: commonData.eventFlags[flag] };
                addEntry(entry);
                break;
            case 0x05:
                flushBuffs();
                const flag = nextShort();
                enforce(flag < 0x400, format!"Event flag %02X out of range (%06X)"(flag, offset));
                StructuredText entry = { mainCC: MainCC.clearFlag, eventFlag: commonData.eventFlags[flag] };
                addEntry(entry);
                break;
            case 0x06:
                flushBuffs();
                const flag = nextShort();
                const dest = nextInt();
                enforce(flag < 0x400, format!"Event flag %02X out of range (%06X)"(flag, offset));
                StructuredText entry = { mainCC: MainCC.jumpIfFlagSet, eventFlag: commonData.eventFlags[flag], labels: [ label(dest) ] };
                addEntry(entry);
                break;
            case 0x07:
                flushBuffs();
                const flag = nextShort();
                enforce(flag < 0x400, format!"Event flag %02X out of range (%06X)"(flag, offset));
                StructuredText entry = { mainCC: MainCC.getFlag, eventFlag: commonData.eventFlags[flag] };
                addEntry(entry);
                break;
            case 0x08:
                flushBuffs();
                const dest = nextInt();
                StructuredText entry = { mainCC: MainCC.call, labels: [ label(dest) ] };
                addEntry(entry);
                break;
            case 0x09:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.jumpSwitch };
                auto argCount = nextByte();
                while(argCount--) {
                    entry.labels ~= label(nextInt());
                }
                addEntry(entry);
                break;
            case 0x0A:
                flushBuffs();
                const dest = nextInt();
                StructuredText entry = { mainCC: MainCC.jump, labels: [ label(dest) ] };
                addEntry(entry);
                break;
            case 0x0B:
                flushBuffs();
                const arg = nextByte();
                StructuredText entry = { mainCC: MainCC.testWorkMemoryTrue, byteValues: [ arg ] };
                addEntry(entry);
                break;
            case 0x0C:
                flushBuffs();
                auto arg = nextByte();
                StructuredText entry = { mainCC: MainCC.testWorkMemoryFalse, byteValues: [ arg ] };
                addEntry(entry);
                break;
            case 0x0D:
                flushBuffs();
                auto dest = nextByte();
                StructuredText entry = { mainCC: MainCC.copyToArgMemory, cc0DArgument: cast(CC0DArgument)dest };
                addEntry(entry);
                break;
            case 0x0E:
                flushBuffs();
                auto dest = nextByte();
                StructuredText entry = { mainCC: MainCC.storeSecondaryMemory, byteValues: [ dest ] };
                addEntry(entry);
                break;
            case 0x0F:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.incrementSecondaryMemory };
                addEntry(entry);
                break;
            case 0x10:
                flushBuffs();
                auto time = nextByte();
                StructuredText entry = { mainCC: MainCC.pause, byteValues: [ time ] };
                addEntry(entry);
                break;
            case 0x11:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.createMenu };
                addEntry(entry);
                break;
            case 0x12:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.clearLine };
                addEntry(entry);
                break;
            case 0x13:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.haltWithoutTriangle };
                addEntry(entry);
                break;
            case 0x14:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.haltWithPrompt };
                addEntry(entry);
                break;
            case 0x15: .. case 0x17:
                flushBuff();
                StructuredText entry = { mainCC: cast(MainCC)(MainCC.compressed1 + (first - 0x15)) };
                if (doc.supportsCompressedText) {
                    auto arg = nextByte();
                    auto id = ((first - 0x15) << 8) + arg;
                    entry.byteValues = [ arg ];
                    tmpCompbuff ~= doc.compressedTextStrings[id];
                } else {
                    throw new Exception("Compressed text doesn't exist!");
                }
                currentScript ~= entry;
                break;
            case 0x18:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.manageWindows };
                entry.subCC = nextByte();
                switch (cast(SubCC18)entry.subCC.get()) {
                    case SubCC18.closeWindow:
                    case SubCC18.saveWindow:
                    case SubCC18.closeAllWindows:
                    case SubCC18.clearWindow:
                    case SubCC18.showWalletWindow:
                        break;
                    case SubCC18.openWindow:
                    case SubCC18.switchWindow:
                    case SubCC18.menuInWindow:
                    case SubCC18.cancellableMenuInWindow:
                        entry.window = commonData.windows[nextByte()];
                        break;
                    case SubCC18.setTextAlignment:
                        entry.byteValues = [ nextByte(), nextByte() ];
                        break;
                    case SubCC18.compareRegisterWithNumber:
                        entry.intValues = [ nextInt() ];
                        entry.byteValues = [ nextByte() ];
                        break;
                    default:
                        throw new Exception(format!"Unhandled CC: 18 %02X"(entry.subCC));
                }
                addEntry(entry);
                break;
            case 0x19:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.misc19 };
                entry.subCC = nextByte();
                switch (cast(SubCC19)entry.subCC.get()) {
                    case SubCC19.clearStrings:
                    case SubCC19.returnEscargoExpressItemAutoIncrement:
                    case SubCC19.getDelta:
                    case SubCC19.getBattleActionArgument:
                    case SubCC19.returnPartyCount:
                        break;
                    case SubCC19.loadString:
                        string payload;
                        while (auto x = nextByte()) {
                            if (x == 1) {
                                entry.byteValues ~= 0x01;
                                entry.labels = [ label(nextInt()) ];
                                break;
                            } else if (x == 2) {
                                entry.byteValues ~= 0x02;
                                break;
                            } else {
                                entry.text ~= doc.textTable[x];
                            }
                        }
                        break;
                    case SubCC19.inflictStatus:
                        entry.byteValues = [ nextByte(), nextByte(), nextByte() ];
                        break;
                    case SubCC19.returnCharacterNumber:
                    case SubCC19.returnCharacterLetter:
                    case SubCC19.returnCharacterEXPNeeded:
                    case SubCC19.returnEscargoExpressItem:
                    case SubCC19.returnMenuItemCount:
                    case SubCC19.returnFoodCategory:
                    case SubCC19.returnMatchingCondimentID:
                    case SubCC19.setRespawnPoint:
                    case SubCC19.returnStatValue:
                    case SubCC19.returnStatLetter:
                        entry.byteValues = [ nextByte() ];
                        break;
                    case SubCC19.returnCharacterStatusByte:
                    case SubCC19.returnCharacterInventoryItem:
                    case SubCC19.queueItemForDelivery:
                    case SubCC19.getQueuedItem:
                        entry.byteValues = [ nextByte(), nextByte() ];
                        break;
                    case SubCC19.returnDirectionFromCharacterToObject:
                        entry.byteValues = [ nextByte(), nextByte() ];
                        entry.shortValues = [ nextShort() ];
                        break;
                    case SubCC19.returnDirectionFromNPCToObject:
                    case SubCC19.returnDirectionFromGeneratedSpriteToObject:
                        entry.shortValues = [ nextShort() ];
                        entry.byteValues = [ nextByte() ];
                        entry.shortValues ~= nextShort();
                        break;
                    default:
                        throw new Exception(format!"Unhandled: 19 %02X"(entry.subCC));
                }
                addEntry(entry);
                break;
            case 0x1A:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.menus };
                entry.subCC = nextByte();
                switch (cast(SubCC1A)entry.subCC.get()) {
                    case SubCC1A.cc04:
                    case SubCC1A.cc07:
                    case SubCC1A.cc08:
                    case SubCC1A.cc09:
                    case SubCC1A.cc0A:
                    case SubCC1A.cc0B:
                        break;
                    case SubCC1A.cc00:
                    case SubCC1A.cc01:
                        entry.labels = [ label(nextInt()), label(nextInt()), label(nextInt()), label(nextInt()) ];
                        entry.byteValues = [ nextByte() ];
                        break;
                    case SubCC1A.cc05:
                        entry.byteValues = [ nextByte(), nextByte() ];
                        break;
                    case SubCC1A.cc06:
                        entry.byteValues = [ nextByte() ];
                        break;
                    default:
                        throw new Exception(format!"UNHANDLED: 1A %02X"(entry.subCC));
                }
                addEntry(entry);
                break;
            case 0x1B:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.memory };
                entry.subCC = nextByte();
                switch (cast(SubCC1B)entry.subCC.get()) {
                    case SubCC1B.cc00:
                    case SubCC1B.cc01:
                    case SubCC1B.cc04:
                    case SubCC1B.cc05:
                    case SubCC1B.cc06:
                        break;
                    case SubCC1B.cc02:
                    case SubCC1B.cc03:
                        entry.labels = [ label(nextInt()) ];
                        break;
                    default:
                        throw new Exception(format!"UNHANDLED: 1B %02X"(entry.subCC));
                }
                addEntry(entry);
                break;
            case 0x1C:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.misc1C };
                entry.subCC = nextByte();
                switch (cast(SubCC1C)entry.subCC.get()) {
                    case SubCC1C.cc04:
                    case SubCC1C.cc0D:
                    case SubCC1C.cc0E:
                    case SubCC1C.cc0F:
                        break;
                    case SubCC1C.cc00:
                    case SubCC1C.cc01:
                    case SubCC1C.cc02:
                    case SubCC1C.cc03:
                    case SubCC1C.cc05:
                    case SubCC1C.cc06:
                    case SubCC1C.cc07:
                    case SubCC1C.cc08:
                    case SubCC1C.cc09:
                    case SubCC1C.cc0C:
                    case SubCC1C.cc11:
                    case SubCC1C.cc12:
                    case SubCC1C.cc14:
                    case SubCC1C.cc15:
                        entry.byteValues = [ nextByte() ];
                        break;
                    case SubCC1C.cc0A:
                    case SubCC1C.cc0B:
                        entry.intValues = [ nextInt() ];
                        break;
                    case SubCC1C.cc13:
                        entry.byteValues = [ nextByte(), nextByte() ];
                        break;
                    default:
                        throw new Exception(format!"UNHANDLED: 1C %02X"(entry.subCC));
                }
                addEntry(entry);
                break;
            case 0x1D:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.inventory };
                entry.subCC = nextByte();
                switch (cast(SubCC1D)entry.subCC.get()) {
                    case SubCC1D.cc20:
                    case SubCC1D.cc22:
                        break;
                    case SubCC1D.cc00:
                    case SubCC1D.cc01:
                    case SubCC1D.cc04:
                    case SubCC1D.cc05:
                    case SubCC1D.cc0E:
                    case SubCC1D.cc0F:
                    case SubCC1D.cc10:
                    case SubCC1D.cc11:
                    case SubCC1D.cc12:
                    case SubCC1D.cc13:
                        entry.byteValues = [ nextByte(), nextByte() ];
                        break;
                    case SubCC1D.cc02:
                    case SubCC1D.cc03:
                    case SubCC1D.cc0A:
                    case SubCC1D.cc0B:
                    case SubCC1D.cc18:
                    case SubCC1D.cc19:
                    case SubCC1D.cc21:
                    case SubCC1D.cc23:
                    case SubCC1D.cc24:
                        entry.byteValues = [ nextByte() ];
                        break;
                    case SubCC1D.cc06:
                    case SubCC1D.cc07:
                    case SubCC1D.cc14:
                    case SubCC1D.cc17:
                        entry.intValues = [ nextInt() ];
                        break;
                    case SubCC1D.cc08:
                    case SubCC1D.cc09:
                    case SubCC1D.cc0C:
                    case SubCC1D.cc15:
                        entry.shortValues = [ nextShort() ];
                        break;
                    case SubCC1D.cc0D:
                        entry.byteValues = [ nextByte(), nextByte(), nextByte() ];
                        break;
                    default:
                        throw new Exception(format!"UNHANDLED: 1D %02X"(entry.subCC));
                }
                addEntry(entry);
                break;
            case 0x1E:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.stats };
                entry.subCC = nextByte();
                switch (cast(SubCC1E)entry.subCC.get()) {
                    case SubCC1E.cc00:
                    case SubCC1E.cc01:
                    case SubCC1E.cc02:
                    case SubCC1E.cc03:
                    case SubCC1E.cc04:
                    case SubCC1E.cc05:
                    case SubCC1E.cc06:
                    case SubCC1E.cc07:
                    case SubCC1E.cc08:
                    case SubCC1E.cc0A:
                    case SubCC1E.cc0B:
                    case SubCC1E.cc0C:
                    case SubCC1E.cc0D:
                    case SubCC1E.cc0E:
                        entry.byteValues = [ nextByte(), nextByte() ];
                        break;
                    case SubCC1E.cc09:
                        entry.byteValues = [ nextByte() ];
                        entry.intValues = [ nextInt() ];
                        break;
                    default:
                        throw new Exception(format!"UNHANDLED: 1E %02X"(entry.subCC));
                }
                addEntry(entry);
                break;
            case 0x1F:
                flushBuffs();
                StructuredText entry = { mainCC: MainCC.misc1F };
                entry.subCC = nextByte();
                switch (cast(SubCC1F)entry.subCC.get()) {
                    case SubCC1F.cc03:
                    case SubCC1F.cc05:
                    case SubCC1F.cc06:
                    case SubCC1F.cc30:
                    case SubCC1F.cc31:
                    case SubCC1F.cc50:
                    case SubCC1F.cc51:
                    case SubCC1F.cc61:
                    case SubCC1F.cc64:
                    case SubCC1F.cc65:
                    case SubCC1F.cc68:
                    case SubCC1F.cc69:
                    case SubCC1F.ccA0:
                    case SubCC1F.ccA1:
                    case SubCC1F.ccA2:
                    case SubCC1F.ccB0:
                    case SubCC1F.ccD1:
                    case SubCC1F.ccED:
                    case SubCC1F.ccF0:
                        break;
                    case SubCC1F.cc00:
                    case SubCC1F.cc13:
                    case SubCC1F.cc1C:
                    case SubCC1F.cc20:
                    case SubCC1F.cc71:
                    case SubCC1F.cc83:
                    case SubCC1F.ccEB:
                    case SubCC1F.ccEC:
                        entry.byteValues = [ nextByte(), nextByte() ];
                        break;
                    case SubCC1F.cc01:
                    case SubCC1F.cc02:
                    case SubCC1F.cc04:
                    case SubCC1F.cc07:
                    case SubCC1F.cc11:
                    case SubCC1F.cc12:
                    case SubCC1F.cc14:
                    case SubCC1F.cc1D:
                    case SubCC1F.cc21:
                    case SubCC1F.cc41:
                    case SubCC1F.cc52:
                    case SubCC1F.cc60:
                    case SubCC1F.cc62:
                    case SubCC1F.cc67:
                    case SubCC1F.ccD0:
                    case SubCC1F.ccD2:
                    case SubCC1F.ccD3:
                    case SubCC1F.ccE5:
                    case SubCC1F.ccE8:
                        entry.byteValues = [ nextByte() ];
                        break;
                    case SubCC1F.cc15:
                    case SubCC1F.cc17:
                        entry.shortValues = [ nextShort(), nextShort() ];
                        entry.byteValues = [ nextByte() ];
                        break;
                    case SubCC1F.cc16:
                    case SubCC1F.cc1A:
                    case SubCC1F.cc1E:
                    case SubCC1F.cc1F:
                    case SubCC1F.ccE4:
                    case SubCC1F.ccF3:
                        entry.shortValues = [ nextShort() ];
                        entry.byteValues = [ nextByte() ];
                        break;
                    case SubCC1F.cc1B:
                    case SubCC1F.cc23:
                    case SubCC1F.ccE6:
                    case SubCC1F.ccE7:
                    case SubCC1F.ccE9:
                    case SubCC1F.ccEA:
                    case SubCC1F.ccEE:
                    case SubCC1F.ccEF:
                    case SubCC1F.ccF4:
                        entry.shortValues = [ nextShort() ];
                        break;
                    case SubCC1F.cc63:
                        entry.labels = [ label(nextInt()) ];
                        break;
                    case SubCC1F.cc66:
                        entry.byteValues = [ nextByte(), nextByte() ];
                        entry.labels = [ label(nextInt()) ];
                        break;
                    case SubCC1F.ccC0:
                        flushBuffs();
                        ubyte argCount = nextByte();
                        while(argCount--) {
                            entry.labels ~= label(nextInt());
                        }
                        break;
                    case SubCC1F.ccE1:
                        entry.byteValues = [ nextByte(), nextByte(), nextByte() ];
                        break;
                    case SubCC1F.ccF1:
                    case SubCC1F.ccF2:
                        entry.shortValues = [ nextShort(), nextShort() ];
                        break;
                    default:
                        throw new Exception(format!"UNHANDLED: 1F %02X"(entry.subCC));
                }
                addEntry(entry);
                break;
            default:
                throw new Exception(format!"I don't know what this is: %06X: %02X"(offset, first));
        }
    }
    result.toFile!(YAML, Siryulize.omitInits)(buildPath(dir, filename));
    if (jpText) {
        return [filename];
    } else {
        resultUncompressed.toFile!(YAML, Siryulize.omitInits)(buildPath(dir, uncompressedFilename));
        return [filename, uncompressedFilename];
    }
}


enum MainCC : ubyte {
    lineBreak = 0x00,
    startBlankLine = 0x01,
    halt = 0x02,
    haltVariablePrompt = 0x03,
    setFlag = 0x04,
    clearFlag = 0x05,
    jumpIfFlagSet = 0x06,
    getFlag = 0x07,
    call = 0x08,
    jumpSwitch = 0x09,
    jump = 0x0A,
    testWorkMemoryTrue = 0x0B,
    testWorkMemoryFalse = 0x0C,
    copyToArgMemory = 0x0D,
    storeSecondaryMemory = 0x0E,
    incrementSecondaryMemory = 0x0F,
    pause = 0x10,
    createMenu = 0x11,
    clearLine = 0x12,
    haltWithoutTriangle = 0x13,
    haltWithPrompt = 0x14,
    compressed1 = 0x15,
    compressed2 = 0x16,
    compressed3 = 0x17,
    manageWindows = 0x18,
    misc19 = 0x19,
    menus = 0x1A,
    memory = 0x1B,
    misc1C = 0x1C,
    inventory = 0x1D,
    stats = 0x1E,
    misc1F = 0x1F
}

enum SubCC18 : ubyte {
    closeWindow = 0x00,
    openWindow = 0x01,
    saveWindow = 0x02,
    switchWindow = 0x03,
    closeAllWindows = 0x04,
    setTextAlignment = 0x05,
    clearWindow = 0x06,
    compareRegisterWithNumber = 0x07,
    menuInWindow = 0x08,
    cancellableMenuInWindow = 0x09,
    showWalletWindow = 0x0A,
    printCharacterStatus = 0x0D,
}

enum SubCC19 : ubyte {
    loadString = 0x02,
    clearStrings = 0x04,
    inflictStatus = 0x05,
    returnCharacterNumber = 0x10,
    returnCharacterLetter = 0x11,
    returnEscargoExpressItemAutoIncrement = 0x14,
    returnCharacterStatusByte = 0x16,
    returnCharacterEXPNeeded = 0x18,
    returnCharacterInventoryItem = 0x19,
    returnEscargoExpressItem = 0x1A,
    returnMenuItemCount = 0x1B,
    queueItemForDelivery = 0x1C,
    getQueuedItem = 0x1D,
    getDelta = 0x1E,
    getBattleActionArgument = 0x1F,
    returnPartyCount = 0x20,
    returnFoodCategory = 0x21,
    returnDirectionFromCharacterToObject = 0x22,
    returnDirectionFromNPCToObject = 0x23,
    returnDirectionFromGeneratedSpriteToObject = 0x24,
    returnMatchingCondimentID = 0x25,
    setRespawnPoint = 0x26,
    returnStatValue = 0x27,
    returnStatLetter = 0x28,
}

enum SubCC1A : ubyte {
    cc00 = 0x00,
    cc01 = 0x01,
    cc04 = 0x04,
    cc05 = 0x05,
    cc06 = 0x06,
    cc07 = 0x07,
    cc08 = 0x08,
    cc09 = 0x09,
    cc0A = 0x0A,
    cc0B = 0x0B,
}

enum SubCC1B : ubyte {
    cc00 = 0x00,
    cc01 = 0x01,
    cc02 = 0x02,
    cc03 = 0x03,
    cc04 = 0x04,
    cc05 = 0x05,
    cc06 = 0x06,
}

enum SubCC1C : ubyte {
    cc00 = 0x00,
    cc01 = 0x01,
    cc02 = 0x02,
    cc03 = 0x03,
    cc04 = 0x04,
    cc05 = 0x05,
    cc06 = 0x06,
    cc07 = 0x07,
    cc08 = 0x08,
    cc09 = 0x09,
    cc0A = 0x0A,
    cc0B = 0x0B,
    cc0C = 0x0C,
    cc0D = 0x0D,
    cc0E = 0x0E,
    cc0F = 0x0F,
    cc11 = 0x11,
    cc12 = 0x12,
    cc13 = 0x13,
    cc14 = 0x14,
    cc15 = 0x15,
}

enum SubCC1D : ubyte {
    cc00 = 0x00,
    cc01 = 0x01,
    cc02 = 0x02,
    cc03 = 0x03,
    cc04 = 0x04,
    cc05 = 0x05,
    cc06 = 0x06,
    cc07 = 0x07,
    cc08 = 0x08,
    cc09 = 0x09,
    cc0A = 0x0A,
    cc0B = 0x0B,
    cc0C = 0x0C,
    cc0D = 0x0D,
    cc0E = 0x0E,
    cc0F = 0x0F,
    cc10 = 0x10,
    cc11 = 0x11,
    cc12 = 0x12,
    cc13 = 0x13,
    cc14 = 0x14,
    cc15 = 0x15,
    cc17 = 0x17,
    cc18 = 0x18,
    cc19 = 0x19,
    cc20 = 0x20,
    cc21 = 0x21,
    cc22 = 0x22,
    cc23 = 0x23,
    cc24 = 0x24,
}

enum SubCC1E : ubyte {
    cc00 = 0x00,
    cc01 = 0x01,
    cc02 = 0x02,
    cc03 = 0x03,
    cc04 = 0x04,
    cc05 = 0x05,
    cc06 = 0x06,
    cc07 = 0x07,
    cc08 = 0x08,
    cc09 = 0x09,
    cc0A = 0x0A,
    cc0B = 0x0B,
    cc0C = 0x0C,
    cc0D = 0x0D,
    cc0E = 0x0E,
}

enum SubCC1F : ubyte {
    cc00 = 0x00,
    cc01 = 0x01,
    cc02 = 0x02,
    cc03 = 0x03,
    cc04 = 0x04,
    cc05 = 0x05,
    cc06 = 0x06,
    cc07 = 0x07,
    cc11 = 0x11,
    cc12 = 0x12,
    cc13 = 0x13,
    cc14 = 0x14,
    cc15 = 0x15,
    cc16 = 0x16,
    cc17 = 0x17,
    cc18 = 0x18,
    cc19 = 0x19,
    cc1A = 0x1A,
    cc1B = 0x1B,
    cc1C = 0x1C,
    cc1D = 0x1D,
    cc1E = 0x1E,
    cc1F = 0x1F,
    cc20 = 0x20,
    cc21 = 0x21,
    cc23 = 0x23,
    cc30 = 0x30,
    cc31 = 0x31,
    cc40 = 0x40,
    cc41 = 0x41,
    cc50 = 0x50,
    cc51 = 0x51,
    cc52 = 0x52,
    cc60 = 0x60,
    cc61 = 0x61,
    cc62 = 0x62,
    cc63 = 0x63,
    cc64 = 0x64,
    cc65 = 0x65,
    cc66 = 0x66,
    cc67 = 0x67,
    cc68 = 0x68,
    cc69 = 0x69,
    cc71 = 0x71,
    cc81 = 0x81,
    cc83 = 0x83,
    cc90 = 0x90,
    ccA0 = 0xA0,
    ccA1 = 0xA1,
    ccA2 = 0xA2,
    ccB0 = 0xB0,
    ccC0 = 0xC0,
    ccD0 = 0xD0,
    ccD1 = 0xD1,
    ccD2 = 0xD2,
    ccD3 = 0xD3,
    ccE1 = 0xE1,
    ccE4 = 0xE4,
    ccE5 = 0xE5,
    ccE6 = 0xE6,
    ccE7 = 0xE7,
    ccE8 = 0xE8,
    ccE9 = 0xE9,
    ccEA = 0xEA,
    ccEB = 0xEB,
    ccEC = 0xEC,
    ccED = 0xED,
    ccEE = 0xEE,
    ccEF = 0xEF,
    ccF0 = 0xF0,
    ccF1 = 0xF1,
    ccF2 = 0xF2,
    ccF3 = 0xF3,
    ccF4 = 0xF4,
}

enum CC0DArgument : ubyte {
    workingMemory = 0x00,
    secondaryMemory = 0x01,
}

struct StructuredText {
    import std.typecons : Nullable;
    Nullable!MainCC mainCC;
    Nullable!ubyte subCC;
    string text;
    Nullable!string eventFlag;
    string[] labels;
    ubyte[] byteValues;
    ushort[] shortValues;
    uint[] intValues;
    Nullable!CC0DArgument cc0DArgument;
    Nullable!string window;
}