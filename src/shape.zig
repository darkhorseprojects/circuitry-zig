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

const ValueBinding = struct {
    local: ?[]const u8,
    value: []const u8,
    type_label: ?[]const u8,

    fn deinit(self: *ValueBinding, allocator: std.mem.Allocator) void {
        if (self.local) |local| allocator.free(local);
        allocator.free(self.value);
        if (self.type_label) |label| allocator.free(label);
    }
};

const UseEntry = struct {
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
    values: [][]const u8,
    uses: [][]const u8,

    fn deinit(self: *SystemDiagnostic) void {
        self.allocator.free(self.kind);
        self.allocator.free(self.message);
        value.freeStrings(self.allocator, self.values);
        value.freeStrings(self.allocator, self.uses);
    }
};

const SystemView = struct {
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
    system: NormalizedDoc,

    pub fn deinit(self: *Confirmation) void {
        self.card.deinit();
        value.freeStrings(self.allocator, self.problems);
        value.freeStrings(self.allocator, self.cautions);
        value.freeStrings(self.allocator, self.asks);
        self.system.deinit();
    }
};

pub const Direction = enum { takes, gives };

pub const NormalizedValue = struct {
    name: []const u8,
    type_label: ?[]const u8,
    direction: Direction,
};

pub const NormalizedBinding = struct {
    local: ?[]const u8,
    value: []const u8,
    type_label: ?[]const u8,
};

pub const NormalizedPart = struct {
    name: []const u8,
    shape: ?[]const u8,
    model: ?[]const u8,
    instructions: ?[]const u8,
    takes: []NormalizedBinding,
    gives: []NormalizedBinding,
};

pub const NormalizedDoc = struct {
    allocator: std.mem.Allocator,
    version: []const u8,
    name: []const u8,
    about: ?[]const u8,
    takes: []NormalizedValue,
    gives: []NormalizedValue,
    parts: []NormalizedPart,
    diagnostics: []SystemDiagnostic,

    pub fn deinit(self: *NormalizedDoc) void {
        self.allocator.free(self.version);
        self.allocator.free(self.name);
        if (self.about) |about| self.allocator.free(about);
        freeNormalizedValues(self.allocator, self.takes);
        freeNormalizedValues(self.allocator, self.gives);
        for (self.parts) |*part| freeNormalizedPart(self.allocator, part);
        self.allocator.free(self.parts);
        for (self.diagnostics) |*diagnostic| diagnostic.deinit();
        self.allocator.free(self.diagnostics);
    }
};

pub const MaterializedBinding = struct {
    part_name: []const u8,
    side: Direction,
    local: ?[]const u8,
    value: []const u8,
    type_label: ?[]const u8,
};

