const std = @import("std");
const graph_mod = @import("graph.zig");
const resolve_mod = @import("resolve.zig");
const res = @import("resource.zig");
const addr = @import("address.zig");
const validate_mod = @import("validate.zig");
const val = @import("value.zig");

pub const ResourceRef = struct {
    id: []const u8,
    value: *const val.Value,
};

pub const AddressRef = struct {
    graph: *const graph_mod.Graph,
    resource_id: []const u8,
    resource: *const val.Value,
    value: *const val.Value,
};

pub fn resourcesByKind(allocator: std.mem.Allocator, graph: *const graph_mod.Graph, kind_name: []const u8) ![]ResourceRef {
    const resources = graph.resources() orelse return allocator.alloc(ResourceRef, 0);
    if (resources.* != .mapping) return allocator.alloc(ResourceRef, 0);
    var out = std.ArrayList(ResourceRef).empty;
    errdefer out.deinit(allocator);
    var it = resources.mapping.iterator();
    while (it.next()) |entry| if (std.mem.eql(u8, res.kindName(entry.value_ptr) orelse "", kind_name)) try out.append(allocator, .{ .id = entry.key_ptr.*, .value = entry.value_ptr });
    return out.toOwnedSlice(allocator);
}

pub fn field(graph: *const graph_mod.Graph, resource_id: []const u8, field_name: []const u8) ?*const val.Value {
    const resource = graph_mod.resource(graph, resource_id) orelse return null;
    const body = res.body(resource) orelse return null;
    return val.objectGet(body, field_name);
}

pub fn valueAtPath(root: *const val.Value, path: []const []const u8) ?*const val.Value {
    var current = root;
    for (path) |part| current = val.objectGet(current, part) orelse return null;
    return current;
}

pub fn address(graph: *const graph_mod.Graph, parsed: addr.Address) ?AddressRef {
    if (parsed.module != null) return null;
    const resources = graph.resources() orelse return null;
    if (resources.* != .mapping) return null;
    const entry = resources.mapping.getEntry(parsed.resource) orelse return null;
    const resource = entry.value_ptr;
    const value = if (parsed.field_path.len == 0) resource else valueAtPath(res.body(resource) orelse resource, parsed.field_path) orelse return null;
    return .{ .graph = graph, .resource_id = entry.key_ptr.*, .resource = resource, .value = value };
}

pub fn resolvedAddress(resolved: *const resolve_mod.ResolvedGraph, parsed: addr.Address) ?AddressRef {
    if (parsed.module) |module_alias| {
        const module = resolved.module(module_alias) orelse return null;
        return address(&module.graph, .{ .raw = parsed.raw, .module = null, .resource = parsed.resource, .field_path = parsed.field_path });
    }
    return address(&resolved.graph, parsed);
}

pub fn parseAndResolve(allocator: std.mem.Allocator, resolved: *const resolve_mod.ResolvedGraph, raw: []const u8) !AddressRef {
    const aliases = try validate_mod.importAliases(allocator, &resolved.graph);
    defer validate_mod.freeStrings(allocator, aliases);
    var parsed = try addr.parse(allocator, raw, aliases);
    defer parsed.deinit(allocator);
    return resolvedAddress(resolved, parsed) orelse error.AddressNotFound;
}
