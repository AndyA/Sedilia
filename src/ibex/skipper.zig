const std = @import("std");

const ibex = @import("./ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const bytes = @import("./bytes.zig");
const ByteReader = bytes.ByteReader;
const IbexInt = @import("./IbexInt.zig");
const mantissa = @import("./IbexNumber/mantissa.zig");

fn skipNumPos(r: *ByteReader) IbexError!void {
    try IbexInt.skip(r);
    try mantissa.skipMantissa(r);
}

fn skipNumNeg(r: *ByteReader) IbexError!void {
    r.negate();
    defer r.negate();
    return -try skipNumPos(r);
}

fn skipPastEnd(r: *ByteReader) IbexError!void {
    while (true) {
        const nb = try r.peek();
        const tag: IbexTag = @enumFromInt(nb);
        if (tag == .End) break;
        try skip(r);
    }

    try r.next(); // swallow .End
}

fn skipPastZero(r: *ByteReader) IbexError!void {
    if (std.mem.findScalar(u8, r.tail(), 0x00)) |pos|
        return r.skip(pos + 1);

    return IbexError.InvalidData;
}

pub fn skip(r: *ByteReader) IbexError!void {
    const nb = try r.next();
    const tag: IbexTag = @enumFromInt(nb);

    return switch (tag) {
        .End => IbexError.InvalidData, // may not occur on its own
        .Null, .False, .True => {},
        .String, .CollatedString => skipPastZero(r),
        .NumNegNaN, .NumNegInf => {},
        .NumNeg => skipNumNeg(r),
        .NumNegZero, .NumPosZero => {},
        .NumPos => skipNumPos(r),
        .NumPosInf, .NumPosNaN => {},
        .Array => skipPastEnd(r),
        .Object => skipPastEnd(r),
        else => IbexError.InvalidData,
    };
}
