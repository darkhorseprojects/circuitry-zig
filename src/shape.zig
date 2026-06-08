const std = @import("std");
const serde = @import("serde");
const value = @import("value.zig");

pub const Value = value.Value;

pub const Shape = struct {
    arena: std.heap.ArenaAllocator,
    root: Value,

    pub fn deinit(self: *Shape) void {
        self.arena.deinit();
    }
};

pub const ActionCard = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    about: ?[]const u8,
    takes: [][]const u8,
    does: [][]const u8,
    gives: [][]const u8,

    pub fn deinit(self: *ActionCard) void {
        self.allocator.free(self.name);
        if (self.about) |a| self.allocator.free(a);
        value.freeStrings(self.allocator, self.takes);
        value.freeStrings(self.allocator, self.does);
        value.freeStrings(self.allocator, self.gives);
    }
};

pub const Confirmation = struct {
    allocator: std.mem.Allocator,
    ready: bool,
    card: ActionCard,
    problems: [][]const u8,
    cautions: [][]const u8,
    asks: [][]const u8,

    pub fn deinit(self: *Confirmation) void {
        self.card.deinit();
        value.freeStrings(self.allocator, self.problems);
        value.freeStrings(self.allocator, self.cautions);
        value.freeStrings(self.allocator, self.asks);
    }
};

const native = [_][]const u8{ "circuitry", "name", "about", "takes", "does", "gives" };
const old = [_][]const u8{ "nodes", "edges", "ports", "graph", "resources", "imports", "exports", "tools", "tool", "models", "model", "agents", "agent", "sessions", "session", "memory", "schema", "schemas", "meta", "extra" };

pub fn loadText(allocator: std.mem.Allocator, text: []const u8) !Shape {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const arena_allocator = arena.allocator();
    const root = try serde.yaml.parse(arena_allocator, text);
    return .{ .arena = arena, .root = root };
}

pub fn loadFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !Shape {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const arena_allocator = arena.allocator();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, arena_allocator, .limited(16 * 1024 * 1024));
    const root = try serde.yaml.parse(arena_allocator, bytes);
    return .{ .arena = arena, .root = root };
}

pub fn card(allocator: std.mem.Allocator, shape: *const Shape) !ActionCard {
    if (shape.root != .mapping) return error.NotCircuitryShape;
    const name_v = value.get(&shape.root, "name");
    const about_v = value.get(&shape.root, "about");
    const name = if (name_v) |v| value.string(v) orelse "untitled" else "untitled";
    const about = if (about_v) |v| value.string(v) else null;
    return .{
        .allocator = allocator,
        .name = try allocator.dupe(u8, name),
        .about = if (about) |a| try allocator.dupe(u8, a) else null,
        .takes = try value.names(allocator, value.get(&shape.root, "takes")),
        .does = try value.actionNames(allocator, value.get(&shape.root, "does")),
        .gives = try value.names(allocator, value.get(&shape.root, "gives")),
    };
}

pub fn confirm(allocator: std.mem.Allocator, shape: *const Shape) !Confirmation {
    var c = try card(allocator, shape);
    errdefer c.deinit();
    var problems: std.ArrayList([]const u8) = .empty;
    var cautions: std.ArrayList([]const u8) = .empty;
    errdefer {
        freeList(allocator, &problems);
        freeList(allocator, &cautions);
    }

    const version = value.get(&shape.root, "circuitry");
    if (version == null or !value.isCircuitry06(version.?)) try problems.append(allocator, try allocator.dupe(u8, "Use `circuitry: 0.6`."));
    if (value.empty(value.get(&shape.root, "does"))) try problems.append(allocator, try allocator.dupe(u8, "Say what action should be taken."));
    if (value.empty(value.get(&shape.root, "gives"))) try cautions.append(allocator, try allocator.dupe(u8, "Name what the action gives back."));

    if (shape.root == .mapping) {
        var it = shape.root.mapping.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            if (contains(&old, key)) {
                const msg = try std.fmt.allocPrint(allocator, "`{s}` looks like old framework language. Fold it into takes/does/gives.", .{key});
                try cautions.append(allocator, msg);
            }
        }
    }

    const asks = try dupeStringList(allocator, c.takes);
    return .{
        .allocator = allocator,
        .ready = problems.items.len == 0,
        .card = c,
        .problems = try problems.toOwnedSlice(allocator),
        .cautions = try cautions.toOwnedSlice(allocator),
        .asks = asks,
    };
}

pub fn nonNativeFields(allocator: std.mem.Allocator, shape: *const Shape) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer freeList(allocator, &out);
    if (shape.root != .mapping) return out.toOwnedSlice(allocator);
    var it = shape.root.mapping.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (!contains(&native, key)) try out.append(allocator, try allocator.dupe(u8, key));
    }
    return out.toOwnedSlice(allocator);
}

pub fn renderCard(allocator: std.mem.Allocator, c: *const ActionCard) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, c.name);
    try out.append(allocator, '\n');
    if (c.about) |a| { try out.appendSlice(allocator, a); try out.append(allocator, '\n'); }
    try renderNames(allocator, &out, "takes", c.takes);
    try renderNames(allocator, &out, "does", c.does);
    try renderNames(allocator, &out, "gives", c.gives);
    return out.toOwnedSlice(allocator);
}

fn renderNames(allocator: std.mem.Allocator, out: *std.ArrayList(u8), label: []const u8, items: [][]const u8) !void {
    try out.print(allocator, "{s}: ", .{label});
    if (items.len == 0) try out.appendSlice(allocator, "-") else {
        for (items, 0..) |item, i| { if (i != 0) try out.appendSlice(allocator, ", "); try out.appendSlice(allocator, item); }
    }
    try out.append(allocator, '\n');
}

fn contains(comptime haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |item| if (std.mem.eql(u8, item, needle)) return true;
    return false;
}

fn dupeStringList(allocator: std.mem.Allocator, items: [][]const u8) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(allocator);
    for (items) |item| try out.append(allocator, try allocator.dupe(u8, item));
    return out.toOwnedSlice(allocator);
}

fn freeList(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
}
