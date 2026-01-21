const std = @import("std");

pub const IbexClass = struct {}; // TODO

pub const IbexValueType = enum(u8) {
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

        len: u56,
        ptr: [*]const T,

        pub fn init(slice: []const T) Self {
            return Self{ .len = @intCast(slice.len), .ptr = slice.ptr };
        }

        pub fn get(self: *const Self) []const T {
            return self.ptr[0..self.len];
        }
    };
}

test PackedSlice {
    try std.testing.expectEqual(120, @bitSizeOf(PackedSlice(u8)));
    const is = PackedSlice(u8).init("Hello");
    try std.testing.expectEqual("Hello", is.get());
}

fn Padded(comptime T: type, comptime bits: usize) type {
    return packed struct {
        pad: @Int(.unsigned, bits - @bitSizeOf(T)) = 0,
        d: T,
    };
}

const Payload = packed union {
    null: Padded(void, 120),
    bool: Padded(bool, 120),
    integer: Padded(i64, 120),
    float: Padded(f64, 120),
    array: PackedSlice(IbexValue),
    object: PackedSlice(IbexValue),
    string: PackedSlice(u8),
    class: Padded(*const IbexClass, 120),
    json: PackedSlice(u8),
    ibex: PackedSlice(u8),
};

const IbexValue = packed struct {
    const Self = @This();

    tag: IbexValueType,
    v: Payload,

    pub fn initNull() Self {
        return Self{ .tag = .null, .v = Payload{ .null = .{ .d = {} } } };
    }

    pub fn initBool(b: bool) Self {
        return Self{ .tag = .bool, .v = Payload{ .bool = .{ .d = b } } };
    }
};

test IbexValue {
    try std.testing.expectEqual(128, @bitSizeOf(IbexValue));
    const ivNull = IbexValue.initNull();
    try std.testing.expectEqual(.null, ivNull.tag);
}

pub fn main() !void {
    std.debug.print("{d}\n", .{@bitSizeOf(IbexValue)});
}
