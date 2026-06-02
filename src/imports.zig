const std = @import("std");
const graph_mod = @import("graph.zig");
const val = @import("value.zig");

pub const Resolver = *const fn (allocator: std.mem.Allocator, specifier: []const u8, from_dir: []const u8) anyerror![]u8;

pub const Import = struct {
    alias: []const u8,
    specifier: []const u8,
};

pub fn specifier(spec: *const val.Value) ?[]const u8 {
    if (spec.* == .string) return spec.string;
    if (spec.* == .mapping) {
        const path = val.objectGet(spec, "path") orelse return null;
        if (path.* == .string) return path.string;
    }
    return null;
}

pub fn count(graph: *const graph_mod.Graph) usize {
    const imports = graph.imports() orelse return 0;
    return if (imports.* == .mapping) imports.mapping.count() else 0;
}

pub fn resolvePath(allocator: std.mem.Allocator, spec: []const u8, from_dir: []const u8, resolver: ?Resolver) ![]u8 {
    const raw = if (resolver) |custom| try custom(allocator, spec, from_dir) else try defaultResolve(allocator, spec, from_dir);
    errdefer allocator.free(raw);
    return raw;
}

pub fn defaultResolve(allocator: std.mem.Allocator, spec: []const u8, from_dir: []const u8) ![]u8 {
    if (hasUriScheme(spec) and !std.fs.path.isAbsolute(spec)) return error.UnsupportedImportScheme;
    if (std.fs.path.isAbsolute(spec)) return allocator.dupe(u8, spec);
    return std.fs.path.join(allocator, &.{ from_dir, spec });
}

fn hasUriScheme(spec: []const u8) bool {
    const colon = std.mem.indexOfScalar(u8, spec, ':') orelse return false;
    if (colon == 0) return false;
    return std.mem.indexOfAny(u8, spec[0..colon], "/\\") == null;
}
