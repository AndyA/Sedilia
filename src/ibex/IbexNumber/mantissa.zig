const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const ibex = @import("../ibex.zig");
const IbexError = ibex.IbexError;
const bytes = @import("../bytes.zig");
const ByteReader = bytes.ByteReader;
const ByteWriter = bytes.ByteWriter;

fn sizeInBytes(comptime T: type, mant: T) u16 {
    const sig_bits = @typeInfo(T).int.bits - @ctz(mant);
    return (sig_bits + 6) / 7;
}

pub fn mantissaLength(comptime T: type, mant: T) usize {
    return @max(1, sizeInBytes(T, mant));
}

pub fn writeMantissa(comptime T: type, w: *ByteWriter, mantissa: T) !void {
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
    const gpa = std.testing.allocator;
    inline for (general_cases) |tc| {
        var w = ByteWriter{ .gpa = gpa };
        defer w.deinit();
        try writeMantissa(tc.T, &w, tc.mant);
        // std.debug.print("T={any}, m={x} encoded={any}\n", .{ tc.T, tc.mant, w.slice() });
        try std.testing.expectEqual(w.buf.items.len, mantissaLength(tc.T, tc.mant));
        try std.testing.expectEqualDeep(tc.bytes, w.slice());
    }
}

pub fn readMantissa(comptime T: type, r: *ByteReader) !T {
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
                return IbexError.InvalidData;
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
