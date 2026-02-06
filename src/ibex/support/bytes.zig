const std = @import("std");
const assert = std.debug.assert;
const ibex = @import("./types.zig");

const IbexError = ibex.IbexError;
const IbexTag = ibex.IbexTag;

/// Read bytes from a buffer. Optionally bytes read can be xored with 0xFF; this is used
/// for negative numbers.
pub const ByteReader = struct {
    const Self = @This();
    buf: []const u8,
    flip: u8 = 0x00,
    pos: usize = 0,

    /// Make a copy of this reader that sees the bytes from the current position onwards.
    pub fn fork(self: *const Self) Self {
        return Self{ .buf = self.tail(), .flip = self.flip };
    }

    pub fn eof(self: *const Self) bool {
        assert(self.pos <= self.buf.len);
        return self.pos == self.buf.len;
    }

    pub fn next(self: *Self) IbexError!u8 {
        if (self.eof())
            return IbexError.UnexpectedEndOfInput;
        defer self.pos += 1;
        return self.buf[self.pos] ^ self.flip;
    }

    pub fn nextTag(self: *Self) IbexError!IbexTag {
        assert(self.flip == 0x00);
        return try ibex.tagFromByte(try self.next());
    }

    pub fn negate(self: *Self) void {
        self.flip = ~self.flip;
    }

    pub fn skip(self: *Self, bytes: usize) !void {
        if (self.pos + bytes > self.buf.len)
            return IbexError.UnexpectedEndOfInput;
        self.pos += bytes;
    }

    pub fn tail(self: *const Self) []const u8 {
        assert(self.flip == 0x00);
        return self.buf[self.pos..];
    }
};

pub const ByteWriter = struct {
    const Self = @This();

    writer: *std.Io.Writer,
    flip: u8 = 0x00,

    pub fn put(self: *Self, b: u8) IbexError!void {
        try self.writer.writeByte(b ^ self.flip);
    }

    pub fn putTag(self: *Self, tag: IbexTag) IbexError!void {
        assert(self.flip == 0x00);
        try self.put(@intFromEnum(tag));
    }

    pub fn append(self: *Self, bytes: []const u8) IbexError!void {
        assert(self.flip == 0x00);
        try self.writer.writeAll(bytes);
    }

    pub fn negate(self: *Self) void {
        self.flip = ~self.flip;
    }
};
