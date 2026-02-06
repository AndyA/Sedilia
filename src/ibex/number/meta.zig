const std = @import("std");
const print = std.debug.print;

const ibex = @import("../support/types.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;

const bytes = @import("../support/bytes.zig");
const ByteWriter = bytes.ByteWriter;
const ByteReader = bytes.ByteReader;

const IbexVarInt = @import("./IbexVarInt.zig");
const mantissa = @import("./mantissa.zig");

const Self = @This();

negative: bool,
exponent: i64 = 0,
mantissa_bits: usize = 0,
special: bool = false,

fn fromNum(r: *ByteReader, negative: bool) IbexError!Self {
    const exp = try IbexVarInt.read(r);
    const mant_bits = try mantissa.mantissaBits(r);
    return Self{ .negative = negative, .exponent = exp, .mantissa_bits = mant_bits };
}

fn fromNumPos(r: *ByteReader) IbexError!Self {
    return fromNum(r, false);
}

fn fromNumNeg(r: *ByteReader) IbexError!Self {
    r.negate();
    defer r.negate();
    return fromNum(r, true);
}

pub fn fromReaderAfterTag(r: *ByteReader, tag: IbexTag) IbexError!Self {
    return switch (tag) {
        .NumNegNaN, .NumNegInf => Self{ .special = true, .negative = true },
        .NumNeg => fromNumNeg(r),
        .NumNegZero => Self{ .negative = true },
        .NumPosZero => Self{ .negative = false },
        .NumPos => fromNumPos(r),
        .NumPosInf, .NumPosNaN => Self{ .special = true, .negative = false },
        else => IbexError.TypeMismatch,
    };
}

pub fn intBits(self: *const Self) ?usize {
    if (self.special or self.mantissa_bits > self.exponent)
        return null;
    return @intCast(self.exponent + 1);
}

const IbexNumber = @import("./IbexNumber.zig").IbexNumber;

test {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    var w = ByteWriter{ .writer = &writer };
    try IbexNumber(u64).write(&w, std.math.maxInt(u64));
    var r = ByteReader{ .buf = writer.buffered() };
    const nb = try r.next();
    const meta: Self = try .fromReaderAfterTag(&r, @enumFromInt(nb));
    try std.testing.expectEqual(64, meta.intBits());
    // print("{any}\n", .{meta});
}
