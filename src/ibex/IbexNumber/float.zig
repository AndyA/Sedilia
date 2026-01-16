const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const ibex = @import("../ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const bytes = @import("../bytes.zig");
const ByteReader = bytes.ByteReader;
const ByteWriter = bytes.ByteWriter;
const IbexInt = @import("../IbexInt.zig");
const mantissa = @import("./mantissa.zig");

fn FloatBits(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const bits = @typeInfo(T).float.bits;
        pub const exp_bits = switch (bits) {
            16 => 5,
            32 => 8,
            64 => 11,
            80 => 15,
            128 => 15,
            else => unreachable,
        };
        // f80 stores the redundant MSB of the mantissa explicitly.
        // Presumably because f80 is a legacy 80(2)87 format?
        pub const explicit_msb = switch (bits) {
            80 => true,
            else => false,
        };
        pub const mant_bits = bits - exp_bits - 1;
        pub const exp_bias = (1 << exp_bits - 1) - 1;

        pub const TExpValue = @Int(.signed, exp_bits + 1);
        pub const TInt = @Int(.unsigned, bits);
        pub const TExp = @Int(.unsigned, exp_bits);
        pub const TMant = @Int(.unsigned, mant_bits);

        value: packed struct(TInt) {
            mant: TMant,
            exp: TExp,
            sign: bool,
        } = undefined,

        pub fn init(value: T) Self {
            return Self{ .value = @bitCast(value) };
        }

        pub fn get(self: Self) T {
            return @bitCast(self.value);
        }

        pub fn format(self: Self, w: *std.Io.Writer) std.Io.Writer.Error!void {
            const norm_exp = @as(i64, @intCast(self.value.exp)) - exp_bias;
            try w.print(
                "{any:>5} {s} e( {x:>4} ) m( {x:>28} ) ({d:>8})",
                .{
                    T,
                    if (self.value.sign) "-" else "+",
                    self.value.exp,
                    self.value.mant,
                    norm_exp,
                },
            );
        }
    };
}

fn isOverflow(comptime T: type, value: anytype) bool {
    return math.isFinite((value)) and
        (value < -math.floatMax(T) or
            value > math.floatMax(T));
}

pub fn floatCodec(comptime T: type) type {
    if (T == f80) {
        const codec = floatCodec(f128);
        return struct {
            // Use f128 to handle f80
            pub fn encodedLength(value: T) usize {
                return codec.encodedLength(value);
            }

            pub fn write(w: *ByteWriter, value: T) !void {
                try codec.write(w, value);
            }

            pub fn read(r: *ByteReader) !T {
                const res = try codec.read(r);
                if (isOverflow(f80, res))
                    return IbexError.Overflow;
                return @floatCast(res);
            }
        };
    }

    const VT = FloatBits(T);
    assert(!VT.explicit_msb);

    return struct {
        fn massageFloat(value: T) struct { i64, VT.TMant } {
            const v = VT.init(@abs(value));
            var exp: i64 = v.value.exp;
            var mant = v.value.mant;

            assert(exp < math.maxInt(VT.TExp));

            // https://en.wikipedia.org/wiki/Subnormal_number
            if (exp == 0) {
                const lz = @clz(mant);
                mant <<= @intCast(lz);
                exp -= lz;
            }

            return .{ exp, mant };
        }

        pub fn encodedLength(value: T) usize {
            if (math.isNegativeZero(value) or
                math.isPositiveZero(value) or
                math.isInf(value) or
                math.isNan(value))
                return 1;

            const exp, const mant = massageFloat(value);

            return 1 + IbexInt.encodedLength(exp - VT.exp_bias) +
                mantissa.mantissaLength(VT.TMant, mant);
        }

        fn writeFloat(w: *ByteWriter, value: T) !void {
            const exp, const mant = massageFloat(value);
            try IbexInt.write(w, exp - VT.exp_bias);
            try mantissa.writeMantissa(VT.TMant, w, mant);
        }

        pub fn write(w: *ByteWriter, value: T) !void {
            if (math.isNegativeInf(value))
                return w.put(@intFromEnum(IbexTag.NumNegInf))
            else if (math.isPositiveInf(value))
                return w.put(@intFromEnum(IbexTag.NumPosInf))
            else if (math.isNegativeZero(value))
                return w.put(@intFromEnum(IbexTag.NumNegZero))
            else if (math.isPositiveZero(value))
                return w.put(@intFromEnum(IbexTag.NumPosZero))
            else if (math.isNan(value)) {
                const v = VT.init(value);
                const tag: IbexTag = if (v.value.sign) .NumNegNaN else .NumPosNaN;
                return w.put(@intFromEnum(tag));
            } else if (value < 0.0) {
                try w.put(@intFromEnum(IbexTag.NumNeg));
                w.negate();
                defer w.negate();
                return writeFloat(w, -value);
            } else {
                try w.put(@intFromEnum(IbexTag.NumPos));
                return writeFloat(w, value);
            }
        }

        fn readNumPos(r: *ByteReader) !T {
            var exp = try IbexInt.read(r) + VT.exp_bias;
            // std.debug.print("exp={d}, max={d}\n", .{ exp, math.maxInt(VT.TExp) });
            if (exp >= math.maxInt(VT.TExp))
                return IbexError.Overflow;

            var mant = try mantissa.readMantissa(VT.TMant, r);

            // https://en.wikipedia.org/wiki/Subnormal_number
            if (exp <= 0) {
                if (-exp >= VT.mant_bits)
                    return 0.0;
                mant >>= @intCast(-exp);
                exp = 0;
            }

            const v = VT{ .value = .{
                .exp = @intCast(exp),
                .mant = mant,
                .sign = false,
            } };
            return v.get();
        }

        fn readNumNeg(r: *ByteReader) !T {
            r.negate();
            defer r.negate();
            return -try readNumPos(r);
        }

        pub fn read(r: *ByteReader) !T {
            const nb = try r.next();
            const tag: IbexTag = @enumFromInt(nb);
            return switch (tag) {
                .NumPosZero => 0.0,
                .NumNegZero => -0.0,
                .NumNegInf => -math.inf(T),
                .NumPosInf => math.inf(T),
                .NumNegNaN => -math.nan(T),
                .NumPosNaN => math.nan(T),
                .NumPos => readNumPos(r),
                .NumNeg => readNumNeg(r),
                else => IbexError.InvalidData,
            };
        }
    };
}

