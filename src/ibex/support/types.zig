const std = @import("std");
const assert = std.debug.assert;

// Ibex and Oryx

pub const IbexTag = enum(u8) {
    End = 0x00, // end of Object / Array - sorts before anything else

    Null = 0x01,
    False = 0x02,
    True = 0x03,
    String = 0x04,
    Collation = 0x05,

    NumNegNaN = 0x06,
    NumNegInf = 0x07,
    NumNeg = 0x08, // ~NumPos
    NumNegZero = 0x09,
    NumPosZero = 0x0a,
    NumPos = 0x0b, // <exp: IbexVarInt><mant: mantissa>
    NumPosInf = 0x0c,
    NumPosNaN = 0x0d,

    Array = 0x0e, // (elt)* End
    Object = 0x0f, // (k, v)* End

    pub fn isNumber(tag: IbexTag) bool {
        return switch (tag) {
            .NumNegNaN, .NumNegInf, .NumNeg, .NumNegZero => true,
            .NumPosZero, .NumPos, .NumPosInf, .NumPosNaN => true,
            else => false,
        };
    }
};

pub const IbexTagMax = blk: {
    const info = @typeInfo(IbexTag).@"enum";
    assert(info.tag_type == u8);
    var seen: u256 = 0;
    for (info.fields) |f| seen |= 1 << f.value;
    assert((seen +% 1 & seen) == 0); // contiguous
    break :blk 256 - @clz(seen);
};

fn validIbexTag(byte: u8) bool {
    return byte < IbexTagMax;
}

pub fn tagFromByte(b: u8) !IbexTag {
    if (validIbexTag(b))
        return @enumFromInt(b);
    return IbexError.SyntaxError;
}

test IbexTag {
    try std.testing.expect(IbexTag.isNumber(.NumNegNaN));
    try std.testing.expect(!IbexTag.isNumber(.String));
    try std.testing.expectEqual(0x10, IbexTagMax);
}

pub const IbexError = error{
    Overflow,
    BufferFull,
    OutOfMemory,
    InvalidCharacter,
    SyntaxError,
    UnexpectedEndOfInput,
    BufferUnderrun,
    TypeMismatch,
    ArraySizeMismatch,
    UnknownField,
    MissingKeys,
    WriteFailed,
    DuplicateKey,
};
