module common;

import std.array;

struct DumpDoc {
    DumpInfo[] dumpEntries;
    string[ubyte] textTable;
    string[ubyte] staffTextTable;
    string[ushort] flyoverTextTable;
    string[size_t] flyoverLabels;
    string[size_t][string] renameLabels;
    string[] compressedTextStrings;
    string defaultDumpPath = "bin";
    string romIdentifier;
    bool dontUseTextTable;
    bool multibyteFlyovers;
    Music music;
    bool supportsCompressedText() const @safe pure {
        return compressedTextStrings.length > 0;
    }
}

struct CommonData {
    string[] eventFlags;
    string[] items;
    string[] movements;
    string[] musicTracks;
    string[] partyMembers;
    string[] sfx;
    string[] sprites;
    string[] statusGroups;
    string[] windows;
    string[] directions;
    string[] genders;
    string[] enemyTypes;
    string[] itemFlags;
    string[] enemyGroups;
}

ubyte[] readFile(string filename) {
    import std.file : read;
    return cast(ubyte[])read(filename);
}

struct DumpInfo {
    string subdir;
    string name;
    ulong offset;
    ulong size;
    string extension = "bin";
    bool compressed;
}

struct Music {
    uint packPointerTable;
    uint songPointerTable;
    uint numPacks;
}

ushort readShort(const ubyte[] data) @safe pure {
    return (cast(const(ushort)[])data[0 .. 2])[0];
}

const(ubyte)[] getCompressedData(const ubyte[] data) @safe pure {
    ubyte commandbyte;
    ubyte commandID;
    ushort commandLength;
    size_t currentOffset;
    decompLoop: while(true) {
        commandbyte = data[currentOffset++];
        commandID = commandbyte >> 5;
        if (commandID == 7) { //Extend length of command
            commandID = (commandbyte & 0x1C) >> 2;
            if (commandID != 7) { //Double extend does not have a length
                commandLength = ((commandbyte & 3) << 8) + data[currentOffset++] + 1;
            }
        } else {
            commandLength = (commandbyte & 0x1F) + 1;
        }
        if ((commandID >= 4) && (commandID < 7)) { //Read buffer position
            currentOffset += 2;
        }
        switch(commandID) {
            case 0: //Following data is uncompressed
                currentOffset += commandLength;
                break; //copy uncompressed data directly into buffer
            case 1: //Fill range with following byte
                currentOffset++;
                break;
            case 2: //Fill range with following short
                currentOffset += 2;
                break;
            case 3: //Fill range with increasing byte, beginning with following value
                currentOffset++;
                break;
            case 4: //Copy from buffer
            case 5: //Copy from buffer, but with reversed bits
            case 6: //Copy from buffer, but with reversed bytes
                break;
            case 7: break decompLoop;
            default: assert(0);
        }
    }
    return data[0 .. currentOffset];
}
