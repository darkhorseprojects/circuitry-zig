const std = @import("std");

pub const Diagnostic = struct {
    code: []const u8,
    message: []const u8,
    path: []const u8,
};

pub const List = std.ArrayList(Diagnostic);

pub fn add(allocator: std.mem.Allocator, diagnostics: *List, code: []const u8, path: []const u8, comptime fmt: []const u8, args: anytype) !void {
    try diagnostics.append(allocator, .{
        .code = try allocator.dupe(u8, code),
        .path = try allocator.dupe(u8, path),
        .message = try std.fmt.allocPrint(allocator, fmt, args),
    });
}

pub fn deinitList(allocator: std.mem.Allocator, diagnostics: []const Diagnostic) void {
    for (diagnostics) |d| {
        allocator.free(d.code);
        allocator.free(d.message);
        allocator.free(d.path);
    }
}
