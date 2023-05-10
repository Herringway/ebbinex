module textdump;

import std.exception;
import std.format;
import std.path;
import std.stdio;

import siryul;
import common;

string[] parseTextData(string dir, string baseName, string, ubyte[] source, ulong offset, const DumpDoc doc, const CommonData commonData) {
    import std.algorithm.searching : canFind;
    import std.array : empty, front, popFront;
    TextFile[string] textFiles;
    foreach (entry; doc.dumpEntries) {
        if (entry.extension == "ebtxt") {
            textFiles[entry.name] = TextFile(entry.offset + 0xC00000, entry.size);
        }
    }
    if (!doc.d) {
        return parseTextDataAssembly(dir, baseName, "", source, offset, doc, commonData);
    }
    const jpText = doc.dontUseTextTable;
    auto filename = setExtension(baseName, "yaml");
    auto uncompressedFilename = setExtension(baseName, "uncompressed.yaml");
    StructuredText[][string][] result;
    StructuredText[][string][] resultUncompressed;
    StructuredText[] currentScript;
    StructuredText[] currentScriptUncompressed;
    ubyte[] raw;
    string tmpbuff;
    string tmpCompbuff;
    string label(const ulong addr) {
        if (addr == 0) {
            return "null";
        }
        foreach (name, file; textFiles) {
            if ((addr >= file.start) && (addr < file.start + file.length)) {
                if (auto found = (addr - file.start) in doc.renameLabels.get(name, null)) {
                    return *found;
                }
                throw new Exception(format!"No label found for %s/%04X"(name, addr - file.start));
            }
        }
        throw new Exception("No matching files");
    }
    string nextLabel = label(offset);
    auto nextByte() {
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
        currentScript ~= entry;
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
        if (currentScript.length == 0) {
            return;
        }
        flushBuffs();
        result ~= [nextLabel: currentScript];
        currentScript = [];
        resultUncompressed ~= [nextLabel: currentScriptUncompressed];
        nextLabel = label(offset);
        currentScriptUncompressed = [];
    }
    while (!source.empty) {
        foreach (name, textFile; textFiles) {
            if ((offset >= textFile.start) && (offset < textFile.start + textFile.length)) {
                if ((offset - textFile.start) in doc.renameLabels.get(name, null)) {
                    nextScript();
                    break;
                }
            }
        }
        auto first = nextByte();
        if (first in doc.textTable) {
            raw ~= first;
            tmpbuff ~= doc.textTable[first];
            tmpCompbuff ~= doc.textTable[first];
            continue;
        }
        if ((first >= 0x15) && (first <= 0x18)) {
            flushBuff();
        } else {
            flushBuffs();
        }
        switch (first) {
            case 0x00:
                StructuredText entry = { mainCC: MainCC.lineBreak };
                addEntry(entry);
                break;
            case 0x01:
                StructuredText entry = { mainCC: MainCC.startBlankLine };
                addEntry(entry);
                break;
            case 0x02:
                StructuredText entry = { mainCC: MainCC.halt };
                addEntry(entry);
                nextScript();
                break;
            case 0x03:
                StructuredText entry = { mainCC: MainCC.haltVariablePrompt };
                addEntry(entry);
                break;
            case 0x04:
                const flag = nextShort();
                enforce(flag < 0x400, format!"Event flag %02X out of range (%06X)"(flag, offset));
                StructuredText entry = { mainCC: MainCC.setFlag, eventFlag: commonData.eventFlags[flag] };
                addEntry(entry);
                break;
            case 0x05:
                const flag = nextShort();
                enforce(flag < 0x400, format!"Event flag %02X out of range (%06X)"(flag, offset));
                StructuredText entry = { mainCC: MainCC.clearFlag, eventFlag: commonData.eventFlags[flag] };
                addEntry(entry);
                break;
            case 0x06:
                const flag = nextShort();
                const dest = nextInt();
                enforce(flag < 0x400, format!"Event flag %02X out of range (%06X)"(flag, offset));
                StructuredText entry = { mainCC: MainCC.jumpIfFlagSet, eventFlag: commonData.eventFlags[flag], labels: [ label(dest) ] };
                addEntry(entry);
                break;
            case 0x07:
                const flag = nextShort();
                enforce(flag < 0x400, format!"Event flag %02X out of range (%06X)"(flag, offset));
                StructuredText entry = { mainCC: MainCC.getFlag, eventFlag: commonData.eventFlags[flag] };
                addEntry(entry);
                break;
            case 0x08:
                const dest = nextInt();
                StructuredText entry = { mainCC: MainCC.call, labels: [ label(dest) ] };
                addEntry(entry);
                break;
            case 0x09:
                StructuredText entry = { mainCC: MainCC.jumpSwitch };
                auto argCount = nextByte();
                while(argCount--) {
                    entry.labels ~= label(nextInt());
                }
                addEntry(entry);
                break;
            case 0x0A:
                const dest = nextInt();
                StructuredText entry = { mainCC: MainCC.jump, labels: [ label(dest) ] };
                addEntry(entry);
                nextScript();
                break;
            case 0x0B:
                const arg = nextByte();
                StructuredText entry = { mainCC: MainCC.testWorkMemoryTrue, byteValues: [ arg ] };
                addEntry(entry);
                break;
            case 0x0C:
                auto arg = nextByte();
                StructuredText entry = { mainCC: MainCC.testWorkMemoryFalse, byteValues: [ arg ] };
                addEntry(entry);
                break;
            case 0x0D:
                auto dest = nextByte();
                StructuredText entry = { mainCC: MainCC.copyToArgMemory, cc0DArgument: cast(CC0DArgument)dest };
                addEntry(entry);
                break;
            case 0x0E:
                auto dest = nextByte();
                StructuredText entry = { mainCC: MainCC.storeSecondaryMemory, byteValues: [ dest ] };
                addEntry(entry);
                break;
            case 0x0F:
                StructuredText entry = { mainCC: MainCC.incrementSecondaryMemory };
                addEntry(entry);
                break;
            case 0x10:
                auto time = nextByte();
                StructuredText entry = { mainCC: MainCC.pause, byteValues: [ time ] };
                addEntry(entry);
                break;
            case 0x11:
                StructuredText entry = { mainCC: MainCC.createMenu };
                addEntry(entry);
                break;
            case 0x12:
                StructuredText entry = { mainCC: MainCC.clearLine };
                addEntry(entry);
                break;
            case 0x13:
                StructuredText entry = { mainCC: MainCC.haltWithoutTriangle };
                addEntry(entry);
                break;
            case 0x14:
                StructuredText entry = { mainCC: MainCC.haltWithPrompt };
                addEntry(entry);
                break;
            case 0x15: .. case 0x17:
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
    if (currentScript.length > 0) { //whatever's left
        nextScript();
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

struct TextFile {
    size_t start;
    size_t length;
}

string[] parseTextDataAssembly(string dir, string baseName, string, ubyte[] source, ulong offset, const DumpDoc doc, const CommonData commonData) {
    import std.algorithm.searching : canFind;
    import std.array : empty, front, popFront;
    TextFile[string] textFiles;
    foreach (entry; doc.dumpEntries) {
        if (entry.extension == "ebtxt") {
            textFiles[entry.name] = TextFile(entry.offset + 0xC00000, entry.size);
        }
    }
    const jpText = doc.dontUseTextTable;
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
    bool labelPrinted;
    string label(const ulong addr, bool throwOnUndefined) {
        if (addr == 0) {
            return "NULL";
        }
        foreach (name, file; textFiles) {
            if ((addr >= file.start) && (addr < file.start + file.length)) {
                if (auto found = (addr - file.start) in doc.renameLabels.get(name, null)) {
                    return *found;
                }
                if (throwOnUndefined) {
                    throw new Exception(format!"No label found for %s/%04X"(name, addr - file.start));
                } else {
                    return "";
                }
            }
        }
        throw new Exception("No matching files");
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
            outFile.writefln!"\t.BYTE \"%(\\x%02X%)\" ;\"%s\""(raw, tmpbuff);
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
    void printLabel(bool throwOnUndefined) {
        if (labelPrinted || source.empty) {
            return;
        }
        const labelstr = label(offset, throwOnUndefined);
        if (labelstr == "") {
            return;
        }
        flushBuffs();
        symbolFile.writefln!".GLOBAL %s: far"(labelstr);
        writeLine();
        writeFormatted!"%s: ;$%06X"(labelstr, offset);
        labelPrinted = true;
    }
    printLabel(true);
    while (!source.empty) {
        foreach (name, textFile; textFiles) {
            if ((offset >= textFile.start) && (offset < textFile.start + textFile.length)) {
                if ((offset - textFile.start) in doc.renameLabels.get(name, null)) {
                    printLabel(true);
                    break;
                }
            }
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
                writeLine("\tEBTEXT_LINE_BREAK");
                break;
            case 0x01:
                flushBuffs();
                writeLine("\tEBTEXT_START_NEW_LINE");
                break;
            case 0x02:
                flushBuffs();
                writeLine("\tEBTEXT_END_BLOCK");
                printLabel(false);
                break;
            case 0x03:
                flushBuffs();
                writeLine("\tEBTEXT_HALT_WITH_PROMPT");
                break;
            case 0x04:
                flushBuffs();
                auto flag = nextByte() + (nextByte()<<8);
                writeFormatted!"\tEBTEXT_SET_EVENT_FLAG EVENT_FLAG::%s"(flag >= 0x400 ? format!"OVERFLOW%03X"(flag) : commonData.eventFlags[flag]);
                break;
            case 0x05:
                flushBuffs();
                auto flag = nextByte() + (nextByte()<<8);
                writeFormatted!"\tEBTEXT_CLEAR_EVENT_FLAG EVENT_FLAG::%s"(flag >= 0x400 ? format!"OVERFLOW%03X"(flag) : commonData.eventFlags[flag]);
                break;
            case 0x06:
                flushBuffs();
                auto flag = nextByte() + (nextByte()<<8);
                auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                //assert(flag < 0x400, "Event flag number too high");
                writeFormatted!"\tEBTEXT_JUMP_IF_FLAG_SET %s, EVENT_FLAG::%s"(label(dest, true), flag >= 0x400 ? format!"OVERFLOW%03X"(flag) : commonData.eventFlags[flag]);
                break;
            case 0x07:
                flushBuffs();
                auto flag = nextByte() + (nextByte()<<8);
                writeFormatted!"\tEBTEXT_CHECK_EVENT_FLAG EVENT_FLAG::%s"(commonData.eventFlags[flag]);
                break;
            case 0x08:
                flushBuffs();
                auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                writeFormatted!"\tEBTEXT_CALL_TEXT %s"(label(dest, true));
                break;
            case 0x09:
                flushBuffs();
                auto argCount = nextByte();
                string[] dests;
                while(argCount--) {
                    dests ~= label(nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24), true);
                }
                writeFormatted!"\tEBTEXT_JUMP_MULTI %-(%s%|, %)"(dests);
                break;
            case 0x0A:
                flushBuffs();
                auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                writeFormatted!"\tEBTEXT_JUMP %s\n"(label(dest, true));
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
                if (doc.supportsCompressedText) {
                    auto arg = nextByte();
                    auto id = ((first - 0x15)<<8) + arg;
                    outFile.writefln!"\tEBTEXT_COMPRESSED_BANK_%d $%02X ;\"%s\""(first-0x14, arg, doc.compressedTextStrings[id]);
                    tmpCompbuff ~= doc.compressedTextStrings[id];
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
                        writeFormatted!"\tEBTEXT_OPEN_WINDOW WINDOW::%s"(commonData.windows[arg]);
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
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_18_09 $%02X"(arg);
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
                        string payload;
                        string jpTextBuffer;
                        while (auto x = nextByte()) {
                            if (x == 1) {
                                if (jpText) {
                                    writeFormatted!"\tEBTEXT_LOAD_STRING_TO_MEMORY_WITH_SELECT_SCRIPT \"%s\", %s ; \"%s\""(payload, label(nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24), true), jpTextBuffer);
                                } else {
                                    writeFormatted!"\tEBTEXT_LOAD_STRING_TO_MEMORY_WITH_SELECT_SCRIPT \"%s\", %s"(payload, label(nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24), true));
                                }
                                break;
                            } else if (x == 2) {
                                if (jpText) {
                                    writeFormatted!"\tEBTEXT_LOAD_STRING_TO_MEMORY \"%s\" ; \"%s\""(payload, jpTextBuffer);
                                } else {
                                    writeFormatted!"\tEBTEXT_LOAD_STRING_TO_MEMORY \"%s\""(payload);
                                }
                                break;
                            } else {
                                if (jpText) {
                                    payload ~= format!"\\x%02X"(x);
                                    jpTextBuffer ~= doc.textTable[x];
                                } else {
                                    payload ~= doc.textTable[x];
                                }
                            }
                        }
                        break;
                    case 0x04:
                        writeLine("\tEBTEXT_CLEAR_LOADED_STRINGS");
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto statusGroup = nextByte();
                        auto status = nextByte();
                        writeFormatted!"\tEBTEXT_INFLICT_STATUS PARTY_MEMBER_TEXT::%s, $%02X, $%02X"(commonData.partyMembers[arg+1], statusGroup, status);
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
                        writeFormatted!"\tEBTEXT_PARTY_MEMBER_SELECTION_MENU_UNCANCELLABLE %s, %s, %s, %s, $%02X"(label(dest, true), label(dest2, true), label(dest3, true), label(dest4, true), arg5);
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
                        writeFormatted!"\tEBTEXT_JUMP_IF_FALSE %s"(label(dest, true));
                        break;
                    case 0x03:
                        auto dest = nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24);
                        writeFormatted!"\tEBTEXT_JUMP_IF_TRUE %s"(label(dest, true));
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
                        writeFormatted!"\tEBTEXT_PRINT_ITEM_NAME ITEM::%s"(commonData.items[arg]);
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
                        writeFormatted!"\tEBTEXT_GIVE_ITEM_TO_CHARACTER $%02X, ITEM::%s"(arg, commonData.items[arg2]);
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_TAKE_ITEM_FROM_CHARACTER $%02X, ITEM::%s"(arg, commonData.items[arg2]);
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
                        writeFormatted!"\tEBTEXT_CHECK_IF_CHARACTER_DOESNT_HAVE_ITEM $%02X, ITEM::%s"(arg, commonData.items[arg2]);
                        break;
                    case 0x05:
                        auto arg = nextByte();
                        auto arg2 = nextByte();
                        writeFormatted!"\tEBTEXT_CHECK_IF_CHARACTER_HAS_ITEM $%02X, ITEM::%s"(arg, commonData.items[arg2]);
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
                        writeFormatted!"\tEBTEXT_GET_BUY_PRICE_OF_ITEM ITEM::%s"(commonData.items[arg]);
                        break;
                    case 0x0B:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_GET_SELL_PRICE_OF_ITEM ITEM::%s"(commonData.items[arg]);
                        break;
                    case 0x0C:
                        auto arg = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1D_0C $%04X"(arg);
                        break;
                    case 0x0D:
                        auto who = nextByte();
                        auto what = nextByte();
                        auto what2 = nextByte();
                        writeFormatted!"\tEBTEXT_CHARACTER_HAS_AILMENT $%02X, STATUS_GROUP::%s, $%02X"(who, commonData.statusGroups[what - 1], what2);
                        break;
                    case 0x0E:
                        auto who = nextByte();
                        auto what = nextByte();
                        writeFormatted!"\tEBTEXT_GIVE_ITEM_TO_CHARACTER_B $%02X, ITEM::%s"(who, commonData.items[what]);
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
                        writeFormatted!"\tEBTEXT_PLAY_MUSIC $%02X, MUSIC::%s"(arg, commonData.musicTracks[arg2]);
                        break;
                    case 0x01:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_UNKNOWN_CC_1F_01 $%02X"(arg);
                        break;
                    case 0x02:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_PLAY_SOUND SFX::%s"(commonData.sfx[arg]);
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
                        writeFormatted!"\tEBTEXT_ADD_PARTY_MEMBER PARTY_MEMBER::%s"(commonData.partyMembers[arg]);
                        break;
                    case 0x12:
                        auto arg = nextByte();
                        writeFormatted!"\tEBTEXT_REMOVE_PARTY_MEMBER PARTY_MEMBER::%s"(commonData.partyMembers[arg]);
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
                        writeFormatted!"\tEBTEXT_GENERATE_ACTIVE_SPRITE OVERWORLD_SPRITE::%s, EVENT_SCRIPT::%s, $%02X"(commonData.sprites[arg], commonData.movements[arg2], arg3);
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
                        writeFormatted!"\tEBTEXT_CREATE_ENTITY $%04X, EVENT_SCRIPT::%s, $%02X"(arg, commonData.movements[arg2], arg3);
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
                        writeFormatted!"\tEBTEXT_DELETE_GENERATED_SPRITE OVERWORLD_SPRITE::%s, $%02X"(commonData.sprites[arg], arg2);
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
                        writeFormatted!"\tEBTEXT_TRIGGER_BATTLE ENEMY_GROUP::%s"(commonData.enemyGroups[arg]);
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
                    case 0x60:
                        writeLine("\t.BYTE $1F, $60");
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
                        writeFormatted!"\tEBTEXT_SCREEN_RELOAD_PTR %s"(label(arg, true));
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
                        writeFormatted!"\tEBTEXT_ACTIVATE_HOTSPOT $%02X, $%02X, %s"(arg, arg2, label(arg3, true));
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
                            dests ~= label(nextByte() + (nextByte()<<8) + (nextByte()<<16) + (nextByte()<<24), true);
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
                        writeFormatted!"\tEBTEXT_SET_TPT_MOVEMENT_CODE $%04X, EVENT_SCRIPT::%s"(arg, commonData.movements[arg2]);
                        break;
                    case 0xF2:
                        auto arg = nextByte() + (nextByte()<<8);
                        auto arg2 = nextByte() + (nextByte()<<8);
                        writeFormatted!"\tEBTEXT_SET_SPRITE_MOVEMENT_CODE OVERWORLD_SPRITE::%s, EVENT_SCRIPT::%s"(commonData.sprites[arg], commonData.movements[arg2]);
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
