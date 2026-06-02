const std = @import("std");
const addr = @import("address.zig");
const diag = @import("diagnostic.zig");
const val = @import("value.zig");

const scalar_names = [_][]const u8{ "string", "number", "integer", "boolean", "null", "any" };
const reserved_keys = [_][]const u8{ "object", "extra", "optional", "nullable", "array", "list", "record", "key", "union", "literal", "enum", "range", "length", "pattern", "type", "annotations" };
const forbidden_operators = [_][]const u8{ "judge", "criteria", "assertions", "evaluation", "template", "script", "transform", "compute", "derive", "default", "environment", "oneOf", "anyOf", "allOf", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "minLength", "maxLength", "minItems", "maxItems", "properties", "items", "additionalProperties", "format", "$ref" };

pub fn validate(schema: *const val.Value) bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var sink: diag.List = .empty;
    defer sink.deinit(allocator);
    validateNode(allocator, &sink, schema, "schema") catch return false;
    return sink.items.len == 0;
}

pub fn validateWithDiagnostics(allocator: std.mem.Allocator, diagnostics: *diag.List, schema: *const val.Value, path: []const u8) !void {
    try validateNode(allocator, diagnostics, schema, path);
}

pub fn validateValue(schema: *const val.Value, value: *const val.Value) bool {
    return validateValueNode(schema, value, false);
}

fn validateNode(allocator: std.mem.Allocator, diagnostics: *diag.List, schema: *const val.Value, path: []const u8) anyerror!void {
    switch (schema.*) {
        .string => |s| {
            if (!isScalar(s)) try diag.add(allocator, diagnostics, "invalid_schema", path, "{s} uses unknown schema scalar {s}", .{ path, s });
        },
        .mapping => |*map| {
            var semantic_count: usize = 0;
            var reserved_count: usize = 0;
            var ordinary_count: usize = 0;
            var it = map.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (std.mem.eql(u8, key, "annotations")) {
                    if (entry.value_ptr.* != .mapping) try addPath(allocator, diagnostics, path, key, "invalid_schema", "{s} must be a map", .{});
                    continue;
                }
                semantic_count += 1;
                if (isForbidden(key)) {
                    const child_path = try joinPath(allocator, path, key);
                    defer allocator.free(child_path);
                    try diag.add(allocator, diagnostics, "invalid_schema", child_path, "{s} uses unknown schema operator {s}", .{ child_path, key });
                }
                if (isReserved(key)) reserved_count += 1 else ordinary_count += 1;
            }

            if (reserved_count == 0 or ordinary_count > 0) {
                var fields = map.iterator();
                while (fields.next()) |entry| {
                    const key = entry.key_ptr.*;
                    if (std.mem.eql(u8, key, "annotations")) continue;
                    const child_path = try joinPath(allocator, path, key);
                    defer allocator.free(child_path);
                    if (!addr.validIdentifier(key)) try diag.add(allocator, diagnostics, "invalid_identifier", child_path, "schema field name {s} is invalid", .{key});
                    try validateNode(allocator, diagnostics, entry.value_ptr, child_path);
                }
                return;
            }

            if (hasMap(map, "optional")) return validateUnary(allocator, diagnostics, schema, path, "optional", semantic_count);
            if (hasMap(map, "nullable")) return validateUnary(allocator, diagnostics, schema, path, "nullable", semantic_count);
            if (hasMap(map, "literal")) return validateLiteral(allocator, diagnostics, schema, path, semantic_count);
            if (hasMap(map, "enum")) return validateEnum(allocator, diagnostics, schema, path, semantic_count);
            if (hasMap(map, "union")) return validateUnion(allocator, diagnostics, schema, path, semantic_count);
            if (hasMap(map, "object")) return validateObject(allocator, diagnostics, schema, path);
            if (hasMap(map, "array") or hasMap(map, "list")) return validateArray(allocator, diagnostics, schema, path);
            if (hasMap(map, "record")) return validateRecord(allocator, diagnostics, schema, path);
            if (hasMap(map, "type")) return validateTyped(allocator, diagnostics, schema, path);

            var bad = map.iterator();
            while (bad.next()) |entry| if (!std.mem.eql(u8, entry.key_ptr.*, "annotations")) try addPath(allocator, diagnostics, path, entry.key_ptr.*, "invalid_schema", "{s} is not valid in this schema position", .{});
        },
        else => try diag.add(allocator, diagnostics, "invalid_schema", path, "{s} must be a schema scalar or map", .{path}),
    }
}

