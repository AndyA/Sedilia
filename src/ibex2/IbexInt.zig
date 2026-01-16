const std = @import("std");
const assert = std.debug.assert;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const ibex = @import("./ibex.zig");
const IbexError = ibex.IbexError;
const IbexInt = @This();

const BIAS = 0x80;
const LINEAR_LO = 0x08;
const LINEAR_HI = 0xf8;
const MAX_ENCODED: i64 = 0x7efefefefefefe87;
const MAX_VALUE_BYTES = 8;

// The largest value that can be encoded for each number of additional bytes
const LIMITS: [MAX_VALUE_BYTES]i64 = blk: {
    var limits: [MAX_VALUE_BYTES]i64 = undefined;

    var limit: i64 = LINEAR_HI - BIAS;
    limits[0] = limit;
    for (1..MAX_VALUE_BYTES) |len| {
        limit += @as(i64, 1) << (@as(u6, @intCast(len)) * 8);
        limits[len] = limit;
    }

    break :blk limits;
};

pub fn encodedLength(value: i64) usize {
    const abs = if (value < 0) ~value else value;
    inline for (LIMITS, 1..) |limit, len| {
        if (abs < limit)
            return len;
    }
    return MAX_VALUE_BYTES + 1;
}

test encodedLength {
    for (test_cases) |tc| {
        try std.testing.expectEqual(tc.buf.len, IbexInt.encodedLength(tc.want));
    }
}

fn repLength(tag: u8) usize {
    if (tag >= LINEAR_HI)
        return tag - LINEAR_HI + 1
    else if (tag < LINEAR_LO)
        return LINEAR_LO - tag
    else
        return 1;
}

fn readBytes(r: *Reader, byte_count: usize, comptime flip: bool) !i64 {
    assert(byte_count <= MAX_VALUE_BYTES);
    var acc: u64 = try r.takeVarInt(u64, .big, byte_count);
    if (flip)
        acc ^= switch (byte_count) {
            8 => ~@as(u64, 0),
            else => (@as(u64, 1) << @as(u6, @intCast(byte_count * 8))) - 1,
        };
    if (acc > MAX_ENCODED)
        return IbexError.InvalidData;
    return @intCast(acc);
}

pub fn read(r: *Reader) !i64 {
    const nb = try r.takeByte();
    const byte_count = repLength(nb);
    if (nb >= LINEAR_HI) {
        return LIMITS[byte_count - 1] + try readBytes(r, byte_count, false);
    } else if (nb < LINEAR_LO) {
        return ~(LIMITS[byte_count - 1] + try readBytes(r, byte_count, true));
    } else {
        return @as(i64, @intCast(nb)) - BIAS;
    }
}

test read {
    for (test_cases) |tc| {
        var r = std.Io.Reader.fixed(tc.buf);
        try std.testing.expectEqual(tc.want, IbexInt.read(&r));
        try std.testing.expectError(error.EndOfStream, r.takeByte());
    }
}

fn writeBytes(w: *Writer, byte_count: usize, value: i64) !void {
    assert(byte_count <= MAX_VALUE_BYTES);
    for (0..byte_count) |i| {
        const pos: u6 = @intCast(byte_count - 1 - i);
        const byte: u8 = @intCast((value >> (pos * 8)) & 0xff);
        try w.writeByte(byte);
    }
}

pub fn write(w: *Writer, value: i64) !void {
    const byte_count = encodedLength(value) - 1;
    if (byte_count == 0) {
        try w.writeByte(@intCast(value + BIAS));
    } else if (value >= 0) {
        try w.writeByte(@intCast(byte_count - 1 + LINEAR_HI));
        try writeBytes(w, byte_count, value - LIMITS[byte_count - 1]);
    } else {
        try w.writeByte(@intCast(LINEAR_LO - byte_count));
        try writeBytes(w, byte_count, value + LIMITS[byte_count - 1]);
    }
}

test write {
    const gpa = std.testing.allocator;
    for (test_cases) |tc| {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        var w = Writer.Allocating.fromArrayList(gpa, &buf);
        defer w.deinit();
        try IbexInt.write(&w.writer, tc.want);
        var output = w.toArrayList();
        defer output.deinit(gpa);
        try std.testing.expectEqualDeep(tc.buf, output.items);
    }
}