pub const Materializer = struct {
    context: *anyopaque,
    doc: *const fn (context: *anyopaque, doc: *const NormalizedDoc) anyerror!void,
    value: *const fn (context: *anyopaque, value_fact: NormalizedValue) anyerror!void,
    part: *const fn (context: *anyopaque, part_fact: *const NormalizedPart) anyerror!void,
    binding: *const fn (context: *anyopaque, binding_fact: MaterializedBinding) anyerror!void,
    diagnostic: *const fn (context: *anyopaque, diagnostic_fact: SystemDiagnostic) anyerror!void,
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

fn systemView(allocator: std.mem.Allocator, shape: *const Shape) !SystemView {
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
    var system = try normalize(allocator, shape);
    errdefer system.deinit();

    var problems: std.ArrayList([]const u8) = .empty;
    var cautions: std.ArrayList([]const u8) = .empty;
    errdefer {
        freeList(allocator, &problems);
        freeList(allocator, &cautions);
    }

    const version_node = value.get(&shape.root, "circuitry");
    if (version_node == null or !value.isCircuitryVersion(version_node.?)) {
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

    const asks = try dupeNormalizedValueNames(allocator, system.takes);
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

pub fn normalize(allocator: std.mem.Allocator, shape: *const Shape) !NormalizedDoc {
    var c = try card(allocator, shape);
    defer c.deinit();
    var system = try systemView(allocator, shape);
    defer system.deinit();

    const version_node = value.get(&shape.root, "circuitry");
    const version_text = if (version_node) |node| value.string(node) orelse version.circuitry else version.circuitry;

    const takes = try cloneNormalizedValues(allocator, system.takes, .takes);
    errdefer freeNormalizedValues(allocator, takes);
    const gives = try cloneNormalizedValues(allocator, system.gives, .gives);
    errdefer freeNormalizedValues(allocator, gives);
    const parts = try cloneNormalizedParts(allocator, system.uses);
    errdefer {
        for (parts) |*part| freeNormalizedPart(allocator, part);
        allocator.free(parts);
    }
    const diagnostics_copy = try cloneDiagnostics(allocator, system.diagnostics);
    errdefer {
        for (diagnostics_copy) |*diagnostic| diagnostic.deinit();
        allocator.free(diagnostics_copy);
    }

    return .{
        .allocator = allocator,
        .version = try allocator.dupe(u8, version_text),
        .name = try allocator.dupe(u8, c.name),
        .about = if (c.about) |about| try allocator.dupe(u8, about) else null,
        .takes = takes,
        .gives = gives,
        .parts = parts,
        .diagnostics = diagnostics_copy,
    };
}

pub fn stableDocId(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return std.fmt.allocPrint(allocator, "doc_{s}", .{hex[0..24]});
}

pub fn renderNormalized(allocator: std.mem.Allocator, shape: *const Shape) ![]u8 {
    var doc = try normalize(allocator, shape);
    defer doc.deinit();
    return renderNormalizedDoc(allocator, &doc);
}

pub fn renderNormalizedDoc(allocator: std.mem.Allocator, doc: *const NormalizedDoc) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try appendDocMaterial(allocator, &out, doc);
    try out.append(allocator, '\n');
    return out.toOwnedSlice(allocator);
}

pub fn renderNormalizedPart(allocator: std.mem.Allocator, shape: *const Shape, part_name: []const u8) ![]u8 {
    var doc = try normalize(allocator, shape);
    defer doc.deinit();
    return renderNormalizedPartDoc(allocator, &doc, part_name);
}

pub fn renderNormalizedPartDoc(allocator: std.mem.Allocator, doc: *const NormalizedDoc, part_name: []const u8) ![]u8 {
    const part = findNormalizedPart(doc, part_name) orelse return error.NormalizedPartNotFound;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.append(allocator, '{');
    var first = true;
    if (doc.about) |about| try appendStringField(allocator, &out, &first, "about", about);
    try appendFieldName(allocator, &out, &first, "part");
    try appendPartMaterial(allocator, &out, part);
    try appendStringField(allocator, &out, &first, "shape", doc.name);
    try appendStringField(allocator, &out, &first, "version", doc.version);
    try out.append(allocator, '}');
    try out.append(allocator, '\n');
    return out.toOwnedSlice(allocator);
}

pub fn materialize(normalized: *const NormalizedDoc, visitor: Materializer) !void {
    try visitor.doc(visitor.context, normalized);
    for (normalized.takes) |item| try visitor.value(visitor.context, item);
    for (normalized.gives) |item| try visitor.value(visitor.context, item);
    for (normalized.parts) |part| {
        try visitor.part(visitor.context, &part);
        for (part.takes) |binding| try visitor.binding(visitor.context, .{
            .part_name = part.name,
            .side = .takes,
            .local = binding.local,
            .value = binding.value,
            .type_label = binding.type_label,
        });
        for (part.gives) |binding| try visitor.binding(visitor.context, .{
            .part_name = part.name,
            .side = .gives,
            .local = binding.local,
            .value = binding.value,
            .type_label = binding.type_label,
        });
    }
    for (normalized.diagnostics) |diagnostic| try visitor.diagnostic(visitor.context, diagnostic);
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

fn appendDocMaterial(allocator: std.mem.Allocator, out: *std.ArrayList(u8), doc: *const NormalizedDoc) !void {
    try out.append(allocator, '{');
    var first = true;
    if (doc.about) |about| try appendStringField(allocator, out, &first, "about", about);
    try appendFieldName(allocator, out, &first, "diagnostics");
    try out.append(allocator, '[');
    for (doc.diagnostics, 0..) |diagnostic, i| {
        if (i != 0) try out.append(allocator, ',');
        try appendDiagnosticMaterial(allocator, out, diagnostic);
    }
    try out.append(allocator, ']');
    try appendFieldName(allocator, out, &first, "gives");
    try appendValuesMaterial(allocator, out, doc.gives);
    try appendStringField(allocator, out, &first, "name", doc.name);
    try appendFieldName(allocator, out, &first, "parts");
    try out.append(allocator, '[');
    for (doc.parts, 0..) |part, i| {
        if (i != 0) try out.append(allocator, ',');
        try appendPartMaterial(allocator, out, &part);
    }
    try out.append(allocator, ']');
    try appendFieldName(allocator, out, &first, "takes");
    try appendValuesMaterial(allocator, out, doc.takes);
    try appendStringField(allocator, out, &first, "version", doc.version);
    try out.append(allocator, '}');
}

fn appendValuesMaterial(allocator: std.mem.Allocator, out: *std.ArrayList(u8), values: []const NormalizedValue) !void {
    try out.append(allocator, '[');
    for (values, 0..) |item, i| {
        if (i != 0) try out.append(allocator, ',');
        try out.append(allocator, '{');
        var first = true;
        try appendStringField(allocator, out, &first, "direction", @tagName(item.direction));
        try appendStringField(allocator, out, &first, "name", item.name);
        if (item.type_label) |label| try appendStringField(allocator, out, &first, "type", label);
        try out.append(allocator, '}');
    }
    try out.append(allocator, ']');
}

fn appendPartMaterial(allocator: std.mem.Allocator, out: *std.ArrayList(u8), part: *const NormalizedPart) !void {
    try out.append(allocator, '{');
    var first = true;
    try appendFieldName(allocator, out, &first, "gives");
    try appendBindingsMaterial(allocator, out, part.gives);
    if (part.instructions) |instructions| try appendStringField(allocator, out, &first, "instructions", instructions);
    if (part.model) |model| try appendStringField(allocator, out, &first, "model", model);
    try appendStringField(allocator, out, &first, "name", part.name);
    if (part.shape) |shape_ref| try appendStringField(allocator, out, &first, "shape", shape_ref);
    try appendFieldName(allocator, out, &first, "takes");
    try appendBindingsMaterial(allocator, out, part.takes);
    try out.append(allocator, '}');
}

fn appendBindingsMaterial(allocator: std.mem.Allocator, out: *std.ArrayList(u8), bindings: []const NormalizedBinding) !void {
    try out.append(allocator, '[');
    for (bindings, 0..) |binding, i| {
        if (i != 0) try out.append(allocator, ',');
        try out.append(allocator, '{');
        var first = true;
        if (binding.local) |local| try appendStringField(allocator, out, &first, "local", local);
        if (binding.type_label) |label| try appendStringField(allocator, out, &first, "type", label);
        try appendStringField(allocator, out, &first, "value", binding.value);
        try out.append(allocator, '}');
    }
    try out.append(allocator, ']');
}

fn appendDiagnosticMaterial(allocator: std.mem.Allocator, out: *std.ArrayList(u8), diagnostic: SystemDiagnostic) !void {
    try out.append(allocator, '{');
    var first = true;
    try appendStringField(allocator, out, &first, "kind", diagnostic.kind);
    try appendStringField(allocator, out, &first, "message", diagnostic.message);
    try appendFieldName(allocator, out, &first, "uses");
    try appendStringArray(allocator, out, diagnostic.uses);
    try appendFieldName(allocator, out, &first, "values");
    try appendStringArray(allocator, out, diagnostic.values);
    try out.append(allocator, '}');
}

fn appendStringArray(allocator: std.mem.Allocator, out: *std.ArrayList(u8), items: []const []const u8) !void {
    try out.append(allocator, '[');
    for (items, 0..) |item, i| {
        if (i != 0) try out.append(allocator, ',');
        try appendJsonString(allocator, out, item);
    }
    try out.append(allocator, ']');
}

fn appendStringField(allocator: std.mem.Allocator, out: *std.ArrayList(u8), first: *bool, key: []const u8, string: []const u8) !void {
    try appendFieldName(allocator, out, first, key);
    try appendJsonString(allocator, out, string);
}

fn appendFieldName(allocator: std.mem.Allocator, out: *std.ArrayList(u8), first: *bool, key: []const u8) !void {
    if (first.*) first.* = false else try out.append(allocator, ',');
    try appendJsonString(allocator, out, key);
    try out.append(allocator, ':');
}

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), string: []const u8) !void {
    try out.append(allocator, '"');
    for (string) |c| switch (c) {
        '"' => try out.appendSlice(allocator, "\\\""),
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\r' => try out.appendSlice(allocator, "\\r"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        else => if (c < 0x20) try out.print(allocator, "\\u{x:0>4}", .{c}) else try out.append(allocator, c),
    };
    try out.append(allocator, '"');
}

fn findNormalizedPart(doc: *const NormalizedDoc, part_name: []const u8) ?*const NormalizedPart {
    for (doc.parts) |*part| if (std.mem.eql(u8, part.name, part_name)) return part;
    return null;
}

fn topLevelBindings(allocator: std.mem.Allocator, maybe: ?*const Value) ![]ValueBinding {
    var out: std.ArrayList(ValueBinding) = .empty;
    errdefer freeBindings(allocator, out.items);
    const v = maybe orelse return out.toOwnedSlice(allocator);
    switch (v.*) {
        .string => |s| if (s.len != 0) try appendTopLevelBinding(allocator, &out, s, null),
        .sequence => |items| for (items) |*item| if (item.* == .string) try appendTopLevelBinding(allocator, &out, item.string, null),
        .mapping => |*map| {
            var it = map.iterator();
            while (it.next()) |entry| try appendTopLevelBinding(allocator, &out, entry.key_ptr.*, bindingType(entry.value_ptr));
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
        if (bindingValue(entry.value_ptr)) |system_value| try out.append(allocator, try makeBinding(allocator, entry.key_ptr.*, system_value, localBindingType(entry.value_ptr)));
    }
    return out.toOwnedSlice(allocator);
}

fn cloneNormalizedValues(allocator: std.mem.Allocator, bindings: []const ValueBinding, direction: Direction) ![]NormalizedValue {
    var out: std.ArrayList(NormalizedValue) = .empty;
    errdefer freeNormalizedValues(allocator, out.items);
    for (bindings) |binding| try out.append(allocator, .{
        .name = try allocator.dupe(u8, binding.value),
        .type_label = if (binding.type_label) |label| try allocator.dupe(u8, label) else null,
        .direction = direction,
    });
    return out.toOwnedSlice(allocator);
}

fn cloneNormalizedBindings(allocator: std.mem.Allocator, bindings: []const ValueBinding) ![]NormalizedBinding {
    var out: std.ArrayList(NormalizedBinding) = .empty;
    errdefer freeNormalizedBindings(allocator, out.items);
    for (bindings) |binding| try out.append(allocator, .{
        .local = if (binding.local) |local| try allocator.dupe(u8, local) else null,
        .value = try allocator.dupe(u8, binding.value),
        .type_label = if (binding.type_label) |label| try allocator.dupe(u8, label) else null,
    });
    return out.toOwnedSlice(allocator);
}

fn cloneNormalizedParts(allocator: std.mem.Allocator, uses: []const UseEntry) ![]NormalizedPart {
    var out: std.ArrayList(NormalizedPart) = .empty;
    errdefer {
        for (out.items) |*part| freeNormalizedPart(allocator, part);
        out.deinit(allocator);
    }
    for (uses) |entry| {
        const takes = try cloneNormalizedBindings(allocator, entry.takes);
        errdefer freeNormalizedBindings(allocator, takes);
        const gives = try cloneNormalizedBindings(allocator, entry.gives);
        errdefer freeNormalizedBindings(allocator, gives);
        try out.append(allocator, .{
            .name = try allocator.dupe(u8, entry.name),
            .shape = if (entry.shape) |shape_ref| try allocator.dupe(u8, shape_ref) else null,
            .model = if (entry.model) |model| try allocator.dupe(u8, model) else null,
            .instructions = if (entry.instructions) |instructions| try allocator.dupe(u8, instructions) else null,
            .takes = takes,
            .gives = gives,
        });
    }
    return out.toOwnedSlice(allocator);
}

fn cloneDiagnostics(allocator: std.mem.Allocator, diagnostics_in: []const SystemDiagnostic) ![]SystemDiagnostic {
    var out: std.ArrayList(SystemDiagnostic) = .empty;
    errdefer {
        for (out.items) |*diagnostic| diagnostic.deinit();
        out.deinit(allocator);
    }
    for (diagnostics_in) |diagnostic| try out.append(allocator, .{
        .allocator = allocator,
        .kind = try allocator.dupe(u8, diagnostic.kind),
        .message = try allocator.dupe(u8, diagnostic.message),
        .values = try cloneStringSlice(allocator, diagnostic.values),
        .uses = try cloneStringSlice(allocator, diagnostic.uses),
    });
    return out.toOwnedSlice(allocator);
}

fn freeNormalizedValues(allocator: std.mem.Allocator, values: []NormalizedValue) void {
    for (values) |item| {
        allocator.free(item.name);
        if (item.type_label) |label| allocator.free(label);
    }
    allocator.free(values);
}

fn freeNormalizedBindings(allocator: std.mem.Allocator, bindings: []NormalizedBinding) void {
    for (bindings) |item| {
        if (item.local) |local| allocator.free(local);
        allocator.free(item.value);
        if (item.type_label) |label| allocator.free(label);
    }
    allocator.free(bindings);
}

fn freeNormalizedPart(allocator: std.mem.Allocator, part: *NormalizedPart) void {
    allocator.free(part.name);
    if (part.shape) |shape_ref| allocator.free(shape_ref);
    if (part.model) |model| allocator.free(model);
    if (part.instructions) |instructions| allocator.free(instructions);
    freeNormalizedBindings(allocator, part.takes);
    freeNormalizedBindings(allocator, part.gives);
}

fn collectDiagnostics(allocator: std.mem.Allocator, takes: []const ValueBinding, uses: []const UseEntry, gives: []const ValueBinding, out: *std.ArrayList(SystemDiagnostic)) !void {
    for (uses) |entry| {
        for (entry.takes) |binding| {
            if (!isInjected(takes, binding.value) and producerCount(uses, binding.value) == 0) {
                const msg = try std.fmt.allocPrint(allocator, "{s} takes unresolved value {s}.", .{ entry.name, binding.value });
                try appendDiagnostic(allocator, out, "unresolved-value", msg, &.{binding.value}, &.{entry.name});
            }
        }
    }
    for (gives) |binding| {
        if (!isInjected(takes, binding.value) and producerCount(uses, binding.value) == 0) {
            const msg = try std.fmt.allocPrint(allocator, "Top-level gives asks for unresolved value {s}.", .{binding.value});
            try appendDiagnostic(allocator, out, "unresolved-value", msg, &.{binding.value}, &.{});
        }
    }
    var duplicate_values: std.StringHashMap(void) = .init(allocator);
    defer duplicate_values.deinit();
    for (uses) |entry| {
        for (entry.gives) |binding| {
            if (producerCount(uses, binding.value) > 1 and !duplicate_values.contains(binding.value)) {
                try duplicate_values.put(binding.value, {});
                const producer_names = try producersForValue(allocator, uses, binding.value);
                defer value.freeStrings(allocator, producer_names);
                const joined = try joinStrings(allocator, producer_names, ", ");
                defer allocator.free(joined);
                const msg = try std.fmt.allocPrint(allocator, "{s} is produced by multiple uses entries: {s}.", .{ binding.value, joined });
                try appendDiagnostic(allocator, out, "duplicate-producer", msg, &.{binding.value}, producer_names);
            }
        }
    }
    if (try findCycle(allocator, uses)) |cycle| {
        defer value.freeStrings(allocator, cycle);
        const joined = try joinStrings(allocator, cycle, " -> ");
        defer allocator.free(joined);
        const msg = try std.fmt.allocPrint(allocator, "Cycle between uses entries: {s}.", .{joined});
        try appendDiagnostic(allocator, out, "cycle", msg, &.{}, cycle);
    }
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

fn producersForValue(allocator: std.mem.Allocator, uses: []const UseEntry, name: []const u8) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer freeList(allocator, &out);
    for (uses) |entry| if (produces(entry, name)) try out.append(allocator, try allocator.dupe(u8, entry.name));
    return out.toOwnedSlice(allocator);
}

fn findCycle(allocator: std.mem.Allocator, uses: []const UseEntry) !?[][]const u8 {
    const visiting = try allocator.alloc(bool, uses.len);
    defer allocator.free(visiting);
    const visited = try allocator.alloc(bool, uses.len);
    defer allocator.free(visited);
    @memset(visiting, false);
    @memset(visited, false);
    var stack: std.ArrayList(usize) = .empty;
    defer stack.deinit(allocator);

    for (uses, 0..) |_, index| {
        if (try visitCycle(allocator, uses, index, visiting, visited, &stack)) |cycle| return cycle;
    }
    return null;
}

fn visitCycle(allocator: std.mem.Allocator, uses: []const UseEntry, index: usize, visiting: []bool, visited: []bool, stack: *std.ArrayList(usize)) !?[][]const u8 {
    if (visiting[index]) {
        var start: usize = 0;
        while (start < stack.items.len and stack.items[start] != index) start += 1;
        var out: std.ArrayList([]const u8) = .empty;
        errdefer freeList(allocator, &out);
        for (stack.items[start..]) |item| try out.append(allocator, try allocator.dupe(u8, uses[item].name));
        try out.append(allocator, try allocator.dupe(u8, uses[index].name));
        return try out.toOwnedSlice(allocator);
    }
    if (visited[index]) return null;

    visiting[index] = true;
    try stack.append(allocator, index);
    for (uses[index].takes) |binding| {
        for (uses, 0..) |candidate, candidate_index| {
            if (candidate_index == index) continue;
            if (!produces(candidate, binding.value)) continue;
            if (try visitCycle(allocator, uses, candidate_index, visiting, visited, stack)) |cycle| return cycle;
        }
    }
    _ = stack.pop();
    visiting[index] = false;
    visited[index] = true;
    return null;
}

fn joinStrings(allocator: std.mem.Allocator, items: []const []const u8, separator: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (items, 0..) |item, index| {
        if (index != 0) try out.appendSlice(allocator, separator);
        try out.appendSlice(allocator, item);
    }
    return out.toOwnedSlice(allocator);
}

fn cloneStringSlice(allocator: std.mem.Allocator, items: []const []const u8) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer freeList(allocator, &out);
    for (items) |item| try out.append(allocator, try allocator.dupe(u8, item));
    return out.toOwnedSlice(allocator);
}

fn appendDiagnostic(allocator: std.mem.Allocator, out: *std.ArrayList(SystemDiagnostic), kind: []const u8, message: []const u8, values: []const []const u8, uses: []const []const u8) !void {
    errdefer allocator.free(message);
    const cloned_values = try cloneStringSlice(allocator, values);
    errdefer value.freeStrings(allocator, cloned_values);
    const cloned_uses = try cloneStringSlice(allocator, uses);
    errdefer value.freeStrings(allocator, cloned_uses);
    try out.append(allocator, .{
        .allocator = allocator,
        .kind = try allocator.dupe(u8, kind),
        .message = message,
        .values = cloned_values,
        .uses = cloned_uses,
    });
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

fn localBindingType(v: *const Value) ?[]const u8 {
    if (v.* != .mapping) return null;
    const t = value.get(v, "type") orelse return null;
    return if (t.* == .string) t.string else null;
}

fn bindingValue(v: *const Value) ?[]const u8 {
    if (v.* == .string and isValueName(v.string)) return v.string;
    if (v.* == .mapping) {
        const ref = value.get(v, "value") orelse return null;
        return if (ref.* == .string and isValueName(ref.string)) ref.string else null;
    }
    return null;
}

fn appendTopLevelBinding(allocator: std.mem.Allocator, out: *std.ArrayList(ValueBinding), raw_name: []const u8, type_label: ?[]const u8) !void {
    const system_value = try ensureValueName(allocator, raw_name);
    defer allocator.free(system_value);
    try out.append(allocator, try makeBinding(allocator, null, system_value, type_label));
}

fn makeBinding(allocator: std.mem.Allocator, local: ?[]const u8, system_value: []const u8, type_label: ?[]const u8) !ValueBinding {
    return .{
        .local = if (local) |name| try allocator.dupe(u8, name) else null,
        .value = try allocator.dupe(u8, system_value),
        .type_label = if (type_label) |label| try allocator.dupe(u8, label) else null,
    };
}

fn ensureValueName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (isValueName(name)) return try allocator.dupe(u8, name);
    const local = try localName(allocator, name);
    defer allocator.free(local);
    return std.fmt.allocPrint(allocator, "${s}", .{local});
}

fn localName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var previous_was_separator = false;
    for (name) |byte| {
        const normalized = switch (byte) {
            'A'...'Z' => byte + 32,
            'a'...'z', '0'...'9', '_', '.', '-' => byte,
            '$', '@' => continue,
            else => '_',
        };
        if (normalized == '_') {
            if (out.items.len == 0 or previous_was_separator) continue;
            previous_was_separator = true;
        } else {
            previous_was_separator = false;
        }
        try out.append(allocator, normalized);
    }
    while (out.items.len != 0 and out.items[out.items.len - 1] == '_') _ = out.pop();
    if (out.items.len == 0) try out.appendSlice(allocator, "value");
    return out.toOwnedSlice(allocator);
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

fn dupeNormalizedValueNames(allocator: std.mem.Allocator, items: []const NormalizedValue) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer freeList(allocator, &out);
    for (items) |item| try out.append(allocator, try allocator.dupe(u8, item.name));
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
    if (s.len <= 1 or s[0] != marker) return false;
    for (s[1..]) |byte| switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '_', '.', '-' => {},
        else => return false,
    };
    return true;
}
