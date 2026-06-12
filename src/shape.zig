const std = @import("std");
const serde = @import("serde");
const value = @import("value.zig");
const version = @import("version.zig");

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
    uses: [][]const u8,
    does: [][]const u8,
    gives: [][]const u8,

    pub fn deinit(self: *ActionCard) void {
        self.allocator.free(self.name);
        if (self.about) |a| self.allocator.free(a);
        value.freeStrings(self.allocator, self.takes);
        value.freeStrings(self.allocator, self.uses);
        value.freeStrings(self.allocator, self.does);
        value.freeStrings(self.allocator, self.gives);
    }
};

pub const ValueBinding = struct {
    local: ?[]const u8,
    value: []const u8,
    type_label: ?[]const u8,

    fn deinit(self: *ValueBinding, allocator: std.mem.Allocator) void {
        if (self.local) |local| allocator.free(local);
        allocator.free(self.value);
        if (self.type_label) |label| allocator.free(label);
    }
};

pub const UseEntry = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    shape: ?[]const u8,
    model: ?[]const u8,
    takes: []ValueBinding,
    gives: []ValueBinding,
    does: [][]const u8,
    instructions: ?[]const u8,

    fn deinit(self: *UseEntry) void {
        self.allocator.free(self.name);
        if (self.shape) |shape_ref| self.allocator.free(shape_ref);
        if (self.model) |model| self.allocator.free(model);
        freeBindings(self.allocator, self.takes);
        freeBindings(self.allocator, self.gives);
        value.freeStrings(self.allocator, self.does);
        if (self.instructions) |instructions| self.allocator.free(instructions);
    }
};

pub const SystemDiagnostic = struct {
    allocator: std.mem.Allocator,
    kind: []const u8,
    message: []const u8,

    fn deinit(self: *SystemDiagnostic) void {
        self.allocator.free(self.kind);
        self.allocator.free(self.message);
    }
};

pub const SystemView = struct {
    allocator: std.mem.Allocator,
    takes: []ValueBinding,
    uses: []UseEntry,
    gives: []ValueBinding,
    value_refs: [][]const u8,
    diagnostics: []SystemDiagnostic,

    pub fn deinit(self: *SystemView) void {
        freeBindings(self.allocator, self.takes);
        for (self.uses) |*entry| entry.deinit();
        self.allocator.free(self.uses);
        freeBindings(self.allocator, self.gives);
        value.freeStrings(self.allocator, self.value_refs);
        for (self.diagnostics) |*diagnostic| diagnostic.deinit();
        self.allocator.free(self.diagnostics);
    }
};

pub const Confirmation = struct {
    allocator: std.mem.Allocator,
    ready: bool,
    card: ActionCard,
    problems: [][]const u8,
    cautions: [][]const u8,
    asks: [][]const u8,
    system: SystemView,

    pub fn deinit(self: *Confirmation) void {
        self.card.deinit();
        value.freeStrings(self.allocator, self.problems);
        value.freeStrings(self.allocator, self.cautions);
        value.freeStrings(self.allocator, self.asks);
        self.system.deinit();
    }
};

const native = [_][]const u8{ "circuitry", "name", "about", "takes", "uses", "does", "gives" };
const old = [_][]const u8{ "nodes", "edges", "ports", "graph", "resources", "imports", "exports", "tools", "tool", "models", "agents", "agent", "sessions", "session", "memory", "schema", "schemas", "meta", "extra" };

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
        .uses = try value.actionNames(allocator, value.get(&shape.root, "uses")),
        .does = try value.actionNames(allocator, value.get(&shape.root, "does")),
        .gives = try value.names(allocator, value.get(&shape.root, "gives")),
    };
}

