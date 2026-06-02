const std = @import("std");
const graph_mod = @import("graph.zig");
const res = @import("resource.zig");
const addr = @import("address.zig");
const diag = @import("diagnostic.zig");
const schema = @import("schema.zig");
const val = @import("value.zig");

pub const ValidationError = error{ InvalidCircuitryGraph };

pub fn validate(allocator: std.mem.Allocator, graph: *const graph_mod.Graph) !void {
    var diagnostics: diag.List = .empty;
    defer {
        diag.deinitList(allocator, diagnostics.items);
        diagnostics.deinit(allocator);
    }
    try collect(allocator, graph, &diagnostics);
    if (diagnostics.items.len != 0) return ValidationError.InvalidCircuitryGraph;
}

pub fn collect(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, diagnostics: *diag.List) !void {
    if (graph.root != .mapping) {
        try diag.add(allocator, diagnostics, "invalid_graph", "", "graph must be an object", .{});
        return;
    }
    if (graph_mod.version(graph) == null or !std.mem.eql(u8, graph_mod.version(graph).?, "0.5")) try diag.add(allocator, diagnostics, "invalid_version", "circuitry", "circuitry must be 0.5", .{});
    inline for (.{ "inputs", "outputs", "entry", "entries", "defs", "sets", "vars" }) |field| {
        if (val.objectGet(&graph.root, field) != null) try diag.add(allocator, diagnostics, "removed_field", field, "{s} is not valid in Circuitry 0.5", .{field});
    }

    const resources = graph.resources() orelse {
        try diag.add(allocator, diagnostics, "missing_resources", "resources", "resources must be an object", .{});
        return;
    };
    if (resources.* != .mapping) {
        try diag.add(allocator, diagnostics, "missing_resources", "resources", "resources must be an object", .{});
        return;
    }

    const aliases = try importAliases(allocator, graph);
    defer freeStrings(allocator, aliases);

    if (graph.imports()) |imports| {
        if (imports.* != .mapping) {
            try diag.add(allocator, diagnostics, "invalid_imports", "imports", "imports must be a map", .{});
        } else {
            var it = imports.mapping.iterator();
            while (it.next()) |entry| {
                if (!addr.validIdentifier(entry.key_ptr.*)) try diag.add(allocator, diagnostics, "invalid_identifier", "imports", "invalid import alias {s}", .{entry.key_ptr.*});
                const spec = entry.value_ptr;
                if (!(spec.* == .string or (spec.* == .mapping and val.objectGet(spec, "path") != null and val.objectGet(spec, "path").?.* == .string))) {
                    try diag.add(allocator, diagnostics, "invalid_import", "imports", "import {s} must be a string or object with path", .{entry.key_ptr.*});
                }
            }
        }
    }

    if (graph.exports()) |exports| {
        if (exports.* != .mapping) {
            try diag.add(allocator, diagnostics, "invalid_exports", "exports", "exports must be a map", .{});
        } else {
            var it = exports.mapping.iterator();
            while (it.next()) |entry| try validateExport(allocator, graph, diagnostics, aliases, entry.key_ptr.*, entry.value_ptr);
        }
    }

    var rit = resources.mapping.iterator();
    while (rit.next()) |entry| {
        if (containsString(aliases, entry.key_ptr.*)) try diag.add(allocator, diagnostics, "identifier_conflict", "resources", "resource {s} conflicts with an import alias", .{entry.key_ptr.*});
        try validateResource(allocator, graph, diagnostics, aliases, resources, entry.key_ptr.*, entry.value_ptr);
    }
    if (graph.exports()) |exports| if (exports.* == .mapping) {
        var eit = exports.mapping.iterator();
        while (eit.next()) |entry| try validateRuntimeInputsForExport(allocator, graph, diagnostics, entry.key_ptr.*);
    };
    try detectCycles(allocator, diagnostics, aliases, resources);
}

