const std = @import("std");
const circuitry = @import("circuitry");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();
    const command = args.next() orelse return usage(init.io);
    const target = args.next() orelse if (!std.mem.eql(u8, command, "help")) return usage(init.io) else "";

    if (std.mem.eql(u8, command, "read")) return read(init.io, allocator, target);
    if (std.mem.eql(u8, command, "confirm")) return confirm(init.io, allocator, target);
    if (std.mem.eql(u8, command, "asks")) return names(init.io, allocator, target, .takes);
    if (std.mem.eql(u8, command, "gives")) return names(init.io, allocator, target, .gives);
    if (std.mem.eql(u8, command, "library")) return library(init.io, allocator, target);
    return usage(init.io);
}

const Which = enum { takes, gives };

fn read(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    var shape = try circuitry.loadFile(io, allocator, path);
    defer shape.deinit();
    var c = try circuitry.card(allocator, &shape);
    defer c.deinit();
    const text = try circuitry.renderCard(allocator, &c);
    defer allocator.free(text);
    try stdout(io, text);
}

fn confirm(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    var shape = try circuitry.loadFile(io, allocator, path);
    defer shape.deinit();
    var result = try circuitry.confirm(allocator, &shape);
    defer result.deinit();
    const text = try circuitry.renderCard(allocator, &result.card);
    defer allocator.free(text);
    try stdout(io, text);
    try printList(io, "fix", result.problems);
    try printList(io, "notice", result.cautions);
    try printList(io, "Zinc should collect", result.asks);
    try stdout(io, if (result.ready) "\nready\n" else "\nnot ready\n");
    if (!result.ready) std.process.exit(1);
}

fn names(io: std.Io, allocator: std.mem.Allocator, path: []const u8, which: Which) !void {
    var shape = try circuitry.loadFile(io, allocator, path);
    defer shape.deinit();
    var c = try circuitry.card(allocator, &shape);
    defer c.deinit();
    const items = if (which == .takes) c.takes else c.gives;
    for (items) |item| { try stdout(io, item); try stdout(io, "\n"); }
}

fn library(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind == .file and circuitry.library.isCircuitryPath(entry.name)) {
            const path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
            defer allocator.free(path);
            var shape = try circuitry.loadFile(io, allocator, path);
            defer shape.deinit();
            var c = try circuitry.card(allocator, &shape);
            defer c.deinit();
            try stdout(io, path); try stdout(io, "\n  "); try stdout(io, c.name); try stdout(io, "\n");
        }
    }
}

fn printList(io: std.Io, title: []const u8, items: [][]const u8) !void {
    if (items.len == 0) return;
    try stdout(io, "\n"); try stdout(io, title); try stdout(io, ":\n");
    for (items) |item| { try stdout(io, "- "); try stdout(io, item); try stdout(io, "\n"); }
}

fn usage(io: std.Io) !void {
    try stderr(io, "usage: circuitry-zig <read|confirm|asks|gives|library> <file-or-dir>\n");
    std.process.exit(1);
}

fn stdout(io: std.Io, bytes: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

fn stderr(io: std.Io, bytes: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}
