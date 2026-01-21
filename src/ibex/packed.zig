const std = @import("std");
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

pub fn PackedSlice(comptime T: type, comptime bits: usize) type {
    return packed struct {
        const Self = @This();
        pub const Type = []const T;

        len: @Int(.unsigned, bits - @bitSizeOf([*]const T)),
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
    try expectEqual(120, @bitSizeOf(PackedSlice(u8, 120)));
    const is = PackedSlice(u8, 120).init("Hello");
    try expectEqual("Hello", is.get());
}

pub fn Padded(comptime T: type, comptime bits: usize) type {
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
