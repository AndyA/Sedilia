const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Value = std.json.Value;

const bytes = @import("../support/bytes.zig");
const IbexWriter = @import("../IbexWriter.zig");
const sortValues = @import("./value.zig").sortValues;

test "ibex ordering" {
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
        &.{ .integer = std.math.minInt(i64) },
        &.{ .float = 0.3 },
        &.{ .integer = 1 },
        &.{ .float = 1.00001 },
        &.{ .integer = std.math.maxInt(i64) },
        &.{ .float = 3.1414e+100 },
        &.{ .array = ar_empty },
        &.{ .array = ar1 },
        &.{ .array = ar2 },
        &.{ .array = ar3 },
        &.{ .object = obj_empty },
        &.{ .object = obj1 },
        &.{ .object = obj2 },
        &.{ .object = obj3 },
    };

    var ibex: [cases.len][]const u8 = undefined;
    for (cases, 0..) |c, i| {
        var writer = std.Io.Writer.Allocating.init(gpa);
        defer writer.deinit();
        var bw = bytes.ByteWriter{ .writer = &writer.writer };
        var iw = IbexWriter{ .w = &bw };
        try iw.write(c);
        ibex[i] = try writer.toOwnedSlice();
    }
    defer for (ibex) |ibx| gpa.free(ibx);

    const shuffled = try gpa.dupe([]const u8, &ibex);
    defer gpa.free(shuffled);
    rand.shuffle([]const u8, shuffled);

    const Context = struct {
        pub fn lt(_: @This(), lhs: []const u8, rhs: []const u8) bool {
            return std.mem.order(u8, lhs, rhs) == .lt;
        }
    };

    std.mem.sort([]const u8, shuffled, Context{}, Context.lt);

    try std.testing.expectEqualDeep(&ibex, shuffled);
}

test {
    _ = @import("./value.zig");
}
