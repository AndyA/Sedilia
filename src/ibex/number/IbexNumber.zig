const std = @import("std");
const intCodec = @import("./int.zig").intCodec;
const floatCodec = @import("./float.zig").floatCodec;

test {
    std.testing.refAllDecls(@This());
}

pub fn IbexNumber(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .float => floatCodec(T),
        .int => intCodec(T),
        else => unreachable,
    };
}

fn testRoundTrip(comptime TWrite: type, comptime TRead: type, value: comptime_float) !void {
    const bytes = @import("../bytes.zig");

    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    var w = bytes.ByteWriter{ .writer = &writer };
    try IbexNumber(TWrite).write(&w, value);

    var r = bytes.ByteReader{ .buf = writer.buffered() };
    const res = try IbexNumber(TRead).read(&r);
    const got: f128 = switch (@typeInfo(TRead)) {
        .int => @floatFromInt(res),
        .float => @floatCast(res),
        else => unreachable,
    };
    try std.testing.expectEqual(@as(f128, @floatCast(value)), got);
}

test IbexNumber {
    try testRoundTrip(u8, f32, 1.0);
    try testRoundTrip(f32, u8, 1.0);
}

pub const IbexNumberMeta = @import("./meta.zig");
