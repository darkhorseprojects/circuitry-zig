const std = @import("std");
const serde = @import("serde");

pub const Value = serde.yaml.Value;
pub const Mapping = serde.yaml.Mapping;

pub fn get(value: *const Value, key: []const u8) ?*const Value {
    if (value.* != .mapping) return null;
    return value.mapping.getPtr(key);
}

pub fn string(value: *const Value) ?[]const u8 {
    return if (value.* == .string) value.string else null;
}

pub fn isCircuitry06(value: *const Value) bool {
    switch (value.*) {
        .string => |s| return std.mem.eql(u8, s, "0.6"),
        .float => |f| return f == 0.6,
        .integer => return false,
        else => return false,
    }
}

pub fn names(allocator: std.mem.Allocator, value: ?*const Value) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(allocator);
    const v = value orelse return out.toOwnedSlice(allocator);
    switch (v.*) {
        .string => |s| if (s.len != 0) try out.append(allocator, try allocator.dupe(u8, s)),
        .sequence => |items| {
            for (items) |*item| if (item.* == .string) try out.append(allocator, try allocator.dupe(u8, item.string));
        },
        .mapping => |*map| {
            var it = map.iterator();
            while (it.next()) |entry| try out.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
        },
        else => {},
    }
    return out.toOwnedSlice(allocator);
}

pub fn actionNames(allocator: std.mem.Allocator, value: ?*const Value) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(allocator);
    const v = value orelse return out.toOwnedSlice(allocator);
    switch (v.*) {
        .string => |s| if (std.mem.trim(u8, s, " \t\r\n").len != 0) try out.append(allocator, try allocator.dupe(u8, "action")),
        .sequence => |items| {
            for (items, 0..) |_, i| {
                const label = try std.fmt.allocPrint(allocator, "{d}", .{i + 1});
                try out.append(allocator, label);
            }
        },
        .mapping => |*map| {
            var it = map.iterator();
            while (it.next()) |entry| try out.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
        },
        else => {},
    }
    return out.toOwnedSlice(allocator);
}

pub fn empty(value: ?*const Value) bool {
    const v = value orelse return true;
    switch (v.*) {
        .null_val => return true,
        .string => |s| return std.mem.trim(u8, s, " \t\r\n").len == 0,
        .sequence => |items| return items.len == 0,
        .mapping => |*map| return map.count() == 0,
        else => return false,
    }
}

pub fn freeStrings(allocator: std.mem.Allocator, items: [][]const u8) void {
    for (items) |item| allocator.free(item);
    allocator.free(items);
}
