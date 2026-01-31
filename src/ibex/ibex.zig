const std = @import("std");
const assert = std.debug.assert;

// Ibex and Oryx

pub const IbexTag = enum(u8) {
    End = 0x00, // end of Object / Array - sorts before anything else

    Null = 0x01,
    False = 0x02,
    True = 0x03,
    String = 0x04,
    CollatedString = 0x05, // <collated><string> | <collated><null>

    NumNegNaN = 0x06,
    NumNegInf = 0x07,
    NumNeg = 0x08, // ~NumPos
    NumNegZero = 0x09,
    NumPosZero = 0x0a,
    NumPos = 0x0b, // <exp: IbexInt><mant: mantissa>
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
    const tinfo = @typeInfo(info.tag_type).int;
    var seen: @Int(.unsigned, 1 << tinfo.bits) = 0;
    for (info.fields) |f| {
        assert((seen & (1 << f.value)) == 0);
        seen |= 1 << f.value;
    }
    assert((seen +% 1 & seen) == 0); // contiguous
    break :blk (1 << tinfo.bits) - @clz(seen);
};

pub fn validIbexTag(byte: u8) bool {
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
};
