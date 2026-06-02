const std = @import("std");
const graph_mod = @import("graph.zig");
const res = @import("resource.zig");
const exp = @import("export.zig");
const addr = @import("address.zig");
const validate_mod = @import("validate.zig");
const resolve_mod = @import("resolve.zig");
const val = @import("value.zig");

pub const Step = struct {
    id: []u8,
    kind: []u8,
    dependencies: [][]u8,

    pub fn deinit(self: Step, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.kind);
        validate_mod.freeStrings(allocator, self.dependencies);
    }
};

pub const ResolvedStep = struct {
    module: ?[]u8,
    id: []u8,
    kind: []u8,
    dependencies: [][]u8,

    pub fn deinit(self: ResolvedStep, allocator: std.mem.Allocator) void {
        if (self.module) |m| allocator.free(m);
        allocator.free(self.id);
        allocator.free(self.kind);
        validate_mod.freeStrings(allocator, self.dependencies);
    }
};

pub fn requiredInputs(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, export_name: []const u8) ![][]u8 {
    const ids = try runSet(allocator, graph, export_name);
    defer validate_mod.freeStrings(allocator, ids);
    var out = std.ArrayList([]u8).empty;
    errdefer freeStringList(allocator, &out);
    for (ids) |id| {
        const rv = graph_mod.resource(graph, id) orelse continue;
        var names: std.ArrayList([]u8) = .empty;
        defer freeStringList(allocator, &names);
        try res.appendRuntimeInputs(allocator, &names, rv);
        for (names.items) |name| if (!contains(out.items, name)) try out.append(allocator, try allocator.dupe(u8, name));
    }
    return out.toOwnedSlice(allocator);
}

pub fn planExport(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, export_name: []const u8) ![]Step {
    const order = try topoSort(allocator, graph, export_name);
    defer validate_mod.freeStrings(allocator, order);
    var out = std.ArrayList(Step).empty;
    errdefer {
        for (out.items) |step| step.deinit(allocator);
        out.deinit(allocator);
    }
    for (order) |id| {
        const rv = graph_mod.resource(graph, id) orelse continue;
        var deps: std.ArrayList([]u8) = .empty;
        errdefer freeStringList(allocator, &deps);
        try res.appendResourceDependencies(allocator, &deps, rv);
        try out.append(allocator, .{ .id = try allocator.dupe(u8, id), .kind = try allocator.dupe(u8, res.kindName(rv) orelse "unknown"), .dependencies = try deps.toOwnedSlice(allocator) });
    }
    return out.toOwnedSlice(allocator);
}

pub fn runSet(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, export_name: []const u8) ![][]u8 {
    const exports = graph.exports() orelse return allocator.alloc([]u8, 0);
    const spec = exp.get(exports, export_name) orelse return error.ExportNotFound;
    const aliases = try validate_mod.importAliases(allocator, graph);
    defer validate_mod.freeStrings(allocator, aliases);
    var target = try addr.parse(allocator, spec.run, aliases);
    defer target.deinit(allocator);
    if (target.module != null) return allocator.alloc([]u8, 0);
    var seen = std.StringHashMap(bool).init(allocator);
    defer seen.deinit();
    var out = std.ArrayList([]u8).empty;
    errdefer freeStringList(allocator, &out);
    try visit(allocator, graph, aliases, &seen, &out, target.resource);
    return out.toOwnedSlice(allocator);
}

pub fn planResolvedExport(allocator: std.mem.Allocator, resolved: *const resolve_mod.ResolvedGraph, export_name: []const u8) ![]ResolvedStep {
    const exports = resolved.graph.exports() orelse return allocator.alloc(ResolvedStep, 0);
    const spec = exp.get(exports, export_name) orelse return error.ExportNotFound;
    const aliases = try validate_mod.importAliases(allocator, &resolved.graph);
    defer validate_mod.freeStrings(allocator, aliases);
    var target = try addr.parse(allocator, spec.run, aliases);
    defer target.deinit(allocator);

    var seen = std.StringHashMap(bool).init(allocator);
    defer {
        freeMapKeys(allocator, &seen);
        seen.deinit();
    }
    var visiting = std.StringHashMap(bool).init(allocator);
    defer {
        freeMapKeys(allocator, &visiting);
        visiting.deinit();
    }
    var out = std.ArrayList(ResolvedStep).empty;
    errdefer freeResolvedSteps(allocator, &out);
    try resolvedVisit(allocator, resolved, null, &resolved.graph, target, &visiting, &seen, &out);
    return out.toOwnedSlice(allocator);
}

pub fn freeResolvedPlan(allocator: std.mem.Allocator, steps: []ResolvedStep) void {
    for (steps) |step| step.deinit(allocator);
    allocator.free(steps);
}

pub fn topoSort(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, export_name: []const u8) ![][]u8 {
    const selected = try runSet(allocator, graph, export_name);
    defer validate_mod.freeStrings(allocator, selected);
    var permanent = std.StringHashMap(bool).init(allocator);
    defer permanent.deinit();
    var temporary = std.StringHashMap(bool).init(allocator);
    defer temporary.deinit();
    const aliases = try validate_mod.importAliases(allocator, graph);
    defer validate_mod.freeStrings(allocator, aliases);
    var out = std.ArrayList([]u8).empty;
    errdefer freeStringList(allocator, &out);
    for (selected) |id| try topoVisit(allocator, graph, aliases, selected, &temporary, &permanent, &out, id);
    return out.toOwnedSlice(allocator);
}