fn validateUnary(allocator: std.mem.Allocator, diagnostics: *diag.List, schema: *const val.Value, path: []const u8, key: []const u8, semantic_count: usize) anyerror!void {
    if (semantic_count != 1) try diag.add(allocator, diagnostics, "invalid_schema", path, "{s} cannot combine {s} with other schema operators", .{ path, key });
    const child = val.objectGet(schema, key) orelse return;
    const child_path = try joinPath(allocator, path, key);
    defer allocator.free(child_path);
    try validateNode(allocator, diagnostics, child, child_path);
}

fn validateObject(allocator: std.mem.Allocator, diagnostics: *diag.List, schema: *const val.Value, path: []const u8) anyerror!void {
    try requireOnly(allocator, diagnostics, schema, path, &.{ "object", "extra", "annotations" }, "object schema");
    const fields = val.objectGet(schema, "object") orelse return;
    const fields_path = try joinPath(allocator, path, "object");
    defer allocator.free(fields_path);
    if (fields.* != .mapping) return diag.add(allocator, diagnostics, "invalid_schema", fields_path, "{s} must be a map", .{fields_path});
    if (val.objectGet(schema, "extra")) |extra| if (extra.* != .boolean) try addPath(allocator, diagnostics, path, "extra", "invalid_schema", "{s} must be a boolean", .{});
    var it = fields.mapping.iterator();
    while (it.next()) |entry| {
        const child_path = try joinPath(allocator, fields_path, entry.key_ptr.*);
        defer allocator.free(child_path);
        if (!addr.validIdentifier(entry.key_ptr.*)) try diag.add(allocator, diagnostics, "invalid_identifier", child_path, "schema field name {s} is invalid", .{entry.key_ptr.*});
        try validateNode(allocator, diagnostics, entry.value_ptr, child_path);
    }
}

fn validateArray(allocator: std.mem.Allocator, diagnostics: *diag.List, schema: *const val.Value, path: []const u8) anyerror!void {
    if (hasValue(schema, "array") and hasValue(schema, "list")) try diag.add(allocator, diagnostics, "invalid_schema", path, "{s} cannot use both array and list", .{path});
    try requireOnly(allocator, diagnostics, schema, path, &.{ "array", "list", "length", "annotations" }, "array schema");
    const key: []const u8 = if (hasValue(schema, "array")) "array" else "list";
    if (val.objectGet(schema, key)) |child| {
        const child_path = try joinPath(allocator, path, key);
        defer allocator.free(child_path);
        try validateNode(allocator, diagnostics, child, child_path);
    }
    if (val.objectGet(schema, "length")) |length| {
        const length_path = try joinPath(allocator, path, "length");
        try validateLength(allocator, diagnostics, length, length_path);
    }
}

