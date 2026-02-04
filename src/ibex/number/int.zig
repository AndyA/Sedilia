const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const ibex = @import("../ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const bytes = @import("../bytes.zig");
const ByteReader = bytes.ByteReader;
const ByteWriter = bytes.ByteWriter;
const IbexInt = @import("../IbexInt.zig");
const mantissa = @import("./mantissa.zig");

pub fn intCodec(comptime T: type) type {
    const info = @typeInfo(T).int;
    const min_int = math.minInt(T);
    const max_exp = switch (info.signedness) {
        .signed => info.bits - 1,
        .unsigned => info.bits,
    };
    const UT = @Int(.unsigned, info.bits);

    return struct {
        pub fn encodedLength(value: T) usize {
            if (value == 0)
                return 1;
            if (value < 0) {
                if (value == min_int)
                    return 1 + IbexInt.encodedLength(max_exp) + 1;
                return encodedLength(-value);
            }
            const msb = info.bits - @clz(value) - 1; // drop MSB
            const byte_count = (msb - @ctz(value) + 6) / 7;
            return 1 + IbexInt.encodedLength(msb) + @max(1, byte_count);
        }

        fn writeInt(w: *ByteWriter, value: T) IbexError!void {
            const msb = info.bits - @clz(value) - 1; // drop MSB
            try IbexInt.write(w, msb); // exp

            if (msb == 0)
                return mantissa.writeMantissa(UT, w, 0);

            const mant = @as(UT, @intCast(value)) << @intCast(info.bits - msb);
            try mantissa.writeMantissa(UT, w, mant);
        }

        pub fn write(w: *ByteWriter, value: T) IbexError!void {
            if (value == 0) {
                try w.put(@intFromEnum(IbexTag.NumPosZero));
            } else if (value < 0) {
                try w.put(@intFromEnum(IbexTag.NumNeg));
                w.negate();
                defer w.negate();
                if (value == min_int) {
                    // Special case minInt
                    try IbexInt.write(w, max_exp);
                    try w.put(0x00);
                } else {
                    try writeInt(w, -value);
                }
            } else {
                try w.put(@intFromEnum(IbexTag.NumPos));
                try writeInt(w, value);
            }
        }

        fn readIntBits(r: *ByteReader, exp: i64) IbexError!T {
            if (exp >= max_exp)
                return IbexError.Overflow;
            const mant = try mantissa.readMantissa(UT, r);
            const int = if (exp == 0) 0 else mant >> @intCast(info.bits - exp);
            return @intCast(int | (@as(UT, 1) << @intCast(exp)));
        }

        fn readPosInt(r: *ByteReader) IbexError!T {
            const exp = try IbexInt.read(r);
            return readIntBits(r, exp);
        }

        fn readNegInt(r: *ByteReader) IbexError!T {
            if (info.signedness == .unsigned)
                return IbexError.Overflow;
            r.negate();
            defer r.negate();
            const exp = try IbexInt.read(r);
            if (exp == max_exp) {
                const nb = try r.next();
                return switch (nb) {
                    0x00 => min_int,
                    else => IbexError.Overflow,
                };
            }
            return -try readIntBits(r, exp);
        }

        pub fn readFromTag(r: *ByteReader, tag: IbexTag) IbexError!T {
            return switch (tag) {
                .NumPosZero, .NumNegZero => 0,
                .NumPos => readPosInt(r),
                .NumNeg => readNegInt(r),
                .NumNegInf, .NumPosInf => IbexError.Overflow,
                .NumNegNaN, .NumPosNaN => IbexError.Overflow,
                else => IbexError.TypeMismatch,
            };
        }

        pub fn read(r: *ByteReader) IbexError!T {
            const nb = try r.next();
            return readFromTag(r, @enumFromInt(nb));
        }
    };
}

const tt = @import("./test_tools.zig");

fn TV(comptime T: type) type {
    return tt.TestVec(T, 100);
}

fn intTestVector(comptime T: type) TV(T) {
    const min_int = math.minInt(T);
    const max_int = math.maxInt(T);
    const info = @typeInfo(T).int;
    const BT = @Int(info.signedness, info.bits + 1);
    var tv = TV(T){};

    var small: BT = 0;
    while (small < @min(5, max_int)) : (small += 1) {
        tv.put(@intCast(small));
        tv.put(@intCast(max_int - small));
        if (info.signedness == .signed) {
            tv.put(@intCast(-small));
            tv.put(@intCast(min_int + small));
        }
    }

    // std.debug.print("{any}: {any}\n", .{ T, tv.slice() });

    return tv;
}

test intCodec {
    // const bit_lengths = [_]usize{ 8, 16 };
    const bit_lengths = //
        [_]usize{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 } ++ //
        [_]usize{ 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 1024 };
    const signs = [_]std.builtin.Signedness{
        .unsigned,
        .signed,
    };

    inline for (bit_lengths) |bits| {
        inline for (signs) |signedness| {
            const T = @Int(signedness, bits);
            // std.debug.print("=== {any} ===\n", .{T});
            const codec = intCodec(T);
            const tv = intTestVector(T);
            for (tv.slice()) |value| {
                var buf: [256]u8 = undefined;
                var writer = std.Io.Writer.fixed(&buf);
                var w = ByteWriter{ .writer = &writer };
                try codec.write(&w, value);
                // std.debug.print("{d} -> {any}\n", .{ value, w.slice() });
                const output = writer.buffered();
                try std.testing.expectEqual(output.len, codec.encodedLength(value));
                tt.checkFloat(output);
                var r = ByteReader{ .buf = output };
                try std.testing.expectEqual(value, try codec.read(&r));
            }
        }
    }
}
