const std = @import("std");
const graph_mod = @import("graph.zig");
const res = @import("resource.zig");

pub fn render(allocator: std.mem.Allocator, graph: *const graph_mod.Graph) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.print(allocator, "{s}\n", .{graph_mod.title(graph) orelse "Circuitry graph"});
    try out.print(allocator, "version: {s}\n", .{graph_mod.version(graph) orelse "(missing)"});
    if (graph.imports()) |imports| try out.print(allocator, "imports: {d}\n", .{if (imports.* == .mapping) imports.mapping.count() else 0}) else try out.appendSlice(allocator, "imports: 0\n");
    if (graph.exports()) |exports| try out.print(allocator, "exports: {d}\n", .{if (exports.* == .mapping) exports.mapping.count() else 0}) else try out.appendSlice(allocator, "exports: 0\n");
    const resources = graph.resources();
    try out.print(allocator, "resources: {d}\n\nresources:\n", .{if (resources != null and resources.?.* == .mapping) resources.?.mapping.count() else 0});
    if (resources) |r| if (r.* == .mapping) {
        var it = r.mapping.iterator();
        while (it.next()) |entry| try out.print(allocator, "  - {s}: {s}\n", .{ entry.key_ptr.*, res.kindName(entry.value_ptr) orelse "(invalid)" });
    };
    return out.toOwnedSlice(allocator);
}
