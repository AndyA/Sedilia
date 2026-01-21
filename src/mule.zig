const std = @import("std");
const Timer = std.time.Timer;
const assert = std.debug.assert;

const Span = packed struct {
    tag: u8,
    len: u24,
    pos: u32,
};

const P = packed union {
    span: Span,
};

pub fn main() !void {
    std.debug.print("{d}\n", .{@bitSizeOf(P)});
}
