const std = @import("std");

const ibex = @import("./ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const bytes = @import("./bytes.zig");
const ByteReader = bytes.ByteReader;
const IbexInt = @import("./IbexInt.zig");
const mantissa = @import("./number/mantissa.zig");

fn skipNumPos(r: *ByteReader) IbexError!void {
    try IbexInt.skip(r);
    try mantissa.skipMantissa(r);
}

fn skipNumNeg(r: *ByteReader) IbexError!void {
    r.negate();
    defer r.negate();
    return try skipNumPos(r);
}

fn skipPastEnd(r: *ByteReader) IbexError!void {
    while (true) {
        const tag = try ibex.tagFromByte(try r.next());
        if (tag == .End) break;
        try skipTag(r, tag);
    }
}

fn skipPastZero(r: *ByteReader) IbexError!void {
    if (std.mem.findScalar(u8, r.tail(), 0x00)) |pos|
        return r.skip(pos + 1);

    return IbexError.SyntaxError;
}

fn skipTag(r: *ByteReader, tag: IbexTag) IbexError!void {
    return switch (tag) {
        .End => IbexError.SyntaxError, // may not occur on its own
        .Null, .False, .True => {},
        .NumNegNaN, .NumNegInf, .NumNegZero => {},
        .NumPosZero, .NumPosInf, .NumPosNaN => {},
        .String => skipPastZero(r),
        .Collation => {
            try skipPastZero(r);
            return skip(r);
        },
        .NumNeg => skipNumNeg(r),
        .NumPos => skipNumPos(r),
        .Array, .Object => skipPastEnd(r),
    };
}

pub fn skip(r: *ByteReader) IbexError!void {
    try skipTag(r, try ibex.tagFromByte(try r.next()));
}