fn validateExport(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, diagnostics: *diag.List, aliases: []const []const u8, name: []const u8, spec: *const val.Value) !void {
    if (!addr.validIdentifier(name)) try diag.add(allocator, diagnostics, "invalid_identifier", "exports", "invalid export name {s}", .{name});
    var run: ?[]const u8 = null;
    var returns: ?*const val.Value = null;
    if (spec.* == .string) {
        run = spec.string;
    } else if (spec.* == .mapping) {
        if (val.objectGet(spec, "input")) |input| try validateExportInput(allocator, diagnostics, input);
        if (val.objectGet(spec, "output") != null) try diag.add(allocator, diagnostics, "removed_field", "exports", "exports.*.output is not valid", .{});
        if (val.objectGet(spec, "run")) |r| {
            if (r.* == .string) run = r.string;
        }
        returns = val.objectGet(spec, "returns");
    }
    if (run) |target| {
        try validateAddress(allocator, graph, diagnostics, aliases, target, "exports");
    } else {
        try diag.add(allocator, diagnostics, "invalid_export", "exports", "export {s} must be a string or object with run", .{name});
    }
    if (returns) |r| {
        if (r.* != .mapping) {
            try diag.add(allocator, diagnostics, "invalid_returns", "exports", "returns must be a map", .{});
        } else {
            var it = r.mapping.iterator();
            while (it.next()) |entry| {
                if (!addr.validIdentifier(entry.key_ptr.*)) try diag.add(allocator, diagnostics, "invalid_identifier", "exports.returns", "invalid return name {s}", .{entry.key_ptr.*});
                if (entry.value_ptr.* == .string) try validateAddress(allocator, graph, diagnostics, aliases, entry.value_ptr.string, "exports.returns") else try diag.add(allocator, diagnostics, "invalid_return", "exports.returns", "return must be an address string", .{});
            }
        }
    }
}

fn validateResource(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, diagnostics: *diag.List, aliases: []const []const u8, resources: *const val.Value, id: []const u8, resource: *const val.Value) !void {
    _ = graph;
    if (!addr.validIdentifier(id)) try diag.add(allocator, diagnostics, "invalid_identifier", "resources", "invalid resource id {s}", .{id});
    if (resource.* != .mapping) return diag.add(allocator, diagnostics, "invalid_resource", "resources", "resource {s} must be an object", .{id});
    inline for (.{ "type", "agent", "mime", "output" }) |field| {
        if (val.objectGet(resource, field) != null) try diag.add(allocator, diagnostics, "removed_field", "resources", "resources.*.{s} is not valid", .{field});
    }
    const kind_name = res.kindName(resource) orelse return diag.add(allocator, diagnostics, "invalid_resource_kind", "resources", "resource {s} must have exactly one primary kind", .{id});
    const body = res.body(resource) orelse return;
    if (std.mem.eql(u8, kind_name, "input")) {
        try diag.add(allocator, diagnostics, "removed_field", "resources.input", "input resources are not valid; declare export.input and reference $name", .{});
    } else if (std.mem.eql(u8, kind_name, "text") or std.mem.eql(u8, kind_name, "data") or std.mem.eql(u8, kind_name, "file")) {
        try validateSource(allocator, diagnostics, kind_name, body);
    } else if (std.mem.eql(u8, kind_name, "model")) {
        if (body.* != .mapping) try diag.add(allocator, diagnostics, "invalid_model", "resources.model", "model must be an object", .{}) else {
            if (val.objectGet(body, "inputs") != null) try diag.add(allocator, diagnostics, "removed_field", "resources.model.inputs", "model.inputs is not valid; use model.input", .{});
            if (val.objectGet(body, "input")) |input| if (input.* == .sequence) {
                const deps = res.dependencies(allocator, resource) catch |e| switch (e) {
                    error.InvalidList => return diag.add(allocator, diagnostics, "invalid_model_input", "resources.model.input", "model.input must be a list of strings", .{}),
                    else => return e,
                };
                defer freeStrings(allocator, deps);
                for (deps) |dep| try validateAddressOrRuntimeInput(allocator, diagnostics, aliases, resources, dep, "resources.model.input");
            } else try diag.add(allocator, diagnostics, "invalid_model_input", "resources.model.input", "model.input must be a list", .{});
            if (val.objectGet(body, "tools")) |tools| if (tools.* == .sequence) {
                var tool_names: std.ArrayList([]u8) = .empty;
                defer freeStringList(allocator, &tool_names);
                res.appendStringList(allocator, &tool_names, tools) catch |e| switch (e) {
                    error.InvalidList => try diag.add(allocator, diagnostics, "invalid_model_tools", "resources.model.tools", "model.tools must be a list of strings", .{}),
                    else => return e,
                };
            } else try diag.add(allocator, diagnostics, "invalid_model_tools", "resources.model.tools", "model.tools must be a list", .{});
            if (val.objectGet(body, "schema")) |s| {
                const schema_path = try std.fmt.allocPrint(allocator, "resources.{s}.model.schema", .{id});
                defer allocator.free(schema_path);
                try schema.validateWithDiagnostics(allocator, diagnostics, s, schema_path);
            }
        }
    } else if (std.mem.eql(u8, kind_name, "run")) {
        if (body.* != .mapping) try diag.add(allocator, diagnostics, "invalid_run", "resources.run", "run must be an object", .{}) else {
            const child = val.objectGet(body, "graph");
            if (child == null or child.?.* != .string) try diag.add(allocator, diagnostics, "missing_run_graph", "resources.run.graph", "run.graph is required", .{});
            if (val.objectGet(body, "export")) |run_export| if (run_export.* != .string) try diag.add(allocator, diagnostics, "invalid_run_export", "resources.run.export", "run.export must be a string", .{});
            if (val.objectGet(body, "input")) |input| if (input.* == .mapping) {
                var it = input.mapping.iterator();
                while (it.next()) |entry| {
                    if (!addr.validIdentifier(entry.key_ptr.*)) try diag.add(allocator, diagnostics, "invalid_identifier", "resources.run.input", "invalid run input name {s}", .{entry.key_ptr.*});
                    if (entry.value_ptr.* == .string) try validateAddressOrRuntimeInput(allocator, diagnostics, aliases, resources, entry.value_ptr.string, "resources.run.input") else try diag.add(allocator, diagnostics, "invalid_run_input", "resources.run.input", "run input values must be address strings", .{});
                }
            } else try diag.add(allocator, diagnostics, "invalid_run_input", "resources.run.input", "run.input must be a map", .{});
            if (val.objectGet(body, "schema")) |s| {
                const schema_path = try std.fmt.allocPrint(allocator, "resources.{s}.run.schema", .{id});
                defer allocator.free(schema_path);
                try schema.validateWithDiagnostics(allocator, diagnostics, s, schema_path);
            }
        }
    }
}

