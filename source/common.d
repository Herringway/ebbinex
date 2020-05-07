module common;

import std.array;

import usa;
import jpn;

enum Build {
    unknown,
    jpn,
    usa
}
auto getDumpEntries(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: return jpnData.entries;
        case Build.usa: return usaData.entries;
        case Build.unknown: assert(0);
    }
}
auto getTextTable(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: return jpnData.table;
        case Build.usa: return usaData.table;
        case Build.unknown: assert(0);
    }
}
auto getStaffTextTable(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: return jpnData.staffTable;
        case Build.usa: return usaData.staffTable;
        case Build.unknown: assert(0);
    }
}
auto getRenameLabels(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: return jpnData.renameLabels;
        case Build.usa: return usaData.renameLabels;
        case Build.unknown: assert(0);
    }
}
auto getForcedTextLabels(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: return jpnData.forceTextLabels;
        case Build.usa: return usaData.forceTextLabels;
        case Build.unknown: assert(0);
    }
}
auto getCompressedStrings(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: assert(0);
        case Build.usa: return usaData.compressed;
        case Build.unknown: assert(0);
    }
}
auto supportsCompressedText(const Build build) @safe pure {
    final switch (build) {
        case Build.jpn: return false;
        case Build.usa: return true;
        case Build.unknown: assert(0);
    }
}

immutable string[] musicTracks = import("music.txt").split("\n");
immutable string[] movements = import("movements.txt").split("\n");
immutable string[] sprites = import("sprites.txt").split("\n");
immutable string[] items = import("items.txt").split("\n");
immutable string[] partyMembers = import("party.txt").split("\n");
immutable string[] eventFlags = import("eventflags.txt").split("\n");
immutable string[] windows = import("windows.txt").split("\n");
immutable string[] statusGroups = import("statusgroups.txt").split("\n");
immutable string[] sfx = import("sfx.txt").split("\n");
immutable string[] directions = [
    "UP",
    "UP_RIGHT",
    "RIGHT",
    "DOWN_RIGHT",
    "DOWN",
    "DOWN_LEFT",
    "LEFT",
    "UP_LEFT"
];
immutable string[] genders = [
    "NULL",
    "MALE",
    "FEMALE",
    "NEUTRAL"
];
immutable string[] enemyTypes = [
    "NORMAL",
    "INSECT",
    "METAL"
];

immutable string[] itemFlags = [
    "NESS_CAN_USE",
    "PAULA_CAN_USE",
    "JEFF_CAN_USE",
    "POO_CAN_USE",
    "TRANSFORM",
    "CANNOT_GIVE",
    "UNKNOWN",
    "CONSUMED_ON_USE"
];
