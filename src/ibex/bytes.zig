const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ibex = @import("./ibex.zig");

const IbexError = ibex.IbexError;

pub const ByteReader = struct {
    const Self = @This();
    buf: []const u8,
    flip: u8 = 0x00,
    pos: usize = 0,

    pub fn eof(self: *const Self) bool {
        assert(self.pos <= self.buf.len);
        return self.pos == self.buf.len;
    }

    pub fn peek(self: *Self) u8 {
        assert(self.pos < self.buf.len);
        return self.buf[self.pos] ^ self.flip;
    }

    pub fn next(self: *Self) IbexError!u8 {
        if (self.eof())
            return IbexError.BufferEmpty;
        defer self.pos += 1;
        return self.peek();
    }

    pub fn negate(self: *Self) void {
        self.flip = ~self.flip;
    }
};

pub const ByteWriter = struct {
    const Self = @This();

    gpa: Allocator,
    buf: std.ArrayList(u8) = .empty,
    flip: u8 = 0x00,

    pub fn restart(self: *Self) void {
        self.buf.items.len = 0;
    }

    pub fn deinit(self: *Self) void {
        self.buf.deinit(self.gpa);
    }

    pub fn put(self: *Self, b: u8) !void {
        try self.buf.append(self.gpa, b ^ self.flip);
    }

    pub fn slice(self: *const Self) []const u8 {
        return self.buf.items;
    }

    pub fn negate(self: *Self) void {
        self.flip = ~self.flip;
    }
};
