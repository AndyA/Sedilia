const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const Value = std.json.Value;

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

/// Compare two values according to CouchDB ordering rules
pub fn compareValues(a: *const Value, b: *const Value) std.math.Order {
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

/// Sort a slice of values according to CouchDB ordering rules
pub fn sortValues(items: []*const Value) void {
    const Context = struct {
        pub fn lt(_: @This(), lhs: *const Value, rhs: *const Value) bool {
            return compareValues(lhs, rhs) == .lt;
        }
    };

    std.mem.sort(*const Value, items, Context{}, Context.lt);
}

test sortValues {
    const gpa = std.testing.allocator;

    var prng: std.Random.DefaultPrng = .init(123);
    const rand = prng.random();

    var ar_empty: std.json.Array = .init(gpa);
    defer ar_empty.deinit();

    var ar1: std.json.Array = .init(gpa);
    defer ar1.deinit();
    try ar1.append(.{ .float = 3 });

    var ar2 = try ar1.clone();
    defer ar2.deinit();
    try ar2.append(.{ .string = "Hello" });

    var ar3 = try ar1.clone();
    defer ar3.deinit();
    try ar3.append(.{ .integer = -300 });

    var obj_empty: std.json.ObjectMap = .init(gpa);
    defer obj_empty.deinit();

    var obj1: std.json.ObjectMap = .init(gpa);
    defer obj1.deinit();
    try obj1.put("a", .{ .integer = 1 });

    var obj2: std.json.ObjectMap = .init(gpa);
    defer obj2.deinit();
    try obj2.put("a", .{ .array = ar1 });

    var obj3: std.json.ObjectMap = .init(gpa);
    defer obj3.deinit();
    try obj3.put("b", .{ .null = {} });

    const cases = &[_]*const Value{
        &.{ .null = {} },
        &.{ .bool = false },
        &.{ .bool = true },
        &.{ .string = "aaa" },
        &.{ .string = "aab" },
        &.{ .float = 0.3 },
        &.{ .integer = 1 },
        &.{ .float = 1.00001 },
        &.{ .array = ar_empty },
        &.{ .array = ar1 },
        &.{ .array = ar2 },
        &.{ .array = ar3 },
        &.{ .object = obj_empty },
        &.{ .object = obj1 },
        &.{ .object = obj2 },
        &.{ .object = obj3 },
    };

    const shuffled = try gpa.dupe(*const Value, cases);
    defer gpa.free(shuffled);

    rand.shuffle(*const Value, shuffled);
    sortValues(shuffled);

    try std.testing.expectEqualDeep(cases, shuffled);
}