fn validateRecord(allocator: std.mem.Allocator, diagnostics: *diag.List, schema: *const val.Value, path: []const u8) anyerror!void {
    try requireOnly(allocator, diagnostics, schema, path, &.{ "record", "key", "length", "annotations" }, "record schema");
    if (val.objectGet(schema, "record")) |child| {
        const child_path = try joinPath(allocator, path, "record");
        defer allocator.free(child_path);
        try validateNode(allocator, diagnostics, child, child_path);
    }
    if (val.objectGet(schema, "key")) |key_spec| {
        const key_path = try joinPath(allocator, path, "key");
        defer allocator.free(key_path);
        if (key_spec.* != .mapping or val.objectGet(key_spec, "pattern") == null or key_spec.mapping.count() != 1) try diag.add(allocator, diagnostics, "invalid_schema", key_path, "{s} must contain only pattern", .{key_path}) else {
            const pattern = val.objectGet(key_spec, "pattern").?;
            const pattern_path = try joinPath(allocator, key_path, "pattern");
            defer allocator.free(pattern_path);
            if (pattern.* != .string) try diag.add(allocator, diagnostics, "invalid_schema", pattern_path, "{s} must be a string", .{pattern_path}) else if (!validPattern(pattern.string)) try diag.add(allocator, diagnostics, "invalid_schema", pattern_path, "{s} is invalid", .{pattern_path});
        }
    }
    if (val.objectGet(schema, "length")) |length| {
        const length_path = try joinPath(allocator, path, "length");
        try validateLength(allocator, diagnostics, length, length_path);
    }
}

fn validateTyped(allocator: std.mem.Allocator, diagnostics: *diag.List, schema: *const val.Value, path: []const u8) anyerror!void {
    try requireOnly(allocator, diagnostics, schema, path, &.{ "type", "range", "length", "pattern", "annotations" }, "typed scalar schema");
    const type_path = try joinPath(allocator, path, "type");
    defer allocator.free(type_path);
    const t = val.objectGet(schema, "type") orelse return;
    if (t.* != .string or !isScalar(t.string)) try diag.add(allocator, diagnostics, "invalid_schema", type_path, "{s} must be a scalar schema name", .{type_path});
    if (val.objectGet(schema, "range")) |range| {
        const range_path = try joinPath(allocator, path, "range");
        try validateRange(allocator, diagnostics, range, range_path);
    }
    if (val.objectGet(schema, "length")) |length| {
        const length_path = try joinPath(allocator, path, "length");
        try validateLength(allocator, diagnostics, length, length_path);
    }
    if (val.objectGet(schema, "pattern")) |pattern| {
        const pattern_path = try joinPath(allocator, path, "pattern");
        defer allocator.free(pattern_path);
        if (pattern.* != .string) try diag.add(allocator, diagnostics, "invalid_schema", pattern_path, "{s} must be a string", .{pattern_path}) else if (!validPattern(pattern.string)) try diag.add(allocator, diagnostics, "invalid_schema", pattern_path, "{s} is invalid", .{pattern_path});
    }
}

fn validateLiteral(allocator: std.mem.Allocator, diagnostics: *diag.List, schema: *const val.Value, path: []const u8, semantic_count: usize) anyerror!void {
    if (semantic_count != 1) try diag.add(allocator, diagnostics, "invalid_schema", path, "{s} cannot combine literal with other schema operators", .{path});
    const literal_path = try joinPath(allocator, path, "literal");
    defer allocator.free(literal_path);
    if (!isScalarLiteral(val.objectGet(schema, "literal") orelse return)) try diag.add(allocator, diagnostics, "invalid_schema", literal_path, "{s} must be a scalar YAML value", .{literal_path});
}

fn validateEnum(allocator: std.mem.Allocator, diagnostics: *diag.List, schema: *const val.Value, path: []const u8, semantic_count: usize) anyerror!void {
    if (semantic_count != 1) try diag.add(allocator, diagnostics, "invalid_schema", path, "{s} cannot combine enum with other schema operators", .{path});
    const enum_path = try joinPath(allocator, path, "enum");
    defer allocator.free(enum_path);
    const items = val.objectGet(schema, "enum") orelse return;
    if (items.* != .sequence) return diag.add(allocator, diagnostics, "invalid_schema", enum_path, "{s} must be a list", .{enum_path});
    for (items.sequence, 0..) |*item, i| if (!isScalarLiteral(item)) {
        const item_path = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ enum_path, i });
        defer allocator.free(item_path);
        try diag.add(allocator, diagnostics, "invalid_schema", item_path, "{s} must be a scalar YAML value", .{item_path});
    };
}

