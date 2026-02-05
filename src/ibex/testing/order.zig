const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const Value = std.json.Value;

// null,
// bool: bool,
// integer: i64,
// float: f64,
// number_string: []const u8,
// string: []const u8,
// array: Array,
// object: ObjectMap,

/// Get the CouchDB ordering of a Value's type
fn valueType(v: *const Value) u8 {
    return switch (v.*) {
        .null => 0,
        .bool => |b| if (b) 2 else 1,
        .string => 3,
        .integer, .float => 4,
        .array => 5,
        .object => 6,
        else => unreachable,
    };
}

fn numValue(v: *const Value) f128 {
    return switch (v.*) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => unreachable,
    };
}

fn compareArrays(a: *const Value, b: *const Value) std.math.Order {
    const aa = a.array.items;
    const ab = b.array.items;
    const len = @min(aa.len, ab.len);
    for (aa[0..len], ab[0..len]) |ia, ib| {
        const cmp = compareValues(&ia, &ib);
        if (cmp != .eq) return cmp;
    }
    return std.math.order(aa.len, ab.len);
}

fn compareObjects(a: *const Value, b: *const Value) std.math.Order {
    const oka = a.object.keys();
    const okb = b.object.keys();
    const ova = a.object.values();
    const ovb = b.object.values();
    const len = @min(oka.len, okb.len);
    for (0..len) |i| {
        const kcmp = std.mem.order(u8, oka[i], okb[i]);
        if (kcmp != .eq) return kcmp;
        const vcmp = compareValues(&ova[i], &ovb[i]);
        if (vcmp != .eq) return vcmp;
    }
    return std.math.order(oka.len, okb.len);
}

fn compareValues(a: *const Value, b: *const Value) std.math.Order {
    const ta = valueType(a);
    const tb = valueType(b);
    if (ta != tb)
        return std.math.order(ta, tb);
    return switch (a.*) {
        .null => .eq,
        .string => std.mem.order(u8, a.string, b.string),
        .integer, .float => std.math.order(numValue(a), numValue(b)),
        .array => compareArrays(a, b),
        .object => compareObjects(a, b),
        else => unreachable,
    };
}

test compareValues {
    const gpa = std.testing.allocator;

    var prng: std.Random.DefaultPrng = .init(123);
    const rand = prng.random();

    const cases = &[_]*const Value{
        &.{ .null = {} },
        &.{ .bool = false },
        &.{ .bool = true },
        &.{ .string = "aaa" },
        &.{ .string = "aab" },
        &.{ .float = 0.3 },
        &.{ .integer = 1 },
        &.{ .float = 1.00001 },
    };

    const shuffled = try gpa.dupe(*const Value, cases);
    defer gpa.free(shuffled);

    rand.shuffle(*const Value, shuffled);

    const Context = struct {
        pub fn lt(_: @This(), lhs: *const Value, rhs: *const Value) bool {
            return compareValues(lhs, rhs) == .lt;
        }
    };

    std.mem.sort(*const Value, shuffled, Context{}, Context.lt);

    try std.testing.expectEqualDeep(cases, shuffled);
}
