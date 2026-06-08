const std = @import("std");
const circuitry = @import("circuitry");

test "reads minimal 0.6 shape" {
    const allocator = std.testing.allocator;
    var s = try circuitry.loadText(allocator,
        \\circuitry: 0.6
        \\name: deep search
        \\takes:
        \\  - question
        \\does: search broadly
        \\gives:
        \\  - answer
    );
    defer s.deinit();
    var c = try circuitry.card(allocator, &s);
    defer c.deinit();
    try std.testing.expectEqualStrings("deep search", c.name);
    try std.testing.expectEqual(@as(usize, 1), c.takes.len);
    try std.testing.expectEqualStrings("question", c.takes[0]);
}

test "confirms ready" {
    const allocator = std.testing.allocator;
    var s = try circuitry.loadText(allocator,
        \\circuitry: "0.6"
        \\name: x
        \\does: action
        \\gives: result
    );
    defer s.deinit();
    var result = try circuitry.confirm(allocator, &s);
    defer result.deinit();
    try std.testing.expect(result.ready);
}
