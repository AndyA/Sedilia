const std = @import("std");
const assert = std.debug.assert;

// Ibex and Oryx

pub const IbexTag = enum(u8) {
    End = 0x00, // end of Object / Array - sorts before anything else

    Null = 0x01,
    False = 0x02,
    True = 0x03,
    String = 0x04,

    NumNegNaN = 0x05,
    NumNegInf = 0x06,
    NumNeg = 0x07,
    NumNegZero = 0x08,
    NumPosZero = 0x09,
    NumPos = 0x0a,
    NumPosInf = 0x0b,
    NumPosNaN = 0x0c,

    Array = 0x0d,
    Object = 0x0e,

    // Behaves like Array; represents something like NDJSON - a sequence of objects.
    Multi = 0x0f,

    // Additional Oryx encodings
    OryxInt = 0x10, // value: IbexInt
    OryxString = 0x11, // len: IbexInt, str: []u8

    OryxClass = 0x12, // parent: IbexInt, count: IbexInt, keys: []IbexValue
    OryxArray = 0x13, // count: IbexInt, values: []IbexValue
    OryxObject = 0x14, // class: IbexInt, count: IbexInt, values: []IbexValue

    pub fn indexSafe(tag: IbexTag) bool {
        return @intFromEnum(tag) < @intFromEnum(IbexTag.Multi);
    }
};

test IbexTag {
    try std.testing.expect(IbexTag.indexSafe(.Object));
    try std.testing.expect(!IbexTag.indexSafe(.Multi));
}

pub const IbexError = error{
    InvalidData,
    Overflow,
    BufferFull,
    BufferEmpty,
};
