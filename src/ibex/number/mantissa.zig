const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const ibex = @import("../support/types.zig");
const IbexError = ibex.IbexError;
const bytes = @import("../support/bytes.zig");
const ByteReader = bytes.ByteReader;
const ByteWriter = bytes.ByteWriter;

fn sizeInBytes(comptime T: type, mant: T) u16 {
    const sig_bits = @typeInfo(T).int.bits - @ctz(mant);
    return (sig_bits + 6) / 7;
}

pub fn mantissaLength(comptime T: type, mant: T) usize {
    return @max(1, sizeInBytes(T, mant));
}

pub fn writeMantissa(comptime T: type, w: *ByteWriter, mantissa: T) IbexError!void {
    const info = @typeInfo(T).int;
    assert(info.signedness == .unsigned);
    const len = sizeInBytes(T, mantissa);

    if (len == 0)
        return w.put(0x00);

    var shift: i32 = @as(i32, @intCast(info.bits)) - 8;

    const mant: @Int(.unsigned, @max(8, info.bits)) = @intCast(mantissa);

    for (0..len) |i| {
        const part = if (shift >= 0)
            mant >> @intCast(shift)
        else
            mant << @intCast(-shift);
        var byte = part & 0xfe;
        if (i < len - 1) byte |= 1;
        try w.put(@intCast(byte));
        shift -= 7;
    }
}

const TestCase = struct {
    T: type,
    mant: comptime_int,
    bytes: []const u8,
};

const general_cases = &[_]TestCase{
    .{ .T = u16, .mant = 0, .bytes = &.{0x00} },
    .{ .T = u8, .mant = 0x80, .bytes = &.{0x80} },
    .{ .T = u8, .mant = 0xff, .bytes = &.{ 0xff, 0x80 } },
    .{ .T = u8, .mant = 0x81, .bytes = &.{ 0x81, 0x80 } },
    .{ .T = u9, .mant = 0x102, .bytes = &.{ 0x81, 0x80 } },
    .{ .T = u1, .mant = 0x1, .bytes = &.{0x80} },
};

test writeMantissa {
    inline for (general_cases) |tc| {
        var buf: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buf);
        var w = ByteWriter{ .writer = &writer };
        try writeMantissa(tc.T, &w, tc.mant);
        const output = writer.buffered();
        try std.testing.expectEqual(output.len, mantissaLength(tc.T, tc.mant));
        try std.testing.expectEqualDeep(tc.bytes, output);
    }
}

pub fn readMantissa(comptime T: type, r: *ByteReader) IbexError!T {
    const info = @typeInfo(T).int;
    assert(info.signedness == .unsigned);

    // We need at least 8 bits so we can work with complete bytes
    const Adequate = @Int(.unsigned, @max(8, info.bits));
    var mant: Adequate = 0;
    const init_shift: i32 = @as(i32, @intCast(info.bits)) - 8;
    var shift = init_shift;
    while (true) : (shift -= 7) {
        const nb = try r.next();
        const bits: Adequate = @intCast(nb & 0xfe);
        // std.debug.print("{any} shift={d}\n", .{ @TypeOf(mant), shift });
        if (shift > -8)
            mant |= if (shift >= 0)
                bits << @intCast(shift)
            else
                bits >> @intCast(-shift);
        if (nb & 0x01 == 0) {
            // Detect non-canonical encoding
            if (nb == 0 and shift != init_shift)
                return IbexError.SyntaxError;
            break;
        }
    }

    return @intCast(mant);
}

const read_cases = &[_]TestCase{
    .{ .T = u16, .mant = 0xffff, .bytes = &.{ 0xff, 0xff, 0xfe } },
    .{ .T = u16, .mant = 0xffff, .bytes = &.{ 0xff, 0xff, 0xff, 0xfe } },
    .{ .T = u16, .mant = 0xffff, .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xfe } },
    .{ .T = u16, .mant = 0xffff, .bytes = &.{ 0xff, 0xff, 0xc0 } },
    .{ .T = u16, .mant = 0xffff, .bytes = &.{ 0xff, 0xff, 0xfe } },
};

test readMantissa {
    inline for (general_cases ++ read_cases) |tc| {
        // std.debug.print("{any}\n", .{tc});
        var r = ByteReader{ .buf = tc.bytes };
        const got = try readMantissa(tc.T, &r);
        try std.testing.expectEqual(tc.mant, got);
    }
}

pub fn mantissaBits(r: *ByteReader) IbexError!usize {
    var bits: usize = 0;
    while (true) : (bits += 7) {
        const nb = try r.next();
        if (nb & 0x01 == 0)
            return bits + 8 - @ctz(nb);
    }
}

const BitsCase = struct {
    want: usize,
    bytes: []const u8,
};

const bits_cases = &[_]BitsCase{
    .{ .want = 0, .bytes = &.{0x00} },
    .{ .want = 1, .bytes = &.{0x80} },
    .{ .want = 7, .bytes = &.{0x02} },
    .{ .want = 14, .bytes = &.{ 0xff, 0xfe } },
    .{ .want = 14, .bytes = &.{ 0x01, 0x02 } },
};

test mantissaBits {
    for (bits_cases) |tc| {
        var r = ByteReader{ .buf = tc.bytes };
        try std.testing.expectEqual(tc.want, mantissaBits(&r));
    }
}

pub fn skipMantissa(r: *ByteReader) IbexError!void {
    while (true) {
        const nb = try r.next();
        if (nb & 0x01 == 0)
            break;
    }
}

test skipMantissa {
    inline for (general_cases ++ read_cases) |tc| {
        var r = ByteReader{ .buf = tc.bytes };
        try skipMantissa(&r);
        try std.testing.expectEqual(tc.bytes.len, r.pos);
    }
}
