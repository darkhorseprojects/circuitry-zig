const std = @import("std");

pub const Address = struct {
    raw: []const u8,
    module: ?[]const u8,
    resource: []const u8,
    field_path: []const []const u8,

    pub fn deinit(self: Address, allocator: std.mem.Allocator) void {
        allocator.free(self.raw);
        if (self.module) |m| allocator.free(m);
        allocator.free(self.resource);
        for (self.field_path) |p| allocator.free(p);
        allocator.free(self.field_path);
    }
};

pub fn parse(allocator: std.mem.Allocator, raw: []const u8, aliases: []const []const u8) !Address {
    if (raw.len == 0) return error.InvalidAddress;
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(allocator);
    var it = std.mem.splitScalar(u8, raw, '.');
    while (it.next()) |part| {
        if (part.len == 0) return error.InvalidAddress;
        try parts.append(allocator, part);
    }
    const first = parts.items[0];
    if (contains(aliases, first)) {
        if (parts.items.len < 2) return error.InvalidAddress;
        return .{
            .raw = try allocator.dupe(u8, raw),
            .module = try allocator.dupe(u8, first),
            .resource = try allocator.dupe(u8, parts.items[1]),
            .field_path = try dupeParts(allocator, parts.items[2..]),
        };
    }
    return .{
        .raw = try allocator.dupe(u8, raw),
        .module = null,
        .resource = try allocator.dupe(u8, first),
        .field_path = try dupeParts(allocator, parts.items[1..]),
    };
}

pub fn validIdentifier(id: []const u8) bool {
    if (id.len == 0) return false;
    if (!(std.ascii.isAlphabetic(id[0]) or id[0] == '_')) return false;
    for (id[1..]) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '-')) return false;
    return true;
}

fn contains(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item, needle)) return true;
    return false;
}

fn dupeParts(allocator: std.mem.Allocator, parts: []const []const u8) ![]const []const u8 {
    var out = try allocator.alloc([]const u8, parts.len);
    var initialized: usize = 0;
    errdefer {
        for (out[0..initialized]) |part| allocator.free(part);
        allocator.free(out);
    }
    for (parts, 0..) |part, i| {
        out[i] = try allocator.dupe(u8, part);
        initialized += 1;
    }
    return out;
}

test "parse local and module addresses" {
    const allocator = std.testing.allocator;
    var a = try parse(allocator, "assistant.answer", &.{});
    defer a.deinit(allocator);
    try std.testing.expectEqualStrings("assistant", a.resource);
    var b = try parse(allocator, "stock.user_turn", &.{"stock"});
    defer b.deinit(allocator);
    try std.testing.expectEqualStrings("stock", b.module.?);
}