pub fn systemView(allocator: std.mem.Allocator, shape: *const Shape) !SystemView {
    const takes = try topLevelBindings(allocator, value.get(&shape.root, "takes"));
    errdefer freeBindings(allocator, takes);
    const uses = try useEntries(allocator, value.get(&shape.root, "uses"));
    errdefer {
        for (uses) |*entry| entry.deinit();
        allocator.free(uses);
    }
    const gives = try topLevelBindings(allocator, value.get(&shape.root, "gives"));
    errdefer freeBindings(allocator, gives);

    var value_refs_list: std.ArrayList([]const u8) = .empty;
    errdefer freeList(allocator, &value_refs_list);
    try discoverRefs(allocator, &shape.root, '$', &value_refs_list);

    var diagnostic_list: std.ArrayList(SystemDiagnostic) = .empty;
    errdefer {
        for (diagnostic_list.items) |*diagnostic| diagnostic.deinit();
        diagnostic_list.deinit(allocator);
    }
    try collectDiagnostics(allocator, takes, uses, gives, &diagnostic_list);

    return .{
        .allocator = allocator,
        .takes = takes,
        .uses = uses,
        .gives = gives,
        .value_refs = try value_refs_list.toOwnedSlice(allocator),
        .diagnostics = try diagnostic_list.toOwnedSlice(allocator),
    };
}

pub fn confirm(allocator: std.mem.Allocator, shape: *const Shape) !Confirmation {
    var c = try card(allocator, shape);
    errdefer c.deinit();
    var system = try systemView(allocator, shape);
    errdefer system.deinit();

    var problems: std.ArrayList([]const u8) = .empty;
    var cautions: std.ArrayList([]const u8) = .empty;
    errdefer {
        freeList(allocator, &problems);
        freeList(allocator, &cautions);
    }

    const version_node = value.get(&shape.root, "circuitry");
    if (version_node == null or !value.isCircuitry062(version_node.?)) {
        const msg = try std.fmt.allocPrint(allocator, "Use `circuitry: \"{s}\"`.", .{version.circuitry});
        try problems.append(allocator, msg);
    }
    if (value.empty(value.get(&shape.root, "does")) and value.empty(value.get(&shape.root, "uses"))) try problems.append(allocator, try allocator.dupe(u8, "Say what action should be taken with `does` or `uses`."));
    if (value.empty(value.get(&shape.root, "gives"))) try cautions.append(allocator, try allocator.dupe(u8, "Name what the action gives back."));

    if (shape.root == .mapping) {
        var it = shape.root.mapping.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            if (contains(&old, key)) {
                const msg = try std.fmt.allocPrint(allocator, "`{s}` looks like old framework language. Fold it into takes/uses/does/gives.", .{key});
                try cautions.append(allocator, msg);
            }
        }
    }

    for (system.diagnostics) |diagnostic| try problems.append(allocator, try allocator.dupe(u8, diagnostic.message));

    const asks = try dupeBindingValues(allocator, system.takes);
    return .{
        .allocator = allocator,
        .ready = problems.items.len == 0,
        .card = c,
        .problems = try problems.toOwnedSlice(allocator),
        .cautions = try cautions.toOwnedSlice(allocator),
        .asks = asks,
        .system = system,
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
    if (c.about) |a| {
        try out.appendSlice(allocator, a);
        try out.append(allocator, '\n');
    }
    try renderNames(allocator, &out, "takes", c.takes);
    try renderNames(allocator, &out, "uses", c.uses);
    try renderNames(allocator, &out, "does", c.does);
    try renderNames(allocator, &out, "gives", c.gives);
    return out.toOwnedSlice(allocator);
}

fn topLevelBindings(allocator: std.mem.Allocator, maybe: ?*const Value) ![]ValueBinding {
    var out: std.ArrayList(ValueBinding) = .empty;
    errdefer freeBindings(allocator, out.items);
    const v = maybe orelse return out.toOwnedSlice(allocator);
    switch (v.*) {
        .string => |s| if (s.len != 0) try out.append(allocator, try makeBinding(allocator, null, ensureValueName(allocator, s), null)),
        .sequence => |items| for (items) |*item| if (item.* == .string) try out.append(allocator, try makeBinding(allocator, null, ensureValueName(allocator, item.string), null)),
        .mapping => |*map| {
            var it = map.iterator();
            while (it.next()) |entry| try out.append(allocator, try makeBinding(allocator, null, ensureValueName(allocator, entry.key_ptr.*), bindingType(entry.value_ptr)));
        },
        else => {},
    }
    return out.toOwnedSlice(allocator);
}

