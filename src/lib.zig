const std = @import("std");

pub const value = @import("value.zig");
pub const graph = @import("graph.zig");
pub const resource = @import("resource.zig");
pub const exports = @import("export.zig");
pub const imports = @import("imports.zig");
pub const address = @import("address.zig");
pub const schema = @import("schema.zig");
pub const plan = @import("plan.zig");
pub const query = @import("query.zig");
pub const diagnostic = @import("diagnostic.zig");
pub const validation = @import("validate.zig");
pub const normalize = @import("normalize.zig");
pub const resolver = @import("resolve.zig");
pub const inspect = @import("inspect.zig");

pub const Graph = graph.Graph;
pub const ResolvedGraph = resolver.ResolvedGraph;
pub const DependencyPlan = []plan.Step;
pub const ReturnProjection = exports.Projection;
pub const Diagnostic = diagnostic.Diagnostic;
pub const ValidationError = validation.ValidationError;
pub const Address = address.Address;

pub const loadYamlFile = graph.loadYamlFile;
pub const loadFile = graph.loadFile;
pub const validate = validation.validate;
pub const collectDiagnostics = validation.collect;
pub const resolve = resolver.resolve;
pub const requiredInputs = plan.requiredInputs;
pub const planExport = plan.planExport;

pub fn getExport(g: *const Graph, name: []const u8) ?exports.ExportSpec {
    const e = g.exports() orelse return null;
    return exports.get(e, name);
}

pub fn returnProjections(allocator: std.mem.Allocator, g: *const Graph, name: []const u8) ![]exports.Projection {
    const spec = getExport(g, name) orelse return error.ExportNotFound;
    const aliases = try validation.importAliases(allocator, g);
    defer validation.freeStrings(allocator, aliases);
    return exports.projections(allocator, spec, aliases);
}

test {
    _ = value;
    _ = graph;
    _ = resource;
    _ = exports;
    _ = address;
    _ = schema;
    _ = plan;
    _ = query;
    _ = validation;
    _ = inspect;
}