fn validateUnion(allocator: std.mem.Allocator, diagnostics: *diag.List, schema: *const val.Value, path: []const u8, semantic_count: usize) anyerror!void {
    if (semantic_count != 1) try diag.add(allocator, diagnostics, "invalid_schema", path, "{s} cannot combine union with other schema operators", .{path});
    const union_path = try joinPath(allocator, path, "union");
    defer allocator.free(union_path);
    const union_value = val.objectGet(schema, "union") orelse return;
    if (union_value.* == .sequence) {
        for (union_value.sequence, 0..) |*branch, i| {
            const branch_path = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ union_path, i });
            defer allocator.free(branch_path);
            try validateNode(allocator, diagnostics, branch, branch_path);
        }
    } else if (union_value.* == .mapping) {
        const tag = val.objectGet(union_value, "tag");
        if (tag == null or tag.?.* != .string) try addPath(allocator, diagnostics, union_path, "tag", "invalid_schema", "{s} must be a string", .{});
        const variants = val.objectGet(union_value, "variants");
        const variants_path = try joinPath(allocator, union_path, "variants");
        defer allocator.free(variants_path);
        if (variants == null or variants.?.* != .mapping) return diag.add(allocator, diagnostics, "invalid_schema", variants_path, "{s} must be a map", .{variants_path});
        var it = variants.?.mapping.iterator();
        while (it.next()) |entry| {
            const branch_path = try joinPath(allocator, variants_path, entry.key_ptr.*);
            defer allocator.free(branch_path);
            try validateNode(allocator, diagnostics, entry.value_ptr, branch_path);
        }
    } else try diag.add(allocator, diagnostics, "invalid_schema", union_path, "{s} must be a list or tagged union map", .{union_path});
}

fn validateRange(allocator: std.mem.Allocator, diagnostics: *diag.List, range: *const val.Value, path_owned: []const u8) !void {
    defer allocator.free(path_owned);
    if (range.* != .mapping) return diag.add(allocator, diagnostics, "invalid_schema", path_owned, "{s} must be a map", .{path_owned});
    var it = range.mapping.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const child_path = try joinPath(allocator, path_owned, key);
        defer allocator.free(child_path);
        if (!oneOf(key, &.{ "min", "max", "gt", "lt" })) try diag.add(allocator, diagnostics, "invalid_schema", child_path, "{s} is not a valid range key", .{child_path});
        if (entry.value_ptr.* != .integer and entry.value_ptr.* != .float) try diag.add(allocator, diagnostics, "invalid_schema", child_path, "{s} must be a number", .{child_path});
    }
}

fn validateLength(allocator: std.mem.Allocator, diagnostics: *diag.List, length: *const val.Value, path_owned: []const u8) !void {
    defer allocator.free(path_owned);
    if (length.* != .mapping) return diag.add(allocator, diagnostics, "invalid_schema", path_owned, "{s} must be a map", .{path_owned});
    var it = length.mapping.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const child_path = try joinPath(allocator, path_owned, key);
        defer allocator.free(child_path);
        if (!oneOf(key, &.{ "min", "max" })) try diag.add(allocator, diagnostics, "invalid_schema", child_path, "{s} is not a valid length key", .{child_path});
        if (entry.value_ptr.* != .integer or entry.value_ptr.integer < 0) try diag.add(allocator, diagnostics, "invalid_schema", child_path, "{s} must be a non-negative integer", .{child_path});
    }
}

