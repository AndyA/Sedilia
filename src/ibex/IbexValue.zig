const std = @import("std");
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const pack = @import("./packed.zig");
const shadow = @import("./shadow.zig");
const IbexClass = shadow.IbexClass;

test {
    std.testing.refAllDecls(@This());
}

const IbexValue = packed struct {
    const Self = @This();

    const TagType = u8;
    const budget = 128 - @bitSizeOf(TagType);

    const Payload = packed union {
        null: pack.Padded(void, budget),
        bool: pack.Padded(bool, budget),
        integer: pack.Padded(i64, budget),
        float: pack.Padded(f64, budget),
        array: pack.Slice(IbexValue, budget),
        // An object is like an array but its first element must be a `class`
        object: pack.Slice(IbexValue, budget),
        string: pack.Slice(u8, budget),
        class: pack.Padded(*const IbexClass, budget),
        json: pack.Slice(u8, budget), // literal JSON
        ibex: pack.Slice(u8, budget), // Ibex/Oryx bytes
    };

    pub const Tag = enum(TagType) {
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

    tag: Tag,
    p: Payload,

    pub fn tagType(comptime tag: Tag) type {
        return @FieldType(Payload, @tagName(tag)).Type;
    }

    pub fn init(comptime tag: Tag, value: tagType(tag)) Self {
        const FT = @FieldType(Payload, @tagName(tag));
        const payload = @unionInit(Payload, @tagName(tag), FT.init(value));
        return Self{ .tag = tag, .p = payload };
    }

    pub fn get(self: Self, comptime tag: Tag) tagType(tag) {
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
