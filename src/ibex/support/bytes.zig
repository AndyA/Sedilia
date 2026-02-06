const std = @import("std");
const assert = std.debug.assert;
const ibex = @import("./types.zig");

const IbexError = ibex.IbexError;
const IbexTag = ibex.IbexTag;

pub const ByteReader = struct {
    const Self = @This();
    buf: []const u8,
    flip: u8 = 0x00,
    pos: usize = 0,

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
        return self.buf[self.pos..];
    }
};

pub const ByteWriter = struct {
    const BW = @This();

    writer: *std.Io.Writer,
    flip: u8 = 0x00,

    pub fn put(self: *BW, b: u8) IbexError!void {
        try self.writer.writeByte(b ^ self.flip);
    }

    pub fn putTag(self: *BW, tag: IbexTag) IbexError!void {
        try self.put(@intFromEnum(tag));
    }

    pub fn append(self: *BW, bytes: []const u8) IbexError!void {
        assert(self.flip == 0x00);
        try self.writer.writeAll(bytes);
    }

    pub fn negate(self: *BW) void {
        self.flip = ~self.flip;
    }
};
