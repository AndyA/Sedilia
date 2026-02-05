const std = @import("std");
const assert = std.debug.assert;

const ibex = @import("./types.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const bytes = @import("./bytes.zig");
const ByteReader = bytes.ByteReader;
const IbexVarInt = @import("../number/IbexVarInt.zig");
const mantissa = @import("../number/mantissa.zig");

fn skipNumPos(r: *ByteReader) IbexError!void {
    try IbexVarInt.skip(r);
    try mantissa.skipMantissa(r);
}

fn skipNumNeg(r: *ByteReader) IbexError!void {
    r.negate();
    defer r.negate();
    try skipNumPos(r);
}

fn skipPastObject(r: *ByteReader) IbexError!void {
    while (true) {
        const tag = try ibex.tagFromByte(try r.next());
        if (tag == .End) break;
        if (tag != .String)
            return IbexError.SyntaxError;
        try skipPastString(r);
        try skip(r);
    }
}

fn skipPastArray(r: *ByteReader) IbexError!void {
    while (true) {
        const tag = try ibex.tagFromByte(try r.next());
        if (tag == .End) break;
        try skipAfterTag(r, tag);
    }
}

fn skipPastString(r: *ByteReader) IbexError!void {
    const tail = r.tail();
    var pos: usize = 0;
    while (std.mem.findAnyPos(u8, tail, pos, &.{ 0x00, 0x01 })) |esc| {
        if (tail[esc] == 0x00)
            return r.skip(esc + 1);
        assert(tail[esc] == 0x01);
        if (esc + 1 == tail.len)
            return IbexError.SyntaxError;
        const code = tail[esc + 1];
        if (code != 0x01 and code != 0x02)
            return IbexError.SyntaxError;
        pos = esc + 2;
    }

    return IbexError.SyntaxError;
}

fn skipPastZero(r: *ByteReader) IbexError!void {
    if (std.mem.findScalar(u8, r.tail(), 0x00)) |pos|
        return r.skip(pos + 1);

    return IbexError.SyntaxError;
}

pub fn skipAfterTag(r: *ByteReader, tag: IbexTag) IbexError!void {
    return switch (tag) {
        .End => IbexError.SyntaxError, // may not occur on its own
        .Null, .False, .True => {},
        .NumNegNaN, .NumNegInf, .NumNegZero => {},
        .NumPosZero, .NumPosInf, .NumPosNaN => {},
        .String => skipPastString(r),
        .Collation => {
            try skipPastZero(r);
            return skip(r);
        },
        .NumNeg => skipNumNeg(r),
        .NumPos => skipNumPos(r),
        .Array => skipPastArray(r),
        .Object => skipPastObject(r),
    };
}

pub fn skip(r: *ByteReader) IbexError!void {
    try skipAfterTag(r, try ibex.tagFromByte(try r.next()));
}
