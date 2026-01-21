const std = @import("std");
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const pack = @import("./packed.zig");
const shadow = @import("./shadow.zig");
const IbexClass = shadow.IbexClass;

test {
    std.testing.refAllDecls(@This());
}

pub const IbexValueTag = enum(u8) {
    null,
    bool,
    integer,
    float,
    array,
    object,
    string,
    class,
    json,
    ibex,
};

const IbexValue = packed struct {
    const Self = @This();

    const budget = 128 - @bitSizeOf(IbexValueTag);

    const Payload = packed union {
        null: pack.Padded(void, budget),
        bool: pack.Padded(bool, budget),
        integer: pack.Padded(i64, budget),
        float: pack.Padded(f64, budget),
        array: pack.PackedSlice(IbexValue, budget),
        object: pack.PackedSlice(IbexValue, budget), // like an array but with the class as the first element
        string: pack.PackedSlice(u8, budget),
        class: pack.Padded(*const IbexClass, budget),
        json: pack.PackedSlice(u8, budget), // literal JSON
        ibex: pack.PackedSlice(u8, budget), // Ibex/Oryx bytes
    };

    tag: IbexValueTag,
    p: Payload,

    pub fn tagType(comptime tag: IbexValueTag) type {
        return @FieldType(Payload, @tagName(tag)).Type;
    }

    pub fn init(comptime tag: IbexValueTag, value: tagType(tag)) Self {
        const FT = @FieldType(Payload, @tagName(tag));
        const payload = @unionInit(Payload, @tagName(tag), FT.init(value));
        return Self{ .tag = tag, .p = payload };
    }

    pub fn get(self: Self, comptime tag: IbexValueTag) tagType(tag) {
        assert(tag == self.tag);
        return @field(self.p, @tagName(tag)).get();
    }
};

test IbexValue {
    try expectEqual(128, @bitSizeOf(IbexValue));

    const ivNull = IbexValue.init(.null, {});
    try expectEqual(.null, ivNull.tag);

    const ivInt = IbexValue.init(.integer, 12345);
    try expectEqual(.integer, ivInt.tag);
    try expectEqual(12345, ivInt.get(.integer));

    const ivStr = IbexValue.init(.string, "Hello!");
    try expectEqual(.string, ivStr.tag);
    try expectEqual("Hello!", ivStr.get(.string));
}
