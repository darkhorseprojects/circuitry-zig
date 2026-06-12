const std = @import("std");
const circuitry = @import("circuitry");

test "reads 0.6.4 system shape" {
    const allocator = std.testing.allocator;
    var s = try circuitry.loadText(allocator,
        \\circuitry: "0.6.4"
        \\name: deep search
        \\takes:
        \\  $question: text
        \\uses:
        \\  search:
        \\    takes:
        \\      query: $question
        \\    gives:
        \\      sources: $sources
        \\gives:
        \\  $sources: list
    );
    defer s.deinit();
    var c = try circuitry.card(allocator, &s);
    defer c.deinit();
    try std.testing.expectEqualStrings("deep search", c.name);
    try std.testing.expectEqual(@as(usize, 1), c.takes.len);
    try std.testing.expectEqualStrings("$question", c.takes[0]);
    try std.testing.expectEqual(@as(usize, 1), c.uses.len);
    try std.testing.expectEqualStrings("search", c.uses[0]);
}

test "confirms ready system" {
    const allocator = std.testing.allocator;
    var s = try circuitry.loadText(allocator,
        \\circuitry: "0.6.4"
        \\name: x
        \\takes:
        \\  $question: text
        \\uses:
        \\  draft:
        \\    takes:
        \\      question: $question
        \\    does: action
        \\    gives:
        \\      answer: $answer
        \\gives:
        \\  $answer: text
    );
    defer s.deinit();
    var result = try circuitry.confirm(allocator, &s);
    defer result.deinit();
    try std.testing.expect(result.ready);
    try std.testing.expectEqualStrings("$question", result.asks[0]);
    try std.testing.expectEqualStrings("action", result.system.parts[0].instructions.?);
}

test "normalizes document facts" {
    const allocator = std.testing.allocator;
    var s = try circuitry.loadText(allocator,
        \\circuitry: "0.6.4"
        \\name: answer
        \\about: short answer
        \\takes:
        \\  $question: text
        \\uses:
        \\  answer:
        \\    model: default
        \\    takes:
        \\      question: $question
        \\    does: Answer briefly.
        \\    gives:
        \\      answer:
        \\        value: $answer
        \\        type: text
        \\gives:
        \\  $answer: text
    );
    defer s.deinit();
    var doc = try circuitry.normalize(allocator, &s);
    defer doc.deinit();
    try std.testing.expectEqualStrings("0.6.4", doc.version);
    try std.testing.expectEqualStrings("answer", doc.name);
    try std.testing.expectEqualStrings("short answer", doc.about.?);
    try std.testing.expectEqual(@as(usize, 1), doc.takes.len);
    try std.testing.expectEqualStrings("$question", doc.takes[0].name);
    try std.testing.expectEqualStrings("text", doc.takes[0].type_label.?);
    try std.testing.expectEqual(circuitry.Direction.takes, doc.takes[0].direction);
    try std.testing.expectEqual(@as(usize, 1), doc.parts.len);
    try std.testing.expectEqualStrings("answer", doc.parts[0].name);
    try std.testing.expectEqualStrings("default", doc.parts[0].model.?);
    try std.testing.expectEqualStrings("Answer briefly.", doc.parts[0].instructions.?);
    try std.testing.expectEqualStrings("question", doc.parts[0].takes[0].local.?);
    try std.testing.expectEqualStrings("$question", doc.parts[0].takes[0].value);
    try std.testing.expectEqual(null, doc.parts[0].takes[0].type_label);
    try std.testing.expectEqualStrings("answer", doc.parts[0].gives[0].local.?);
    try std.testing.expectEqualStrings("$answer", doc.parts[0].gives[0].value);
    try std.testing.expectEqualStrings("text", doc.parts[0].gives[0].type_label.?);
    try std.testing.expectEqual(@as(usize, 0), doc.diagnostics.len);
}

