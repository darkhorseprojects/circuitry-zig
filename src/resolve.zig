const std = @import("std");
const graph_mod = @import("graph.zig");
const validate_mod = @import("validate.zig");
const res = @import("resource.zig");
const addr = @import("address.zig");
const exp = @import("export.zig");
const imports = @import("imports.zig");

pub const ImportResolver = imports.Resolver;

pub const Options = struct {
    import_resolver: ?ImportResolver = null,
};

pub const Module = struct {
    alias: []u8,
    path: []u8,
    graph: graph_mod.Graph,
    modules: []Module,

    pub fn deinit(self: *Module, allocator: std.mem.Allocator) void {
        allocator.free(self.alias);
        allocator.free(self.path);
        for (self.modules) |*module| module.deinit(allocator);
        allocator.free(self.modules);
        self.graph.deinit();
    }
};

pub const ResolvedGraph = struct {
    allocator: std.mem.Allocator,
    graph: graph_mod.Graph,
    modules: []Module,

    pub fn deinit(self: *ResolvedGraph) void {
        for (self.modules) |*child_module| child_module.deinit(self.allocator);
        self.allocator.free(self.modules);
        self.graph.deinit();
    }

    pub fn module(self: *const ResolvedGraph, alias: []const u8) ?*const Module {
        for (self.modules) |*child_module| if (std.mem.eql(u8, child_module.alias, alias)) return child_module;
        return null;
    }
};

pub fn resolve(allocator: std.mem.Allocator, io: std.Io, graph: graph_mod.Graph, options: Options) !ResolvedGraph {
    var owned = graph;
    errdefer owned.deinit();
    try validate_mod.validate(allocator, &owned);

    var seen = std.StringHashMap(bool).init(allocator);
    defer seen.deinit();
    try seen.put(owned.path, true);

    const modules = try resolveImports(allocator, io, &owned, options, &seen);
    errdefer {
        for (modules) |*module| module.deinit(allocator);
        allocator.free(modules);
    }
    try validateModuleReferences(allocator, &owned, modules);
    return .{ .allocator = allocator, .graph = owned, .modules = modules };
}

fn resolveImports(allocator: std.mem.Allocator, io: std.Io, graph: *const graph_mod.Graph, options: Options, seen: *std.StringHashMap(bool)) ![]Module {
    const import_map = graph.imports() orelse return allocator.alloc(Module, 0);
    if (import_map.* != .mapping) return allocator.alloc(Module, 0);
    const from_dir = std.fs.path.dirname(graph.path) orelse ".";
    var out = std.ArrayList(Module).empty;
    errdefer {
        for (out.items) |*module| module.deinit(allocator);
        out.deinit(allocator);
    }
    var it = import_map.mapping.iterator();
    while (it.next()) |entry| {
        const spec = imports.specifier(entry.value_ptr) orelse continue;
        const raw_import_path = try imports.resolvePath(allocator, spec, from_dir, options.import_resolver);
        defer allocator.free(raw_import_path);
        const real_import_path = try std.Io.Dir.cwd().realPathFileAlloc(io, raw_import_path, allocator);
        defer allocator.free(real_import_path);
        const import_path = try allocator.dupe(u8, real_import_path);
        errdefer allocator.free(import_path);
        if (seen.contains(import_path)) return error.ImportCycle;
        try seen.put(import_path, true);
        var child = try graph_mod.loadFile(allocator, io, import_path);
        errdefer child.deinit();
        try validate_mod.validate(allocator, &child);
        const child_modules = try resolveImports(allocator, io, &child, options, seen);
        errdefer {
            for (child_modules) |*module| module.deinit(allocator);
            allocator.free(child_modules);
        }
        try validateModuleReferences(allocator, &child, child_modules);
        try out.append(allocator, .{
            .alias = try allocator.dupe(u8, entry.key_ptr.*),
            .path = import_path,
            .graph = child,
            .modules = child_modules,
        });
        _ = seen.remove(import_path);
    }
    return out.toOwnedSlice(allocator);
}

fn validateModuleReferences(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, modules: []const Module) !void {
    const aliases = try validate_mod.importAliases(allocator, graph);
    defer validate_mod.freeStrings(allocator, aliases);
    if (graph.exports()) |exports| if (exports.* == .mapping) {
        var it = exports.mapping.iterator();
        while (it.next()) |entry| {
            const spec = exp.get(exports, entry.key_ptr.*) orelse continue;
            try validateAddressModuleReference(allocator, modules, aliases, spec.run);
            if (spec.returns) |returns| if (returns.* == .mapping) {
                var rit = returns.mapping.iterator();
                while (rit.next()) |ret| if (ret.value_ptr.* == .string) try validateAddressModuleReference(allocator, modules, aliases, ret.value_ptr.string);
            };
        }
    };
    const resources = graph.resources() orelse return;
    if (resources.* != .mapping) return;
    var rit = resources.mapping.iterator();
    while (rit.next()) |entry| {
        const deps = try res.dependencies(allocator, entry.value_ptr);
        defer validate_mod.freeStrings(allocator, deps);
        for (deps) |dep| try validateAddressModuleReference(allocator, modules, aliases, dep);
    }
}

fn validateAddressModuleReference(allocator: std.mem.Allocator, modules: []const Module, aliases: []const []const u8, raw: []const u8) !void {
    var parsed = addr.parse(allocator, raw, aliases) catch return;
    defer parsed.deinit(allocator);
    const module_alias = parsed.module orelse return;
    const module = findModule(modules, module_alias) orelse return error.ImportNotResolved;
    if (graph_mod.resource(&module.graph, parsed.resource) == null) return error.UnknownModuleResource;
}

fn findModule(modules: []const Module, alias: []const u8) ?*const Module {
    for (modules) |*module| if (std.mem.eql(u8, module.alias, alias)) return module;
    return null;
}