fn validateSource(allocator: std.mem.Allocator, diagnostics: *diag.List, kind: []const u8, body: *const val.Value) !void {
    if (body.* == .string) return;
    if (body.* != .mapping) return diag.add(allocator, diagnostics, "invalid_source", "resources", "{s} source must be a string or object", .{kind});
    var count: usize = 0;
    inline for (.{ "value", "path", "uri" }) |field| {
        if (val.objectGet(body, field) != null) count += 1;
    }
    if (count != 1) try diag.add(allocator, diagnostics, "invalid_source", "resources", "{s} source must have exactly one of value, path, uri", .{kind});
    if (val.objectGet(body, "path")) |path| if (path.* != .string) try diag.add(allocator, diagnostics, "invalid_source_path", "resources", "{s}.path must be a string", .{kind});
    if (val.objectGet(body, "uri")) |uri| if (uri.* != .string) try diag.add(allocator, diagnostics, "invalid_source_uri", "resources", "{s}.uri must be a string", .{kind});
}

fn validateExportInput(allocator: std.mem.Allocator, diagnostics: *diag.List, input: *const val.Value) !void {
    if (input.* != .mapping) return diag.add(allocator, diagnostics, "invalid_export_input", "exports.input", "export.input must be a schema map", .{});
    var it = input.mapping.iterator();
    while (it.next()) |entry| {
        if (!addr.validIdentifier(entry.key_ptr.*)) try diag.add(allocator, diagnostics, "invalid_identifier", "exports.input", "invalid export input {s}", .{entry.key_ptr.*});
        const schema_path = try std.fmt.allocPrint(allocator, "exports.input.{s}", .{entry.key_ptr.*});
        defer allocator.free(schema_path);
        try schema.validateWithDiagnostics(allocator, diagnostics, entry.value_ptr, schema_path);
    }
}

fn validateRuntimeInputsForExport(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, diagnostics: *diag.List, export_name: []const u8) !void {
    const exports = graph.exports() orelse return;
    const spec = @import("export.zig").get(exports, export_name) orelse return;
    const ids = @import("plan.zig").runSet(allocator, graph, export_name) catch return;
    defer freeStrings(allocator, ids);
    var used: std.ArrayList([]u8) = .empty;
    defer freeStringList(allocator, &used);
    for (ids) |id| {
        const rv = graph_mod.resource(graph, id) orelse continue;
        try res.appendRuntimeInputs(allocator, &used, rv);
    }
    for (used.items) |name| if (!exportInputDeclares(spec.input, name)) try diag.add(allocator, diagnostics, "undeclared_runtime_input", "exports.input", "${s} is used but not declared on export input", .{name});
}

