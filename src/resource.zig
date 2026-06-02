const std = @import("std");
const val = @import("value.zig");

pub const Kind = enum { text, data, file, model, run, unknown };

const metadata = [_][]const u8{ "label", "description" };

pub fn kindName(resource: *const val.Value) ?[]const u8 {
    if (resource.* != .mapping) return null;
    var found: ?[]const u8 = null;
    var it = resource.mapping.iterator();
    while (it.next()) |entry| {
        if (isMetadata(entry.key_ptr.*)) continue;
        if (found != null) return null;
        found = entry.key_ptr.*;
    }
    return found;
}

pub fn kind(resource: *const val.Value) Kind {
    const name = kindName(resource) orelse return .unknown;
    if (std.mem.eql(u8, name, "text")) return .text;
    if (std.mem.eql(u8, name, "data")) return .data;
    if (std.mem.eql(u8, name, "file")) return .file;
    if (std.mem.eql(u8, name, "model")) return .model;
    if (std.mem.eql(u8, name, "run")) return .run;
    return .unknown;
}

pub fn body(resource: *const val.Value) ?*const val.Value {
    const name = kindName(resource) orelse return null;
    return val.objectGet(resource, name);
}

pub fn dependencies(allocator: std.mem.Allocator, resource: *const val.Value) ![][]u8 {
    var out = std.ArrayList([]u8).empty;
    errdefer {
        for (out.items) |item| allocator.free(item);
        out.deinit(allocator);
    }
    switch (kind(resource)) {
        .model => {
            const model = body(resource) orelse return out.toOwnedSlice(allocator);
            const input = val.objectGet(model, "input") orelse return out.toOwnedSlice(allocator);
            try appendStringList(allocator, &out, input);
        },
        .run => {
            const run = body(resource) orelse return out.toOwnedSlice(allocator);
            const input = val.objectGet(run, "input") orelse return out.toOwnedSlice(allocator);
            if (input.* == .mapping) {
                var it = input.mapping.iterator();
                while (it.next()) |entry| if (entry.value_ptr.* == .string) try out.append(allocator, try allocator.dupe(u8, entry.value_ptr.string));
            }
        },
        else => {},
    }
    return out.toOwnedSlice(allocator);
}

pub fn runtimeInputName(raw: []const u8) ?[]const u8 {
    return if (raw.len > 1 and raw[0] == '$') raw[1..] else null;
}

pub fn isRuntimeInputRef(raw: []const u8) bool {
    return runtimeInputName(raw) != null;
}

pub fn appendResourceDependencies(allocator: std.mem.Allocator, out: *std.ArrayList([]u8), resource: *const val.Value) !void {
    const deps = try dependencies(allocator, resource);
    defer {
        for (deps) |dep| allocator.free(dep);
        allocator.free(deps);
    }
    for (deps) |dep| if (!isRuntimeInputRef(dep)) try out.append(allocator, try allocator.dupe(u8, dep));
}

pub fn appendRuntimeInputs(allocator: std.mem.Allocator, out: *std.ArrayList([]u8), resource: *const val.Value) !void {
    const deps = try dependencies(allocator, resource);
    defer {
        for (deps) |dep| allocator.free(dep);
        allocator.free(deps);
    }
    for (deps) |dep| if (runtimeInputName(dep)) |name| try out.append(allocator, try allocator.dupe(u8, name));
}

pub fn appendStringList(allocator: std.mem.Allocator, out: *std.ArrayList([]u8), value: *const val.Value) !void {
    if (value.* != .sequence) return error.InvalidList;
    for (value.sequence) |*item| {
        if (item.* == .sequence) try appendStringList(allocator, out, item)
        else if (item.* == .string) try out.append(allocator, try allocator.dupe(u8, item.string))
        else return error.InvalidList;
    }
}

fn isMetadata(key: []const u8) bool {
    for (metadata) |m| if (std.mem.eql(u8, key, m)) return true;
    return false;
}
