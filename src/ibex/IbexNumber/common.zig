const std = @import("std");

const ibex = @import("../ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const bytes = @import("../bytes.zig");
const ByteReader = bytes.ByteReader;
const IbexInt = @import("../IbexInt.zig");
const mantissa = @import("./mantissa.zig");

fn skipNumPos(r: *ByteReader) IbexError!void {
    try IbexInt.skip(r);
    try mantissa.skipMantissa(r);
}

fn skipNumNeg(r: *ByteReader) IbexError!void {
    r.negate();
    defer r.negate();
    return -try skipNumPos(r);
}

pub fn skip(r: *ByteReader) IbexError!void {
    const nb = try r.next();
    const tag: IbexTag = @enumFromInt(nb);
    switch (tag) {
        .NumPosZero, .NumNegZero, .NumNegInf, .NumPosInf, .NumNegNaN, .NumPosNaN => return,
        .NumPos => skipNumPos(r),
        .NumNeg => skipNumNeg(r),
        else => IbexError.InvalidData,
    }
}
