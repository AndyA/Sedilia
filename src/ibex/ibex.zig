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

test IbexTag {
    try std.testing.expect(IbexTag.isNumber(.NumNegNaN));
    try std.testing.expect(!IbexTag.isNumber(.String));
}

pub const IbexError = error{
    InvalidData,
    Overflow,
    BufferFull,
    BufferEmpty,
};
