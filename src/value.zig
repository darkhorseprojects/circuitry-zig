const std = @import("std");
const serde = @import("serde");

pub const Value = serde.yaml.Value;
pub const Mapping = serde.yaml.Mapping;

pub fn objectGet(value: *const Value, key: []const u8) ?*const Value {
    if (value.* != .mapping) return null;
    return value.mapping.getPtr(key);
}

pub fn objectGetMut(value: *Value, key: []const u8) ?*Value {
    if (value.* != .mapping) return null;
    return value.mapping.getPtr(key);
}

pub fn putOwned(object: *Value, allocator: std.mem.Allocator, key: []const u8, value: Value) !void {
    if (object.* != .mapping) return error.InvalidObject;
    const gop = try object.mapping.getOrPut(allocator, key);
    if (gop.found_existing) {
        allocator.free(key);
        gop.value_ptr.deinit(allocator);
        gop.value_ptr.* = value;
    } else {
        gop.key_ptr.* = key;
        gop.value_ptr.* = value;
    }
}

pub fn string(value: *const Value) ?[]const u8 {
    return if (value.* == .string) value.string else null;
}

pub fn boolValue(value: *const Value) ?bool {
    return if (value.* == .boolean) value.boolean else null;
}

pub fn isObject(value: *const Value) bool {
    return value.* == .mapping;
}

pub fn isArray(value: *const Value) bool {
    return value.* == .sequence;
}

pub fn writeJsonLike(allocator: std.mem.Allocator, value: *const Value) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try appendJsonLike(allocator, &out, value, 0);
    return out.toOwnedSlice(allocator);
}

fn appendJsonLike(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: *const Value, indent: usize) !void {
    switch (value.*) {
        .null_val => try out.appendSlice(allocator, "null"),
        .boolean => |b| try out.appendSlice(allocator, if (b) "true" else "false"),
        .integer => |i| try out.print(allocator, "{d}", .{i}),
        .float => |f| try out.print(allocator, "{d}", .{f}),
        .string => |s| {
            var aw = std.Io.Writer.Allocating.fromArrayList(allocator, out);
            defer out.* = aw.toArrayList();
            try std.json.Stringify.value(s, .{}, &aw.writer);
        },
        .sequence => |items| {
            try out.appendSlice(allocator, "[");
            for (items, 0..) |*item, i| {
                if (i != 0) try out.appendSlice(allocator, ", ");
                try appendJsonLike(allocator, out, item, indent + 2);
            }
            try out.appendSlice(allocator, "]");
        },
        .mapping => |*map| {
            try out.appendSlice(allocator, "{");
            var it = map.iterator();
            var i: usize = 0;
            while (it.next()) |entry| : (i += 1) {
                if (i != 0) try out.appendSlice(allocator, ",");
                try out.append(allocator, '\n');
                try appendSpaces(allocator, out, indent + 2);
                try out.print(allocator, "\"{s}\": ", .{entry.key_ptr.*});
                try appendJsonLike(allocator, out, entry.value_ptr, indent + 2);
            }
            if (i != 0) {
                try out.append(allocator, '\n');
                try appendSpaces(allocator, out, indent);
            }
            try out.appendSlice(allocator, "}");
        },
    }
}

fn appendSpaces(allocator: std.mem.Allocator, out: *std.ArrayList(u8), n: usize) !void {
    for (0..n) |_| try out.append(allocator, ' ');
}
