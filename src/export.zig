const std = @import("std");
const address = @import("address.zig");
const val = @import("value.zig");

pub const ExportSpec = struct {
    name: []const u8,
    run: []const u8,
    input: ?*const val.Value,
    returns: ?*const val.Value,
};

pub const Projection = struct {
    name: []u8,
    address: address.Address,

    pub fn deinit(self: Projection, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.address.deinit(allocator);
    }
};

pub fn get(exports: *const val.Value, name: []const u8) ?ExportSpec {
    const spec = val.objectGet(exports, name) orelse return null;
    if (spec.* == .string) return .{ .name = name, .run = spec.string, .input = null, .returns = null };
    if (spec.* == .mapping) {
        const run = val.objectGet(spec, "run") orelse return null;
        if (run.* != .string) return null;
        return .{ .name = name, .run = run.string, .input = val.objectGet(spec, "input"), .returns = val.objectGet(spec, "returns") };
    }
    return null;
}

pub fn projections(allocator: std.mem.Allocator, spec: ExportSpec, aliases: []const []const u8) ![]Projection {
    const returns = spec.returns orelse return allocator.alloc(Projection, 0);
    if (returns.* != .mapping) return error.InvalidReturns;
    var out = std.ArrayList(Projection).empty;
    errdefer {
        for (out.items) |projection| projection.deinit(allocator);
        out.deinit(allocator);
    }
    var it = returns.mapping.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* != .string) return error.InvalidReturns;
        try out.append(allocator, .{
            .name = try allocator.dupe(u8, entry.key_ptr.*),
            .address = try address.parse(allocator, entry.value_ptr.string, aliases),
        });
    }
    return out.toOwnedSlice(allocator);
}

pub fn freeProjections(allocator: std.mem.Allocator, items: []Projection) void {
    for (items) |item| item.deinit(allocator);
    allocator.free(items);
}
