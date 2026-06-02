const std = @import("std");
const circuitry = @import("circuitry");

test "valid fixture validates" {
    var graph = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/minimal.circuitry.yaml");
    defer graph.deinit();
    try circuitry.validate(std.testing.allocator, &graph);
}

test "invalid fixture rejects removed entry" {
    var graph = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/invalid-removed-entry.circuitry.yaml");
    defer graph.deinit();
    try std.testing.expectError(error.InvalidCircuitryGraph, circuitry.validate(std.testing.allocator, &graph));
}

test "invalid nested model list loads then validates with diagnostics" {
    var graph = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/invalid-model-list.circuitry.yaml");
    defer graph.deinit();
    try std.testing.expectError(error.InvalidCircuitryGraph, circuitry.validate(std.testing.allocator, &graph));
}

// Covers alias conflicts, run.export type, run input key ids, source path type, and schema field ids.
test "validator parity rejects malformed graph shape" {
    var graph = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/invalid-parity.circuitry.yaml");
    defer graph.deinit();
    try std.testing.expectError(error.InvalidCircuitryGraph, circuitry.validate(std.testing.allocator, &graph));
}

test "load normalizes source shorthand" {
    var graph = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/minimal.circuitry.yaml");
    defer graph.deinit();
    const message = circuitry.graph.resource(&graph, "message") orelse return error.TestExpectedResource;
    const body = circuitry.resource.body(message) orelse return error.TestExpectedResource;
    const value = circuitry.value.objectGet(body, "value") orelse return error.TestExpectedResource;
    try std.testing.expectEqualStrings("Hello from Circuitry.", value.string);
}

test "return projections parse addresses" {
    var graph = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/projected-return.circuitry.yaml");
    defer graph.deinit();
    const projections = try circuitry.returnProjections(std.testing.allocator, &graph, "main");
    defer circuitry.exports.freeProjections(std.testing.allocator, projections);
    try std.testing.expectEqual(@as(usize, 1), projections.len);
    try std.testing.expectEqualStrings("answer", projections[0].name);
    try std.testing.expectEqualStrings("assistant", projections[0].address.resource);
    try std.testing.expectEqualStrings("answer", projections[0].address.field_path[0]);
}

test "resolve loads imported modules" {
    const graph = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/imports.circuitry.yaml");
    var resolved = try circuitry.resolve(std.testing.allocator, std.testing.io, graph, .{});
    defer resolved.deinit();
    try std.testing.expectEqual(@as(usize, 1), resolved.modules.len);
    try std.testing.expectEqualStrings("shared", resolved.modules[0].alias);
    try std.testing.expect(circuitry.graph.resource(&resolved.modules[0].graph, "shared_text") != null);
}

test "resolve rejects missing imported resources" {
    const graph = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/import-missing-resource.circuitry.yaml");
    try std.testing.expectError(error.UnknownModuleResource, circuitry.resolve(std.testing.allocator, std.testing.io, graph, .{}));
}

test "resolved plan includes module-qualified dependencies" {
    const graph = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/imported-plan.circuitry.yaml");
    var resolved = try circuitry.resolve(std.testing.allocator, std.testing.io, graph, .{});
    defer resolved.deinit();
    const steps = try circuitry.plan.planResolvedExport(std.testing.allocator, &resolved, "main");
    defer circuitry.plan.freeResolvedPlan(std.testing.allocator, steps);
    try std.testing.expectEqual(@as(usize, 2), steps.len);
    try std.testing.expectEqualStrings("shared", steps[0].module.?);
    try std.testing.expectEqualStrings("shared_text", steps[0].id);
    try std.testing.expectEqualStrings("assistant", steps[1].id);
    try std.testing.expectEqualStrings("shared.shared_text", steps[1].dependencies[0]);
}

test "deterministic schema fixture validates and custom payload is queryable" {
    var graph = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/schema-valid.circuitry.yaml");
    defer graph.deinit();
    try circuitry.validate(std.testing.allocator, &graph);

    try std.testing.expectEqualStrings("extension", circuitry.query.resourceKind(&graph, "example_extension").?);
    const payload = circuitry.query.customResourcePayload(&graph, "example_extension", "extension") orelse return error.TestExpectedResource;
    const package = circuitry.value.objectGet(payload, "package") orelse return error.TestExpectedResource;
    try std.testing.expectEqualStrings("@zinc/example", package.string);

    const schema = circuitry.query.modelSchema(&graph, "assistant") orelse return error.TestExpectedResource;
    try std.testing.expect(circuitry.schema.validate(schema));
    const sample_body = circuitry.query.resourceBody(&graph, "sample_answer") orelse return error.TestExpectedResource;
    const sample_value = circuitry.value.objectGet(sample_body, "value") orelse return error.TestExpectedResource;
    try std.testing.expect(circuitry.schema.validateValue(schema, sample_value));
}

// Covers unknown operators, enum shape, and invalid pattern diagnostics.
test "deterministic schema fixture rejects invalid operators" {
    var graph = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/schema-invalid.circuitry.yaml");
    defer graph.deinit();
    var diagnostics: circuitry.diagnostic.List = .empty;
    defer {
        circuitry.diagnostic.deinitList(std.testing.allocator, diagnostics.items);
        diagnostics.deinit(std.testing.allocator);
    }
    try circuitry.collectDiagnostics(std.testing.allocator, &graph, &diagnostics);
    try std.testing.expect(diagnostics.items.len >= 3);
    var saw_minimum = false;
    var saw_enum = false;
    var saw_pattern = false;
    for (diagnostics.items) |item| {
        if (std.mem.indexOf(u8, item.message, "minimum") != null and std.mem.indexOf(u8, item.path, "resources.assistant.model.schema.score.minimum") != null) saw_minimum = true;
        if (std.mem.indexOf(u8, item.message, "must be a list") != null and std.mem.indexOf(u8, item.path, "resources.assistant.model.schema.status.enum") != null) saw_enum = true;
        if (std.mem.indexOf(u8, item.message, "is invalid") != null and std.mem.indexOf(u8, item.path, "resources.assistant.model.schema.slug.pattern") != null) saw_pattern = true;
    }
    try std.testing.expect(saw_minimum);
    try std.testing.expect(saw_enum);
    try std.testing.expect(saw_pattern);
}

 test "query resolves module address and resource metadata is ignored" {
    var graph = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/metadata-resource.circuitry.yaml");
    defer graph.deinit();
    const assistant = circuitry.graph.resource(&graph, "assistant") orelse return error.TestExpectedResource;
    try std.testing.expectEqualStrings("model", circuitry.resource.kindName(assistant).?);

    const imported = try circuitry.loadFile(std.testing.allocator, std.testing.io, "tests/fixtures/imports.circuitry.yaml");
    var resolved = try circuitry.resolve(std.testing.allocator, std.testing.io, imported, .{});
    defer resolved.deinit();
    const found = try circuitry.query.parseAndResolve(std.testing.allocator, &resolved, "shared.shared_text");
    try std.testing.expectEqualStrings("shared_text", found.resource_id);
}
