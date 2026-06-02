const std = @import("std");
const circuitry = @import("circuitry");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();
    const command = args.next() orelse return usage(init.io);
    const file = args.next() orelse return usage(init.io);

    var graph = try circuitry.loadFile(allocator, init.io, file);

    if (std.mem.eql(u8, command, "check")) {
        defer graph.deinit();
        try validateOrPrint(allocator, init.io, &graph);
        try writeStdout(init.io, "ok\n");
        return;
    }
    if (std.mem.eql(u8, command, "inspect")) {
        defer graph.deinit();
        try validateOrPrint(allocator, init.io, &graph);
        const text = try circuitry.inspect.render(allocator, &graph);
        defer allocator.free(text);
        try writeStdout(init.io, text);
        return;
    }
    if (std.mem.eql(u8, command, "resolve")) {
        var resolved = circuitry.resolve(allocator, init.io, graph, .{}) catch |err| {
            // resolve consumes graph on both success and error.
            try printError(init.io, err);
            std.process.exit(1);
        };
        defer resolved.deinit();
        const text = try circuitry.inspect.render(allocator, &resolved.graph);
        defer allocator.free(text);
        try writeStdout(init.io, text);
        return;
    }
    graph.deinit();
    return usage(init.io);
}

fn validateOrPrint(allocator: std.mem.Allocator, io: std.Io, graph: *const circuitry.Graph) !void {
    var diagnostics: circuitry.diagnostic.List = .empty;
    defer {
        circuitry.diagnostic.deinitList(allocator, diagnostics.items);
        diagnostics.deinit(allocator);
    }
    try circuitry.collectDiagnostics(allocator, graph, &diagnostics);
    if (diagnostics.items.len == 0) return;
    for (diagnostics.items) |d| try printDiagnostic(io, d);
    std.process.exit(1);
}

fn printDiagnostic(io: std.Io, d: circuitry.Diagnostic) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    try writer.interface.print("{s} {s}: {s}\n", .{ d.code, d.path, d.message });
    try writer.interface.flush();
}

fn printError(io: std.Io, err: anyerror) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    try writer.interface.print("error: {s}\n", .{@errorName(err)});
    try writer.interface.flush();
}

fn usage(io: std.Io) !void {
    try writeStderr(io, "usage: circuitry-zig <check|inspect|resolve> <graph.circuitry.yaml>\n");
    std.process.exit(1);
}

fn writeStdout(io: std.Io, bytes: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

fn writeStderr(io: std.Io, bytes: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}