fn requireOnly(allocator: std.mem.Allocator, diagnostics: *diag.List, schema: *const val.Value, path: []const u8, allowed: []const []const u8, label: []const u8) !void {
    var it = schema.mapping.iterator();
    while (it.next()) |entry| if (!oneOf(entry.key_ptr.*, allowed)) {
        const child_path = try joinPath(allocator, path, entry.key_ptr.*);
        defer allocator.free(child_path);
        try diag.add(allocator, diagnostics, "invalid_schema", child_path, "{s} is not valid for {s}", .{ child_path, label });
    };
}

fn validateValueNode(schema: *const val.Value, value: ?*const val.Value, absent: bool) bool {
    if (schema.* == .string) return !absent and validateScalar(schema.string, value.?);
    if (schema.* != .mapping) return false;
    const map = &schema.mapping;

    if (hasMap(map, "optional") and semanticCount(map) == 1) return absent or validateValueNode(val.objectGet(schema, "optional").?, value, false);
    if (hasMap(map, "nullable") and semanticCount(map) == 1) return !absent and (value.?.* == .null_val or validateValueNode(val.objectGet(schema, "nullable").?, value, false));
    if (hasMap(map, "literal") and semanticCount(map) == 1) return !absent and scalarEqual(value.?, val.objectGet(schema, "literal").?);
    if (hasMap(map, "enum") and semanticCount(map) == 1) {
        if (absent) return false;
        const items = val.objectGet(schema, "enum") orelse return false;
        if (items.* != .sequence) return false;
        for (items.sequence) |*item| if (scalarEqual(value.?, item)) return true;
        return false;
    }
    if (hasMap(map, "union") and semanticCount(map) == 1) return !absent and validateUnionValue(val.objectGet(schema, "union").?, value.?);

    if (ordinaryCount(map) > 0) return validateObjectValue(schema, value, absent);
    if ((hasMap(map, "array") or hasMap(map, "list")) and !(hasMap(map, "array") and hasMap(map, "list"))) {
        if (absent or value.?.* != .sequence) return false;
        const child = val.objectGet(schema, if (hasMap(map, "array")) "array" else "list").?;
        if (!checkLength(val.objectGet(schema, "length"), value.?.sequence.len)) return false;
        for (value.?.sequence) |*item| if (!validateValueNode(child, item, false)) return false;
        return true;
    }
    if (hasMap(map, "record")) {
        if (absent or value.?.* != .mapping) return false;
        const child = val.objectGet(schema, "record").?;
        if (!checkLength(val.objectGet(schema, "length"), value.?.mapping.count())) return false;
        var it = value.?.mapping.iterator();
        while (it.next()) |entry| {
            if (val.objectGet(schema, "key")) |key_spec| if (val.objectGet(key_spec, "pattern")) |pattern| if (pattern.* == .string and !matchPattern(pattern.string, entry.key_ptr.*)) return false;
            if (!validateValueNode(child, entry.value_ptr, false)) return false;
        }
        return true;
    }
    if (hasMap(map, "type")) {
        if (absent) return false;
        const t = val.objectGet(schema, "type") orelse return false;
        if (t.* != .string or !validateScalar(t.string, value.?)) return false;
        if (!checkRange(val.objectGet(schema, "range"), value.?)) return false;
        if (val.objectGet(schema, "pattern")) |pattern| if (pattern.* != .string or value.?.* != .string or !matchPattern(pattern.string, value.?.string)) return false;
        const length_value: ?usize = switch (value.?.*) { .string => |s| s.len, .sequence => |items| items.len, .mapping => |m| m.count(), else => null };
        if (!checkLength(val.objectGet(schema, "length"), length_value)) return false;
        return true;
    }
    return validateObjectValue(schema, value, absent);
}