test "round trip" {
    const gpa = std.testing.allocator;
    for (0..140000) |offset| {
        const value = @as(i64, @intCast(offset)) - 70000;
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        var w = Writer.Allocating.fromArrayList(gpa, &buf);
        defer w.deinit();
        try IbexInt.write(&w.writer, value);

        var output = w.toArrayList();
        defer output.deinit(gpa);

        var r = Reader.fixed(output.items);

        // var r = ByteReader{ .buf = w.slice() };
        const got = IbexInt.read(&r);
        try std.testing.expectEqual(value, got);
    }
}

const TestCase = struct { buf: []const u8, flip: u8 = 0x00, want: i64 };
const test_cases = &[_]TestCase{
    // .{
    //     .buf = &.{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
    //     .want = -18519084246547628408,
    // },
    .{
        .buf = &.{ 0x00, 0x81, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x78 },
        .want = std.math.minInt(i64),
    },
    .{
        .buf = &.{ 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
        .want = -72340172838076793,
    },
    .{
        .buf = &.{ 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        .want = -72340172838076792,
    },
    .{ .buf = &.{ 0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = -282578800148857 },
    .{ .buf = &.{ 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = -282578800148856 },
    .{ .buf = &.{ 0x02, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = -1103823438201 },
    .{ .buf = &.{ 0x03, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = -1103823438200 },
    .{ .buf = &.{ 0x03, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = -4311810425 },
    .{ .buf = &.{ 0x04, 0x00, 0x00, 0x00, 0x00 }, .want = -4311810424 },
    .{ .buf = &.{ 0x04, 0xff, 0xff, 0xff, 0xff }, .want = -16843129 },
    .{ .buf = &.{ 0x05, 0x00, 0x00, 0x00 }, .want = -16843128 },
    .{ .buf = &.{ 0x05, 0xff, 0xff, 0xff }, .want = -65913 },
    .{ .buf = &.{ 0x06, 0x00, 0x00 }, .want = -65912 },
    .{ .buf = &.{ 0x06, 0xff, 0xfe }, .want = -378 },
    .{ .buf = &.{ 0x06, 0xff, 0xff }, .want = -377 },
    .{ .buf = &.{ 0x07, 0x00 }, .want = -376 },
    .{ .buf = &.{ 0x07, 0xff }, .want = -121 },
    .{ .buf = &.{0x08}, .want = -120 },
    .{ .buf = &.{0x7f}, .want = -1 },
    .{ .buf = &.{0x80}, .want = 0 },
    .{ .buf = &.{0x81}, .want = 1 },
    .{ .buf = &.{0xf7}, .want = 119 },
    .{ .buf = &.{ 0xf8, 0x00 }, .want = 120 },
    .{ .buf = &.{ 0xf8, 0xff }, .want = 375 },
    .{ .buf = &.{ 0xf9, 0x00, 0x00 }, .want = 376 },
    .{ .buf = &.{ 0xf9, 0x00, 0x01 }, .want = 377 },
    .{ .buf = &.{ 0xf9, 0x01, 0x00 }, .want = 632 },
    .{ .buf = &.{ 0xf9, 0xff, 0xff }, .want = 65911 },
    .{ .buf = &.{ 0xfa, 0x00, 0x00, 0x00 }, .want = 65912 },
    .{ .buf = &.{ 0xfa, 0xff, 0xff, 0xff }, .want = 16843127 },
    .{ .buf = &.{ 0xfb, 0x00, 0x00, 0x00, 0x00 }, .want = 16843128 },
    .{ .buf = &.{ 0xfb, 0xff, 0xff, 0xff, 0xff }, .want = 4311810423 },
    .{ .buf = &.{ 0xfc, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = 4311810424 },
    .{ .buf = &.{ 0xfc, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = 1103823438199 },
    .{ .buf = &.{ 0xfd, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = 1103823438200 },
    .{ .buf = &.{ 0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = 282578800148855 },
    .{ .buf = &.{ 0xfe, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = 282578800148856 },
    .{
        .buf = &.{ 0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
        .want = 72340172838076791,
    },
    .{
        .buf = &.{ 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        .want = 72340172838076792,
    },
    .{
        .buf = &.{ 0xff, 0x7e, 0xfe, 0xfe, 0xfe, 0xfe, 0xfe, 0xfe, 0x87 },
        .want = std.math.maxInt(i64),
    },
    // .{
    //     .buf = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
    //     .want = 18519084246547628407,
    // },
};