fn visit(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, aliases: []const []const u8, seen: *std.StringHashMap(bool), out: *std.ArrayList([]u8), id: []const u8) !void {
    if (seen.contains(id)) return;
    try seen.put(id, true);
    try out.append(allocator, try allocator.dupe(u8, id));
    const rv = graph_mod.resource(graph, id) orelse return;
    var deps: std.ArrayList([]u8) = .empty;
    defer freeStringList(allocator, &deps);
    try res.appendResourceDependencies(allocator, &deps, rv);
    for (deps.items) |dep| {
        var parsed = addr.parse(allocator, dep, aliases) catch continue;
        defer parsed.deinit(allocator);
        if (parsed.module == null) try visit(allocator, graph, aliases, seen, out, parsed.resource);
    }
}

fn topoVisit(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, aliases: []const []const u8, selected: []const []u8, temporary: *std.StringHashMap(bool), permanent: *std.StringHashMap(bool), out: *std.ArrayList([]u8), id: []const u8) !void {
    if (!contains(selected, id) or permanent.contains(id)) return;
    if (temporary.contains(id)) return error.DependencyCycle;
    try temporary.put(id, true);
    const rv = graph_mod.resource(graph, id) orelse return;
    var deps: std.ArrayList([]u8) = .empty;
    defer freeStringList(allocator, &deps);
    try res.appendResourceDependencies(allocator, &deps, rv);
    for (deps.items) |dep| {
        var parsed = addr.parse(allocator, dep, aliases) catch continue;
        defer parsed.deinit(allocator);
        if (parsed.module == null) try topoVisit(allocator, graph, aliases, selected, temporary, permanent, out, parsed.resource);
    }
    _ = temporary.remove(id);
    try permanent.put(id, true);
    try out.append(allocator, try allocator.dupe(u8, id));
}

fn resolvedVisit(
    allocator: std.mem.Allocator,
    resolved: *const resolve_mod.ResolvedGraph,
    current_module: ?[]const u8,
    current_graph: *const graph_mod.Graph,
    target: addr.Address,
    visiting: *std.StringHashMap(bool),
    seen: *std.StringHashMap(bool),
    out: *std.ArrayList(ResolvedStep),
) !void {
    var target_graph = current_graph;
    var target_module = current_module;
    if (target.module) |module_alias| {
        if (current_module != null) return error.NestedModulePlanningUnsupported;
        const module = resolved.module(module_alias) orelse return error.ImportNotResolved;
        target_graph = &module.graph;
        target_module = module_alias;
    }

    const key = try resolvedKey(allocator, target_module, target.resource);
    defer allocator.free(key);
    if (seen.contains(key)) return;
    if (visiting.contains(key)) return error.DependencyCycle;
    try visiting.put(try allocator.dupe(u8, key), true);
    errdefer removeMapKey(allocator, visiting, key);

    const rv = graph_mod.resource(target_graph, target.resource) orelse return error.ResourceNotFound;
    const aliases = try validate_mod.importAliases(allocator, target_graph);
    defer validate_mod.freeStrings(allocator, aliases);
    var deps: std.ArrayList([]u8) = .empty;
    defer freeStringList(allocator, &deps);
    try res.appendResourceDependencies(allocator, &deps, rv);
    for (deps.items) |dep| {
        var parsed = try addr.parse(allocator, dep, aliases);
        defer parsed.deinit(allocator);
        if (target_module != null and parsed.module != null) return error.NestedModulePlanningUnsupported;
        try resolvedVisit(allocator, resolved, target_module, target_graph, parsed, visiting, seen, out);
    }

    removeMapKey(allocator, visiting, key);
    try seen.put(try allocator.dupe(u8, key), true);
    var step_deps: std.ArrayList([]u8) = .empty;
    errdefer freeStringList(allocator, &step_deps);
    for (deps.items) |dep| try step_deps.append(allocator, try qualifyDependencyName(allocator, target_module, dep));
    try out.append(allocator, .{
        .module = if (target_module) |m| try allocator.dupe(u8, m) else null,
        .id = try allocator.dupe(u8, target.resource),
        .kind = try allocator.dupe(u8, res.kindName(rv) orelse "unknown"),
        .dependencies = try step_deps.toOwnedSlice(allocator),
    });
}

fn resolvedKey(allocator: std.mem.Allocator, module: ?[]const u8, id: []const u8) ![]u8 {
    return if (module) |m| std.fmt.allocPrint(allocator, "{s}.{s}", .{ m, id }) else allocator.dupe(u8, id);
}

fn qualifyDependencyName(allocator: std.mem.Allocator, module: ?[]const u8, dep: []const u8) ![]u8 {
    if (module == null or std.mem.indexOfScalar(u8, dep, '.') != null) return allocator.dupe(u8, dep);
    return std.fmt.allocPrint(allocator, "{s}.{s}", .{ module.?, dep });
}

fn freeResolvedSteps(allocator: std.mem.Allocator, list: *std.ArrayList(ResolvedStep)) void {
    for (list.items) |step| step.deinit(allocator);
    list.deinit(allocator);
}

fn removeMapKey(allocator: std.mem.Allocator, map: *std.StringHashMap(bool), key: []const u8) void {
    if (map.fetchRemove(key)) |entry| allocator.free(entry.key);
}

fn freeMapKeys(allocator: std.mem.Allocator, map: *std.StringHashMap(bool)) void {
    var it = map.keyIterator();
    while (it.next()) |key| allocator.free(key.*);
}

fn freeStringList(allocator: std.mem.Allocator, list: *std.ArrayList([]u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
}

fn contains(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item, needle)) return true;
    return false;
}
