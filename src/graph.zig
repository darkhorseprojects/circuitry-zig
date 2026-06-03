const std = @import("std");
const serde = @import("serde");
const normalize = @import("normalize.zig");
const val = @import("value.zig");

pub const Value = val.Value;

pub const Graph = struct {
    arena: std.heap.ArenaAllocator,
    path: []u8,
    root: Value,

    pub fn deinit(self: *Graph) void {
        self.root.deinit(self.arena.allocator());
        self.arena.deinit();
    }

    pub fn resources(self: *const Graph) ?*const Value {
        return val.objectGet(&self.root, "resources");
    }

    pub fn exports(self: *const Graph) ?*const Value {
        return val.objectGet(&self.root, "exports");
    }

    pub fn imports(self: *const Graph) ?*const Value {
        return val.objectGet(&self.root, "imports");
    }
};

pub fn loadYamlFile(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !Graph {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(io, file_path, a, .limited(16 * 1024 * 1024));
    return .{ .arena = arena, .path = try canonicalPath(a, io, file_path), .root = try serde.yaml.parse(a, text) };
}

pub fn loadFile(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !Graph {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(io, file_path, a, .limited(16 * 1024 * 1024));
    const root = try serde.yaml.parse(a, text);
    var graph = Graph{ .arena = arena, .path = try canonicalPath(a, io, file_path), .root = root };
    try normalize.graph(&graph);
    return graph;
}

pub fn version(self: *const Graph) ?[]const u8 {
    const v = val.objectGet(&self.root, "circuitry") orelse return null;
    return val.string(v);
}

pub fn title(self: *const Graph) ?[]const u8 {
    const v = val.objectGet(&self.root, "title") orelse return null;
    return val.string(v);
}

pub fn resource(graph: *const Graph, id: []const u8) ?*const Value {
    const resources = graph.resources() orelse return null;
    return val.objectGet(resources, id);
}

fn canonicalPath(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().realPathFileAlloc(io, file_path, allocator);
}

test "graph module compiles" {
    _ = std.testing.allocator;
}