fn useEntries(allocator: std.mem.Allocator, maybe: ?*const Value) ![]UseEntry {
    var out: std.ArrayList(UseEntry) = .empty;
    errdefer {
        for (out.items) |*entry| entry.deinit();
        out.deinit(allocator);
    }
    const v = maybe orelse return out.toOwnedSlice(allocator);
    if (v.* != .mapping) return out.toOwnedSlice(allocator);
    var it = v.mapping.iterator();
    while (it.next()) |entry| {
        const raw = entry.value_ptr;
        const takes = try localBindings(allocator, if (raw.* == .mapping) value.get(raw, "takes") else null);
        errdefer freeBindings(allocator, takes);
        const gives = try localBindings(allocator, if (raw.* == .mapping) value.get(raw, "gives") else null);
        errdefer freeBindings(allocator, gives);
        const does_value = if (raw.* == .mapping) value.get(raw, "does") else null;
        const does = try value.actionNames(allocator, does_value);
        errdefer value.freeStrings(allocator, does);
        const instructions = try instructionText(allocator, does_value);
        errdefer if (instructions) |text| allocator.free(text);
        const shape_ref = if (raw.* == .mapping) try stringDup(allocator, value.get(raw, "shape")) else null;
        errdefer if (shape_ref) |s| allocator.free(s);
        const model = if (raw.* == .mapping) try stringDup(allocator, value.get(raw, "model")) else null;
        errdefer if (model) |m| allocator.free(m);
        try out.append(allocator, .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, entry.key_ptr.*),
            .shape = shape_ref,
            .model = model,
            .takes = takes,
            .gives = gives,
            .does = does,
            .instructions = instructions,
        });
    }
    return out.toOwnedSlice(allocator);
}

fn localBindings(allocator: std.mem.Allocator, maybe: ?*const Value) ![]ValueBinding {
    var out: std.ArrayList(ValueBinding) = .empty;
    errdefer freeBindings(allocator, out.items);
    const v = maybe orelse return out.toOwnedSlice(allocator);
    if (v.* != .mapping) return out.toOwnedSlice(allocator);
    var it = v.mapping.iterator();
    while (it.next()) |entry| {
        if (bindingValue(entry.value_ptr)) |system_value| try out.append(allocator, try makeBinding(allocator, entry.key_ptr.*, system_value, null));
    }
    return out.toOwnedSlice(allocator);
}

fn collectDiagnostics(allocator: std.mem.Allocator, takes: []const ValueBinding, uses: []const UseEntry, gives: []const ValueBinding, out: *std.ArrayList(SystemDiagnostic)) !void {
    for (uses) |entry| {
        for (entry.takes) |binding| {
            if (!isInjected(takes, binding.value) and producerCount(uses, binding.value) == 0) {
                const msg = try std.fmt.allocPrint(allocator, "{s} takes unresolved value {s}.", .{ entry.name, binding.value });
                try appendDiagnostic(allocator, out, "unresolved-value", msg);
            }
        }
    }
    for (gives) |binding| {
        if (!isInjected(takes, binding.value) and producerCount(uses, binding.value) == 0) {
            const msg = try std.fmt.allocPrint(allocator, "Top-level gives asks for unresolved value {s}.", .{binding.value});
            try appendDiagnostic(allocator, out, "unresolved-value", msg);
        }
    }
    for (uses) |entry| {
        for (entry.gives) |binding| {
            if (producerCount(uses, binding.value) > 1) {
                const msg = try std.fmt.allocPrint(allocator, "{s} is produced by multiple uses entries.", .{binding.value});
                try appendDiagnostic(allocator, out, "duplicate-producer", msg);
                break;
            }
        }
    }
    if (hasCycle(uses)) try appendDiagnostic(allocator, out, "cycle", try allocator.dupe(u8, "Cycle between uses entries."));
}

fn hasCycle(uses: []const UseEntry) bool {
    for (uses) |a| for (a.takes) |take_a| for (uses) |b| {
        if (std.mem.eql(u8, a.name, b.name)) continue;
        if (!produces(b, take_a.value)) continue;
        for (b.takes) |take_b| if (produces(a, take_b.value)) return true;
    };
    return false;
}

fn produces(entry: UseEntry, name: []const u8) bool {
    for (entry.gives) |binding| if (std.mem.eql(u8, binding.value, name)) return true;
    return false;
}

fn producerCount(uses: []const UseEntry, name: []const u8) usize {
    var count: usize = 0;
    for (uses) |entry| {
        for (entry.gives) |binding| {
            if (std.mem.eql(u8, binding.value, name)) count += 1;
        }
    }
    return count;
}

fn isInjected(takes: []const ValueBinding, name: []const u8) bool {
    for (takes) |binding| if (std.mem.eql(u8, binding.value, name)) return true;
    return false;
}

