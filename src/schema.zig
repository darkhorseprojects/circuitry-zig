const std = @import("std");
const addr = @import("address.zig");
const val = @import("value.zig");

pub fn validate(schema: *const val.Value) bool {
    switch (schema.*) {
        .string => |s| return isScalar(s),
        .mapping => |*map| {
            var it = map.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (!addr.validIdentifier(key)) return false;
                if (isWrapper(key) and map.count() == 1) {
                    if (std.mem.eql(u8, key, "object")) {
                        if (entry.value_ptr.* != .mapping) return false;
                        var fields = entry.value_ptr.mapping.iterator();
                        while (fields.next()) |field| {
                            if (!addr.validIdentifier(field.key_ptr.*)) return false;
                            if (!validate(field.value_ptr)) return false;
                        }
                    } else if (!validate(entry.value_ptr)) return false;
                } else if (!validate(entry.value_ptr)) return false;
            }
            return true;
        },
        else => return false,
    }
}

pub fn validateValue(schema: *const val.Value, value: *const val.Value) bool {
    switch (schema.*) {
        .string => |name| return validateScalar(name, value),
        .mapping => |*map| {
            if (map.count() == 1) {
                var it = map.iterator();
                if (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    if (std.mem.eql(u8, key, "optional")) return value.* == .null_val or validateValue(entry.value_ptr, value);
                    if (std.mem.eql(u8, key, "list")) {
                        if (value.* != .sequence) return false;
                        for (value.sequence) |*item| if (!validateValue(entry.value_ptr, item)) return false;
                        return true;
                    }
                    if (std.mem.eql(u8, key, "object")) {
                        if (value.* != .mapping or entry.value_ptr.* != .mapping) return false;
                        var fields = entry.value_ptr.mapping.iterator();
                        while (fields.next()) |field| {
                            const child = val.objectGet(value, field.key_ptr.*) orelse return false;
                            if (!validateValue(field.value_ptr, child)) return false;
                        }
                        return true;
                    }
                }
            }
            if (value.* != .mapping) return false;
            var fields = map.iterator();
            while (fields.next()) |field| {
                const child = val.objectGet(value, field.key_ptr.*) orelse return false;
                if (!validateValue(field.value_ptr, child)) return false;
            }
            return true;
        },
        else => return false,
    }
}

fn validateScalar(name: []const u8, value: *const val.Value) bool {
    if (std.mem.eql(u8, name, "any")) return true;
    if (std.mem.eql(u8, name, "string")) return value.* == .string;
    if (std.mem.eql(u8, name, "number")) return value.* == .integer or value.* == .float;
    if (std.mem.eql(u8, name, "integer")) return value.* == .integer;
    if (std.mem.eql(u8, name, "boolean")) return value.* == .boolean;
    if (std.mem.eql(u8, name, "null")) return value.* == .null_val;
    return false;
}

fn isScalar(s: []const u8) bool {
    inline for (.{ "string", "number", "integer", "boolean", "null", "any" }) |name| if (std.mem.eql(u8, s, name)) return true;
    return false;
}

fn isWrapper(s: []const u8) bool {
    inline for (.{ "list", "object", "optional" }) |name| if (std.mem.eql(u8, s, name)) return true;
    return false;
}
