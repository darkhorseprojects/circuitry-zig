const std = @import("std");

pub fn isCircuitryPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".circuitry.yaml") or std.mem.endsWith(u8, path, ".circuitry.yml");
}