fn appendDiagnostic(allocator: std.mem.Allocator, out: *std.ArrayList(SystemDiagnostic), kind: []const u8, message: []const u8) !void {
    errdefer allocator.free(message);
    try out.append(allocator, .{ .allocator = allocator, .kind = try allocator.dupe(u8, kind), .message = message });
}

fn discoverRefs(allocator: std.mem.Allocator, v: *const Value, marker: u8, out: *std.ArrayList([]const u8)) !void {
    switch (v.*) {
        .string => |s| if (isMarkedRef(s, marker) and !stringListContains(out.items, s)) try out.append(allocator, try allocator.dupe(u8, s)),
        .sequence => |items| for (items) |*item| try discoverRefs(allocator, item, marker, out),
        .mapping => |*map| {
            var it = map.iterator();
            while (it.next()) |entry| {
                if (isMarkedRef(entry.key_ptr.*, marker) and !stringListContains(out.items, entry.key_ptr.*)) try out.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
                try discoverRefs(allocator, entry.value_ptr, marker, out);
            }
        },
        else => {},
    }
}

fn renderNames(allocator: std.mem.Allocator, out: *std.ArrayList(u8), label: []const u8, items: [][]const u8) !void {
    try out.print(allocator, "{s}: ", .{label});
    if (items.len == 0) try out.appendSlice(allocator, "-") else {
        for (items, 0..) |item, i| {
            if (i != 0) try out.appendSlice(allocator, ", ");
            try out.appendSlice(allocator, item);
        }
    }
    try out.append(allocator, '\n');
}

fn bindingType(v: *const Value) ?[]const u8 {
    if (v.* == .string) return v.string;
    if (v.* == .mapping) {
        const t = value.get(v, "type") orelse return null;
        return if (t.* == .string) t.string else null;
    }
    return null;
}

fn bindingValue(v: *const Value) ?[]const u8 {
    if (v.* == .string and isValueName(v.string)) return v.string;
    if (v.* == .mapping) {
        const ref = value.get(v, "value") orelse return null;
        return if (ref.* == .string and isValueName(ref.string)) ref.string else null;
    }
    return null;
}

fn makeBinding(allocator: std.mem.Allocator, local: ?[]const u8, system_value: []const u8, type_label: ?[]const u8) !ValueBinding {
    return .{
        .local = if (local) |name| try allocator.dupe(u8, name) else null,
        .value = try allocator.dupe(u8, system_value),
        .type_label = if (type_label) |label| try allocator.dupe(u8, label) else null,
    };
}

fn ensureValueName(allocator: std.mem.Allocator, name: []const u8) []const u8 {
    _ = allocator;
    return if (isValueName(name)) name else name;
}

fn stringDup(allocator: std.mem.Allocator, maybe: ?*const Value) !?[]const u8 {
    const v = maybe orelse return null;
    const s = value.string(v) orelse return null;
    return try allocator.dupe(u8, s);
}

fn instructionText(allocator: std.mem.Allocator, maybe: ?*const Value) !?[]const u8 {
    const v = maybe orelse return null;
    if (v.* == .string) return try allocator.dupe(u8, v.string);
    if (v.* != .mapping) return null;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var it = v.mapping.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* != .string) continue;
        try out.appendSlice(allocator, entry.value_ptr.string);
        try out.append(allocator, '\n');
    }
    return try out.toOwnedSlice(allocator);
}

fn freeBindings(allocator: std.mem.Allocator, bindings: []ValueBinding) void {
    for (bindings) |*binding| binding.deinit(allocator);
    allocator.free(bindings);
}

fn contains(comptime haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |item| if (std.mem.eql(u8, item, needle)) return true;
    return false;
}

fn dupeBindingValues(allocator: std.mem.Allocator, items: []const ValueBinding) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer freeList(allocator, &out);
    for (items) |item| try out.append(allocator, try allocator.dupe(u8, item.value));
    return out.toOwnedSlice(allocator);
}

fn freeList(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
}

fn stringListContains(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item, needle)) return true;
    return false;
}

fn isValueName(s: []const u8) bool {
    return isMarkedRef(s, '$');
}
fn isMarkedRef(s: []const u8, marker: u8) bool {
    return s.len > 1 and s[0] == marker;
}
