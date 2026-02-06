const std = @import("std");
const IbexError = @import("./types.zig").IbexError;
const bytes = @import("./bytes.zig");

const Self = @This();
r: *bytes.ByteReader,
state: enum { INIT, ESCAPE, DONE } = .INIT,

pub const Token = struct {
    frag: []const u8,
    terminal: bool = false,
};

pub fn next(self: *Self) IbexError!Token {
    const tail = self.r.tail();
    switch (self.state) {
        .INIT => {
            if (std.mem.findAny(u8, tail, &.{ 0x00, 0x01 })) |esc| {
                try self.r.skip(esc + 1);
                switch (tail[esc]) {
                    0x00 => {
                        self.state = .DONE;
                        return .{ .frag = tail[0..esc], .terminal = true };
                    },
                    0x01 => {
                        self.state = .ESCAPE;
                        return .{ .frag = tail[0..esc] };
                    },
                    else => unreachable,
                }
            }

            return IbexError.SyntaxError;
        },
        .ESCAPE => {
            try self.r.skip(1);
            self.state = .INIT;
            return switch (tail[0]) {
                0x01 => .{ .frag = "\x00" },
                0x02 => .{ .frag = "\x01" },
                else => IbexError.SyntaxError,
            };
        },
        .DONE => unreachable,
    }
}
