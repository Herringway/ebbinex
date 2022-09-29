module common;

import std.array;

struct DumpDoc {
    uint[] forceTextLabels;
    DumpInfo[] dumpEntries;
    string[ubyte] textTable;
    string[ubyte] staffTextTable;
    string[ushort] flyoverTextTable;
    string[size_t] flyoverLabels;
    string[size_t] renameLabels;
    string[] compressedTextStrings;
    string defaultDumpPath = "bin";
    string romIdentifier;
    bool dontUseTextTable;
    bool multibyteFlyovers;
    bool d;
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