fn exportInputDeclares(input: ?*const val.Value, name: []const u8) bool {
    const map = input orelse return false;
    return val.objectGet(map, name) != null;
}

fn validateAddressOrRuntimeInput(allocator: std.mem.Allocator, diagnostics: *diag.List, aliases: []const []const u8, resources: *const val.Value, raw: []const u8, path: []const u8) !void {
    if (res.runtimeInputName(raw)) |name| {
        if (!addr.validIdentifier(name)) try diag.add(allocator, diagnostics, "invalid_identifier", path, "invalid runtime input {s}", .{name});
        return;
    }
    try validateAddressAgainstResources(allocator, diagnostics, aliases, resources, raw, path);
}

fn validateAddress(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, diagnostics: *diag.List, aliases: []const []const u8, raw: []const u8, path: []const u8) !void {
    const resources = graph.resources() orelse return;
    try validateAddressAgainstResources(allocator, diagnostics, aliases, resources, raw, path);
}

fn validateAddressAgainstResources(allocator: std.mem.Allocator, diagnostics: *diag.List, aliases: []const []const u8, resources: *const val.Value, raw: []const u8, path: []const u8) !void {
    var parsed = addr.parse(allocator, raw, aliases) catch return diag.add(allocator, diagnostics, "invalid_address", path, "invalid address {s}", .{raw});
    defer parsed.deinit(allocator);
    if (parsed.module == null and val.objectGet(resources, parsed.resource) == null) try diag.add(allocator, diagnostics, "unknown_resource", path, "unknown resource {s}", .{parsed.resource});
}

fn detectCycles(allocator: std.mem.Allocator, diagnostics: *diag.List, aliases: []const []const u8, resources: *const val.Value) !void {
    var visiting = std.StringHashMap(bool).init(allocator);
    defer visiting.deinit();
    var visited = std.StringHashMap(bool).init(allocator);
    defer visited.deinit();
    var it = resources.mapping.iterator();
    while (it.next()) |entry| try visit(allocator, diagnostics, aliases, resources, &visiting, &visited, entry.key_ptr.*);
}

fn visit(allocator: std.mem.Allocator, diagnostics: *diag.List, aliases: []const []const u8, resources: *const val.Value, visiting: *std.StringHashMap(bool), visited: *std.StringHashMap(bool), id: []const u8) !void {
    if (visited.contains(id)) return;
    if (visiting.contains(id)) return diag.add(allocator, diagnostics, "cycle", "resources", "resource dependency cycle at {s}", .{id});
    try visiting.put(id, true);
    const resource_value = val.objectGet(resources, id) orelse return;
    var deps: std.ArrayList([]u8) = .empty;
    defer freeStringList(allocator, &deps);
    res.appendResourceDependencies(allocator, &deps, resource_value) catch |e| switch (e) {
        error.InvalidList => {
            try diag.add(allocator, diagnostics, "invalid_dependency_list", "resources", "resource dependency list must contain only strings", .{});
            return;
        },
        else => return e,
    };
    for (deps.items) |dep| {
        var parsed = addr.parse(allocator, dep, aliases) catch continue;
        defer parsed.deinit(allocator);
        if (parsed.module == null and val.objectGet(resources, parsed.resource) != null) try visit(allocator, diagnostics, aliases, resources, visiting, visited, parsed.resource);
    }
    _ = visiting.remove(id);
    try visited.put(id, true);
}

fn containsString(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item, needle)) return true;
    return false;
}

fn freeStringList(allocator: std.mem.Allocator, list: *std.ArrayList([]u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
}

pub fn importAliases(allocator: std.mem.Allocator, graph: *const graph_mod.Graph) ![][]u8 {
    const imports = graph.imports() orelse return allocator.alloc([]u8, 0);
    if (imports.* != .mapping) return allocator.alloc([]u8, 0);
    var out = try allocator.alloc([]u8, imports.mapping.count());
    var it = imports.mapping.iterator();
    var i: usize = 0;
    while (it.next()) |entry| : (i += 1) out[i] = try allocator.dupe(u8, entry.key_ptr.*);
    return out;
}

pub fn freeStrings(allocator: std.mem.Allocator, strings: []const []u8) void {
    for (strings) |s| allocator.free(s);
    allocator.free(strings);
}
