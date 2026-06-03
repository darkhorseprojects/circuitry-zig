const std = @import("std");
const res = @import("resource.zig");
const val = @import("value.zig");

pub fn graph(graph_value: anytype) !void {
    const resources = val.objectGetMut(&graph_value.root, "resources") orelse return;
    if (resources.* != .mapping) return;
    var it = resources.mapping.iterator();
    while (it.next()) |entry| try resource(graph_value.allocator(), entry.value_ptr);
}

pub fn resource(allocator: std.mem.Allocator, resource_value: *val.Value) !void {
    const kind = res.kindName(resource_value) orelse return;
    const body = val.objectGetMut(resource_value, kind) orelse return;
    if (std.mem.eql(u8, kind, "text")) return normalizeStringSource(allocator, body, "value");
    if (std.mem.eql(u8, kind, "data")) return normalizeStringSource(allocator, body, "value");
    if (std.mem.eql(u8, kind, "file")) return normalizeStringSource(allocator, body, "path");
    if (std.mem.eql(u8, kind, "model")) return normalizeModel(allocator, body);
}

fn normalizeStringSource(allocator: std.mem.Allocator, body: *val.Value, field: []const u8) !void {
    if (body.* != .string) return;
    const text = body.string;
    var map: val.Mapping = .{};
    errdefer map.deinit(allocator);
    try map.put(allocator, try allocator.dupe(u8, field), .{ .string = try allocator.dupe(u8, text) });
    body.* = .{ .mapping = map };
}

fn normalizeModel(allocator: std.mem.Allocator, body: *val.Value) !void {
    if (body.* != .mapping) return;
    if (val.objectGetMut(body, "input")) |input| try flattenStringListValue(allocator, input);
    if (val.objectGetMut(body, "tools")) |tools| try flattenStringListValue(allocator, tools);
}

fn flattenStringListValue(allocator: std.mem.Allocator, value: *val.Value) !void {
    if (value.* != .sequence or !canFlattenStringList(value)) return;
    var out = std.ArrayList(val.Value).empty;
    errdefer {
        for (out.items) |*item| item.deinit(allocator);
        out.deinit(allocator);
    }
    try appendFlattened(allocator, &out, value);
    value.* = .{ .sequence = try out.toOwnedSlice(allocator) };
}

fn canFlattenStringList(value: *const val.Value) bool {
    if (value.* != .sequence) return false;
    for (value.sequence) |*item| {
        if (item.* == .sequence) {
            if (!canFlattenStringList(item)) return false;
        } else if (item.* != .string) return false;
    }
    return true;
}

fn appendFlattened(allocator: std.mem.Allocator, out: *std.ArrayList(val.Value), value: *const val.Value) !void {
    for (value.sequence) |*item| {
        if (item.* == .sequence) try appendFlattened(allocator, out, item) else try out.append(allocator, .{ .string = try allocator.dupe(u8, item.string) });
    }
}