fn validateObjectValue(schema: *const val.Value, value: ?*const val.Value, absent: bool) bool {
    if (absent or value.?.* != .mapping) return false;
    const fields = val.objectGet(schema, "object") orelse schema;
    if (fields.* != .mapping) return false;
    var it = fields.mapping.iterator();
    while (it.next()) |entry| {
        if (std.mem.eql(u8, entry.key_ptr.*, "annotations")) continue;
        const child = val.objectGet(value.?, entry.key_ptr.*);
        if (!validateValueNode(entry.value_ptr, child, child == null)) return false;
    }
    const extra = if (val.objectGet(schema, "extra")) |e| e.* == .boolean and e.boolean else false;
    if (!extra) {
        var vit = value.?.mapping.iterator();
        while (vit.next()) |entry| if (val.objectGet(fields, entry.key_ptr.*) == null) return false;
    }
    return true;
}

fn validateUnionValue(union_value: *const val.Value, value: *const val.Value) bool {
    if (union_value.* == .sequence) {
        for (union_value.sequence) |*branch| if (validateValueNode(branch, value, false)) return true;
        return false;
    }
    if (union_value.* != .mapping or value.* != .mapping) return false;
    const tag = val.objectGet(union_value, "tag") orelse return false;
    const variants = val.objectGet(union_value, "variants") orelse return false;
    if (tag.* != .string or variants.* != .mapping) return false;
    const tag_value = val.objectGet(value, tag.string) orelse return false;
    if (tag_value.* != .string) return false;
    const variant = val.objectGet(variants, tag_value.string) orelse return false;
    return validateValueNode(variant, value, false);
}

fn validateScalar(name: []const u8, value: *const val.Value) bool {
    if (std.mem.eql(u8, name, "any")) return true;
    if (std.mem.eql(u8, name, "string")) return value.* == .string;
    if (std.mem.eql(u8, name, "number")) return value.* == .integer or value.* == .float;
    if (std.mem.eql(u8, name, "integer")) return value.* == .integer;
    if (std.mem.eql(u8, name, "boolean")) return value.* == .boolean;
    if (std.mem.eql(u8, name, "null")) return value.* == .null_val;
    return false;
}

fn checkRange(range: ?*const val.Value, value: *const val.Value) bool {
    const r = range orelse return true;
    if (r.* != .mapping) return false;
    const n = numberValue(value) orelse return false;
    if (numberValue(val.objectGet(r, "min") orelse undefinedValue())) |min| if (n < min) return false;
    if (numberValue(val.objectGet(r, "max") orelse undefinedValue())) |max| if (n > max) return false;
    if (numberValue(val.objectGet(r, "gt") orelse undefinedValue())) |gt| if (n <= gt) return false;
    if (numberValue(val.objectGet(r, "lt") orelse undefinedValue())) |lt| if (n >= lt) return false;
    return true;
}

fn checkLength(length: ?*const val.Value, actual: ?usize) bool {
    const l = length orelse return true;
    const n = actual orelse return false;
    if (l.* != .mapping) return false;
    if (integerValue(val.objectGet(l, "min") orelse undefinedValue())) |min| if (n < @as(usize, @intCast(min))) return false;
    if (integerValue(val.objectGet(l, "max") orelse undefinedValue())) |max| if (n > @as(usize, @intCast(max))) return false;
    return true;
}

fn numberValue(value: *const val.Value) ?f64 {
    return switch (value.*) { .integer => |i| @floatFromInt(i), .float => |f| f, else => null };
}

fn integerValue(value: *const val.Value) ?i64 {
    return switch (value.*) { .integer => |i| i, else => null };
}

fn undefinedValue() *const val.Value {
    const static = struct { const v = val.Value{ .null_val = {} }; };
    return &static.v;
}

fn scalarEqual(a: *const val.Value, b: *const val.Value) bool {
    return switch (b.*) {
        .null_val => a.* == .null_val,
        .boolean => |x| a.* == .boolean and a.boolean == x,
        .integer => |x| a.* == .integer and a.integer == x,
        .float => |x| a.* == .float and a.float == x,
        .string => |x| a.* == .string and std.mem.eql(u8, a.string, x),
        else => false,
    };
}

