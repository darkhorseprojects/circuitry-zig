const std = @import("std");
const serde = @import("serde");
const normalize = @import("normalize.zig");
const val = @import("value.zig");

pub const Value = val.Value;

pub const Graph = struct {
    arena: std.heap.ArenaAllocator,
    path: []u8,
    root: Value,

    pub fn init(child_allocator: std.mem.Allocator) Graph {
        return .{ .arena = std.heap.ArenaAllocator.init(child_allocator), .path = &.{}, .root = .null_val };
    }

    pub fn allocator(self: *Graph) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn deinit(self: *Graph) void {
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
    var graph = Graph.init(allocator);
    errdefer graph.deinit();
    const a = graph.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(io, file_path, a, .limited(16 * 1024 * 1024));
    graph.path = try canonicalPath(a, io, file_path);
    graph.root = try serde.yaml.parse(a, text);
    return graph;
}

pub fn loadFile(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !Graph {
    var graph = Graph.init(allocator);
    errdefer graph.deinit();
    const a = graph.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(io, file_path, a, .limited(16 * 1024 * 1024));
    graph.path = try canonicalPath(a, io, file_path);
    graph.root = try serde.yaml.parse(a, text);
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