const tt = @import("./test_tools.zig");

fn TV(comptime T: type) type {
    return tt.TestVec(T, 100);
}

fn floatTestVector(comptime T: type) TV(T) {
    var tv = TV(T){};

    tv.put(math.floatMin(T));
    tv.put(math.floatMax(T));
    tv.put(-math.floatMin(T));
    tv.put(-math.floatMax(T));
    tv.put(math.floatEpsAt(T, 0));
    tv.put(-math.floatEpsAt(T, 0));
    tv.put(math.inf(T));
    tv.put(-math.inf(T));
    tv.put(math.nan(T));
    tv.put(-math.nan(T));

    tv.put(math.pi);
    tv.put(math.phi);
    tv.put(-math.pi);
    tv.put(-math.phi);

    var small: T = 0.0;
    while (small < 15.0) : (small += 1.0) {
        tv.put(small);
        tv.put(-small);
        tv.put(1.0 / small);
        tv.put(-1.0 / small);
    }

    // std.debug.print("{any}: {any}\n", .{ T, tv.slice() });

    return tv;
}

fn TMost(comptime TA: type, comptime TB: type) type {
    return if (@typeInfo(TA).float.bits > @typeInfo(TB).float.bits) TA else TB;
}

fn TLeast(comptime TA: type, comptime TB: type) type {
    return if (@typeInfo(TA).float.bits < @typeInfo(TB).float.bits) TA else TB;
}

fn testRoundTrip(
    gpa: Allocator,
    comptime TWrite: type,
    comptime TRead: type,
    value: TMost(TWrite, TRead),
) !void {
    if (isOverflow(TWrite, value)) {
        // std.debug.print("skipping {d} out of range for {any}\n", .{ value, TWrite });
        return;
    }
    const enc = floatCodec(TWrite);
    var w = ByteWriter{ .gpa = gpa };
    defer w.deinit();
    try enc.write(&w, @floatCast(value));
    // std.debug.print("{d} -> {any}\n", .{ value, w.slice() });
    try std.testing.expectEqual(w.buf.items.len, enc.encodedLength(@floatCast(value)));

    const dec = floatCodec(TRead);
    var r = ByteReader{ .buf = w.slice() };

    if (isOverflow(TRead, value)) {
        const res = dec.read(&r);
        try std.testing.expectError(IbexError.Overflow, res);
        return;
    }

    const output = try dec.read(&r);

    if (math.isNegativeInf(value)) {
        try std.testing.expect(math.isNegativeInf(output));
    } else if (math.isPositiveInf(value)) {
        try std.testing.expect(math.isPositiveInf(output));
    } else if (math.isNan(value)) {
        try std.testing.expect(math.isNan(output));
    } else {
        const TMin = TLeast(TWrite, TRead);
        const TMax = TMost(TWrite, TRead);
        const eps: TMax = @floatCast(math.floatEpsAt(TMin, @floatCast(value)));
        const want: TMax = @floatCast(value);
        const got: TMax = @floatCast(output);
        // std.debug.print("want={f}\n got={f}\n", .{ guts(want), guts(got) });
        // std.debug.print("diff={d}, eps={d}\n", .{ @abs(got - want), eps });
        try std.testing.expect(@abs(got - want) <= eps);
    }

    if (TWrite == TRead) {
        const want: TRead = @floatCast(value);
        try std.testing.expect(tt.exactSame(want, output));
    }
}

const FloatTypes = [_]type{ f16, f32, f64, f80, f128 };

test floatCodec {
    const gpa = std.testing.allocator;
    inline for (FloatTypes) |TWrite| {
        inline for (FloatTypes) |TRead| {
            // std.debug.print("=== {any} -> {any} ===\n", .{ TWrite, TRead });
            const tvw = floatTestVector(TWrite);
            for (tvw.slice()) |value| {
                try testRoundTrip(gpa, TWrite, TRead, value);
            }
            const tvr = floatTestVector(TRead);
            for (tvr.slice()) |value| {
                try testRoundTrip(gpa, TWrite, TRead, value);
            }
        }
    }
}
