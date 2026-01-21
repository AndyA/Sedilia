const std = @import("std");
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

pub const IbexClass = struct {}; // TODO

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

fn PackedSlice(comptime T: type) type {
    return packed struct {
        const Self = @This();
        pub const Type = []const T;

        len: u56,
        ptr: [*]const T,

        pub fn init(value: Type) Self {
            return Self{ .len = @intCast(value.len), .ptr = value.ptr };
        }

        pub fn get(self: Self) Type {
            return self.ptr[0..self.len];
        }
    };
}

test PackedSlice {
    try expectEqual(120, @bitSizeOf(PackedSlice(u8)));
    const is = PackedSlice(u8).init("Hello");
    try expectEqual("Hello", is.get());
}

fn Padded(comptime T: type, comptime bits: usize) type {
    return packed struct {
        const Self = @This();
        pub const Type = T;

        pad: @Int(.unsigned, bits - @bitSizeOf(T)) = 0,
        v: T,

        pub fn init(value: Type) Self {
            return Self{ .v = value };
        }

        pub fn get(self: Self) Type {
            return self.v;
        }
    };
}

const Payload = packed union {
    null: Padded(void, 120),
    bool: Padded(bool, 120),
    integer: Padded(i64, 120),
    float: Padded(f64, 120),
    array: PackedSlice(IbexValue),
    object: PackedSlice(IbexValue), // like an array but with the class as the first element
    string: PackedSlice(u8),
    class: Padded(*const IbexClass, 120),
    json: PackedSlice(u8), // literal JSON
    ibex: PackedSlice(u8), // Ibex/Oryx bytes
};

const IbexValue = packed struct {
    const Self = @This();

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
