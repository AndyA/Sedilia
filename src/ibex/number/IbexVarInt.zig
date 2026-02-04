const std = @import("std");
const assert = std.debug.assert;

const ibex = @import("../ibex.zig");
const b = @import("../bytes.zig");
const IbexError = ibex.IbexError;
const ByteReader = b.ByteReader;
const ByteWriter = b.ByteWriter;

const IbexVarInt = @This();

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
    for (LIMITS, 1..) |limit, len| {
        if (abs < limit)
            return len;
    }
    return MAX_VALUE_BYTES + 1;
}

test encodedLength {
    for (test_cases) |tc| {
        try std.testing.expectEqual(tc.buf.len, IbexVarInt.encodedLength(tc.want));
    }
}

fn repLength(tag: u8) usize {
    if (tag >= LINEAR_HI)
        return tag - LINEAR_HI + 1
    else if (tag < LINEAR_LO)
        return LINEAR_LO - tag
    else
        return 0;
}

pub fn skip(r: *ByteReader) !void {
    try r.skip(repLength(try r.next()));
}

test skip {
    for (test_cases) |tc| {
        var r = ByteReader{ .buf = tc.buf };
        try IbexVarInt.skip(&r);
        try std.testing.expectEqual(tc.buf.len, r.pos);
    }
}

fn readBytes(r: *ByteReader, byte_count: usize, comptime flip: u8) IbexError!i64 {
    assert(byte_count <= MAX_VALUE_BYTES);
    var acc: i64 = 0;
    for (0..byte_count) |_| {
        acc = (acc << 8) + (try r.next() ^ flip);
    }
    if (acc < 0 or acc > MAX_ENCODED)
        return IbexError.SyntaxError;
    return acc;
}

pub fn read(r: *ByteReader) IbexError!i64 {
    const nb = try r.next();
    const byte_count = repLength(nb);
    if (nb >= LINEAR_HI) {
        return LIMITS[byte_count - 1] + try readBytes(r, byte_count, 0x00);
    } else if (nb < LINEAR_LO) {
        return ~(LIMITS[byte_count - 1] + try readBytes(r, byte_count, 0xff));
    } else {
        return @as(i64, @intCast(nb)) - BIAS;
    }
}

test read {
    for (test_cases) |tc| {
        var r = ByteReader{ .buf = tc.buf };
        try std.testing.expectEqual(tc.want, IbexVarInt.read(&r));
        try std.testing.expectEqual(tc.buf.len, r.pos);
    }
}

fn writeBytes(w: *ByteWriter, byte_count: usize, value: i64) IbexError!void {
    assert(byte_count <= MAX_VALUE_BYTES);
    for (0..byte_count) |i| {
        const pos: u6 = @intCast(byte_count - 1 - i);
        const byte: u8 = @intCast((value >> (pos * 8)) & 0xff);
        try w.put(byte);
    }
}

pub fn write(w: *ByteWriter, value: i64) IbexError!void {
    const byte_count = encodedLength(value) - 1;
    if (byte_count == 0) {
        try w.put(@intCast(value + BIAS));
    } else if (value >= 0) {
        try w.put(@intCast(byte_count - 1 + LINEAR_HI));
        try writeBytes(w, byte_count, value - LIMITS[byte_count - 1]);
    } else {
        try w.put(@intCast(LINEAR_LO - byte_count));
        try writeBytes(w, byte_count, value + LIMITS[byte_count - 1]);
    }
}

test write {
    for (test_cases) |tc| {
        var buf: [9]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buf);
        var w = ByteWriter{ .writer = &writer };
        try IbexVarInt.write(&w, tc.want);
        try std.testing.expectEqualDeep(tc.buf, writer.buffered());
    }
}

test "round trip" {
    var buf: [9]u8 = undefined;
    for (0..140000) |offset| {
        const value = @as(i64, @intCast(offset)) - 70000;
        var writer = std.Io.Writer.fixed(&buf);
        var w = ByteWriter{ .writer = &writer };
        try IbexVarInt.write(&w, value);
        const output = writer.buffered();
        try std.testing.expectEqual(output.len, IbexVarInt.encodedLength(value));
        var r = ByteReader{ .buf = output };
        const got = IbexVarInt.read(&r);
        try std.testing.expectEqual(value, got);
    }
}

const TestCase = struct { buf: []const u8, want: i64 };
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