fn isScalar(s: []const u8) bool { return oneOf(s, &scalar_names); }
fn isReserved(s: []const u8) bool { return oneOf(s, &reserved_keys); }
fn isForbidden(s: []const u8) bool { return oneOf(s, &forbidden_operators); }
fn oneOf(s: []const u8, items: []const []const u8) bool { for (items) |item| if (std.mem.eql(u8, s, item)) return true; return false; }
fn hasMap(map: *const val.Mapping, key: []const u8) bool { return map.getPtr(key) != null; }
fn hasValue(value: *const val.Value, key: []const u8) bool { return val.objectGet(value, key) != null; }
fn semanticCount(map: *const val.Mapping) usize {
    var n: usize = 0;
    var it = map.iterator();
    while (it.next()) |entry| {
        if (!std.mem.eql(u8, entry.key_ptr.*, "annotations")) n += 1;
    }
    return n;
}
fn ordinaryCount(map: *const val.Mapping) usize {
    var n: usize = 0;
    var it = map.iterator();
    while (it.next()) |entry| {
        if (!std.mem.eql(u8, entry.key_ptr.*, "annotations") and !isReserved(entry.key_ptr.*)) n += 1;
    }
    return n;
}
fn isScalarLiteral(value: *const val.Value) bool { return switch (value.*) { .null_val, .boolean, .integer, .float, .string => true, else => false }; }

fn joinPath(allocator: std.mem.Allocator, path: []const u8, key: []const u8) ![]u8 { return std.fmt.allocPrint(allocator, "{s}.{s}", .{ path, key }); }
fn addPath(allocator: std.mem.Allocator, diagnostics: *diag.List, path: []const u8, key: []const u8, code: []const u8, comptime fmt: []const u8, args: anytype) !void {
    _ = args;
    const child_path = try joinPath(allocator, path, key);
    defer allocator.free(child_path);
    try diag.add(allocator, diagnostics, code, child_path, fmt, .{child_path});
}

fn validPattern(pattern: []const u8) bool {
    var i: usize = 0;
    var bracket = false;
    var paren_depth: usize = 0;
    while (i < pattern.len) : (i += 1) switch (pattern[i]) {
        '\\' => i += 1,
        '[' => {
            if (bracket) return false;
            bracket = true;
        },
        ']' => {
            if (!bracket) return false;
            bracket = false;
        },
        '(' => {
            if (!bracket) paren_depth += 1;
        },
        ')' => {
            if (!bracket) {
                if (paren_depth == 0) return false;
                paren_depth -= 1;
            }
        },
        else => {},
    };
    return !bracket and paren_depth == 0;
}

fn matchPattern(pattern: []const u8, text: []const u8) bool {
    if (!validPattern(pattern)) return false;
    if (pattern.len >= 4 and pattern[0] == '^' and pattern[1] == '[') {
        const close = std.mem.indexOfScalarPos(u8, pattern, 2, ']') orelse return false;
        const class = pattern[2..close];
        const quant = if (close + 1 < pattern.len) pattern[close + 1] else 0;
        const anchored_end = pattern[pattern.len - 1] == '$';
        if (!anchored_end) return false;
        const min: usize = if (quant == '+') 1 else 0;
        if (text.len < min) return false;
        for (text) |c| if (!classContains(class, c)) return false;
        return true;
    }
    if (pattern.len >= 2 and pattern[0] == '^' and pattern[pattern.len - 1] == '$') return std.mem.eql(u8, pattern[1 .. pattern.len - 1], text);
    return std.mem.indexOf(u8, text, pattern) != null;
}

fn classContains(class: []const u8, c: u8) bool {
    var i: usize = 0;
    while (i < class.len) : (i += 1) {
        if (i + 2 < class.len and class[i + 1] == '-') {
            if (c >= class[i] and c <= class[i + 2]) return true;
            i += 2;
        } else if (class[i] == c) return true;
    }
    return false;
}
