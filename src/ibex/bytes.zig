const std = @import("std");
const assert = std.debug.assert;
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

    pub fn peek(self: *Self) IbexError!u8 {
        if (self.eof())
            return IbexError.UnexpectedEndOfInput;
        return self.buf[self.pos] ^ self.flip;
    }

    pub fn next(self: *Self) IbexError!u8 {
        defer self.pos += 1;
        return try self.peek();
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

const ByteWriter1 = struct {
    const Self = @This();
    buf: []u8,
    flip: u8 = 0x00,
    pos: usize = 0,

    pub fn put(self: *Self, b: u8) IbexError!void {
        assert(self.pos <= self.buf.len);
        if (self.pos == self.buf.len)
            return IbexError.BufferFull;
        defer self.pos += 1;
        self.buf[self.pos] = b ^ self.flip;
    }

    pub fn append(self: *Self, bytes: []const u8) IbexError!void {
        assert(self.flip == 0x00);
        if (self.pos + bytes.len > self.buf.len)
            return IbexError.BufferFull;
        @memcpy(self.buf[self.pos .. self.pos + bytes.len], bytes);
        self.pos += bytes.len;
    }

    pub fn slice(self: *const Self) []const u8 {
        return self.buf[0..self.pos];
    }

    pub fn negate(self: *Self) void {
        self.flip = ~self.flip;
    }

    pub const Fixed = struct {
        bw: Self,

        pub fn init(buf: []u8) Fixed {
            return Fixed{ .bw = Self{ .buf = buf } };
        }

        pub fn slice(self: *const Fixed) []const u8 {
            return self.bw.slice();
        }
    };
};

const ByteWriter2 = struct {
    const BW = @This();

    writer: *std.Io.Writer,
    flip: u8 = 0x00,

    pub fn put(self: *BW, b: u8) IbexError!void {
        try self.writer.writeByte(b ^ self.flip);
    }

    pub fn append(self: *BW, bytes: []const u8) IbexError!void {
        assert(self.flip == 0x00);
        try self.writer.writeAll(bytes);
    }

    pub fn negate(self: *BW) void {
        self.flip = ~self.flip;
    }

    pub const Fixed = struct {
        bw: BW = undefined,
        writer: std.Io.Writer,

        pub fn init(buf: []u8) Fixed {
            var fixed = Fixed{ .writer = std.Io.Writer.fixed(buf) };
            fixed.bw = BW{ .writer = &fixed.writer };
            return fixed;
        }

        pub fn slice(self: *const Fixed) []const u8 {
            return self.writer.buffer[0..self.writer.end];
        }
    };
};

pub const ByteWriter = ByteWriter1;