const MaterializerCounts = struct {
    docs: usize = 0,
    values: usize = 0,
    parts: usize = 0,
    bindings: usize = 0,
    diagnostics: usize = 0,

    fn doc(context: *anyopaque, fact: *const circuitry.NormalizedDoc) anyerror!void {
        _ = fact;
        const self: *MaterializerCounts = @ptrCast(@alignCast(context));
        self.docs += 1;
    }

    fn value(context: *anyopaque, fact: circuitry.NormalizedValue) anyerror!void {
        _ = fact;
        const self: *MaterializerCounts = @ptrCast(@alignCast(context));
        self.values += 1;
    }

    fn part(context: *anyopaque, fact: *const circuitry.NormalizedPart) anyerror!void {
        _ = fact;
        const self: *MaterializerCounts = @ptrCast(@alignCast(context));
        self.parts += 1;
    }

    fn binding(context: *anyopaque, fact: circuitry.MaterializedBinding) anyerror!void {
        _ = fact;
        const self: *MaterializerCounts = @ptrCast(@alignCast(context));
        self.bindings += 1;
    }

    fn diagnostic(context: *anyopaque, fact: circuitry.SystemDiagnostic) anyerror!void {
        _ = fact;
        const self: *MaterializerCounts = @ptrCast(@alignCast(context));
        self.diagnostics += 1;
    }
};

test "builds stable document and fact keys" {
    const allocator = std.testing.allocator;
    const first = try circuitry.stableDocId(allocator, "name: x\n");
    defer allocator.free(first);
    const second = try circuitry.stableDocId(allocator, "name: x\n");
    defer allocator.free(second);
    try std.testing.expectEqualStrings(first, second);
    try std.testing.expect(std.mem.startsWith(u8, first, "doc_"));

    const part = try circuitry.partKey(allocator, "answer");
    defer allocator.free(part);
    try std.testing.expectEqualStrings("part:answer", part);

    const val = try circuitry.valueKey(allocator, .takes, "$question");
    defer allocator.free(val);
    try std.testing.expectEqualStrings("value:takes:$question", val);

    const binding = try circuitry.bindingKey(allocator, "answer", .gives, "answer");
    defer allocator.free(binding);
    try std.testing.expectEqualStrings("binding:answer:gives:answer", binding);
}

test "materializes normalized facts" {
    const allocator = std.testing.allocator;
    var s = try circuitry.loadText(allocator,
        \\circuitry: "0.6.4"
        \\name: answer
        \\takes:
        \\  $question: text
        \\uses:
        \\  answer:
        \\    takes:
        \\      question: $question
        \\    gives:
        \\      answer: $answer
        \\gives:
        \\  $answer: text
    );
    defer s.deinit();
    var doc = try circuitry.normalize(allocator, &s);
    defer doc.deinit();
    var counts: MaterializerCounts = .{};
    try circuitry.materialize(&doc, .{
        .context = &counts,
        .doc = MaterializerCounts.doc,
        .value = MaterializerCounts.value,
        .part = MaterializerCounts.part,
        .binding = MaterializerCounts.binding,
        .diagnostic = MaterializerCounts.diagnostic,
    });
    try std.testing.expectEqual(@as(usize, 1), counts.docs);
    try std.testing.expectEqual(@as(usize, 2), counts.values);
    try std.testing.expectEqual(@as(usize, 1), counts.parts);
    try std.testing.expectEqual(@as(usize, 2), counts.bindings);
    try std.testing.expectEqual(@as(usize, 0), counts.diagnostics);
}

test "diagnoses unresolved values" {
    const allocator = std.testing.allocator;
    var s = try circuitry.loadText(allocator,
        \\circuitry: "0.6.4"
        \\name: broken
        \\uses:
        \\  draft:
        \\    takes:
        \\      notes: $notes
        \\    gives:
        \\      answer: $answer
        \\gives:
        \\  $answer: text
    );
    defer s.deinit();
    var result = try circuitry.confirm(allocator, &s);
    defer result.deinit();
    try std.testing.expect(!result.ready);
    try std.testing.expectEqualStrings("unresolved-value", result.system.diagnostics[0].kind);
}

test "diagnoses duplicate producers and cycles" {
    const allocator = std.testing.allocator;
    var s = try circuitry.loadText(allocator,
        \\circuitry: "0.6.4"
        \\name: broken
        \\uses:
        \\  a:
        \\    takes:
        \\      input: $b
        \\    gives:
        \\      output: $a
        \\      other: $same
        \\  b:
        \\    takes:
        \\      input: $a
        \\    gives:
        \\      output: $b
        \\      other: $same
        \\gives:
        \\  $a: text
    );
    defer s.deinit();
    var result = try circuitry.confirm(allocator, &s);
    defer result.deinit();
    var saw_duplicate = false;
    var saw_cycle = false;
    for (result.system.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.kind, "duplicate-producer")) saw_duplicate = true;
        if (std.mem.eql(u8, diagnostic.kind, "cycle")) saw_cycle = true;
    }
    try std.testing.expect(saw_duplicate);
    try std.testing.expect(saw_cycle);
}
