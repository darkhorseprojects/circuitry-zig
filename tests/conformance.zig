const std = @import("std");
const circuitry = @import("circuitry");

test "reads 0.6.1 system shape" {
    const allocator = std.testing.allocator;
    var s = try circuitry.loadText(allocator,
        \\circuitry: "0.6.1"
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

test "confirms ready system and surfaces model" {
    const allocator = std.testing.allocator;
    var s = try circuitry.loadText(allocator,
        \\circuitry: "0.6.1"
        \\name: x
        \\takes:
        \\  $question: text
        \\uses:
        \\  draft:
        \\    model: fast
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
    try std.testing.expectEqualStrings("fast", result.system.uses[0].model.?);
    try std.testing.expectEqualStrings("action", result.system.uses[0].instructions.?);
}

test "discovers value and package references" {
    const allocator = std.testing.allocator;
    var s = try circuitry.loadText(allocator,
        \\circuitry: "0.6.1"
        \\name: x
        \\zinc:
        \\  packages:
        \\    browser: zinc://package/browser@0.6.1
        \\takes:
        \\  $question: text
        \\uses:
        \\  search:
        \\    shape: @browser.shapes.search-web
        \\    takes:
        \\      query: $question
        \\    gives:
        \\      sources: $sources
        \\gives:
        \\  $sources: list
    );
    defer s.deinit();
    var view = try circuitry.systemView(allocator, &s);
    defer view.deinit();
    try std.testing.expectEqual(@as(usize, 2), view.value_refs.len);
    try std.testing.expectEqual(@as(usize, 1), view.package_refs.len);
    try std.testing.expectEqualStrings("@browser.shapes.search-web", view.package_refs[0]);
}

test "diagnoses unresolved values" {
    const allocator = std.testing.allocator;
    var s = try circuitry.loadText(allocator,
        \\circuitry: "0.6.1"
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
        \\circuitry: "0.6.1"
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
