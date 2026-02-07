const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Stringify = std.json.Stringify;
const Scanner = std.json.Scanner;

const JsonFilter = struct {
    const Self = @This();

    gpa: Allocator,
    reader: *std.Io.Reader,
    scanner: Scanner,
    stringify: Stringify,
    prefix: []const u8,
    foo: [128 * 1024]u8 = undefined,

    state: enum { init, string, number } = .init,
    path: std.ArrayList(u8) = .empty,

    pub fn init(
        gpa: Allocator,
        reader: *std.Io.Reader,
        writer: *std.Io.Writer,
        prefix: []const u8,
    ) Self {
        return Self{
            .gpa = gpa,
            .reader = reader,
            .scanner = Scanner.initStreaming(gpa),
            .stringify = Stringify{ .writer = writer },
            .prefix = prefix,
        };
    }

    pub fn deinit(self: *Self) void {
        self.path.deinit(self.gpa);
        self.scanner.deinit();
    }

    fn stringPart(self: *Self, frag: []const u8) !void {
        const sfy = &self.stringify;
        if (self.state == .init) {
            try sfy.beginWriteRaw();
            try sfy.writer.writeByte('"');
            self.state = .string;
        }
        assert(self.state == .string);
        try Stringify.encodeJsonStringChars(frag, .{}, sfy.writer);
    }

    fn stringEnd(self: *Self, frag: []const u8) !void {
        const sfy = &self.stringify;
        try self.stringPart(frag);
        try sfy.writer.writeByte('"');
        sfy.endWriteRaw();
        self.state = .init;
    }

    fn numberPart(self: *Self, frag: []const u8) !void {
        const sfy = &self.stringify;
        if (self.state == .init) {
            try sfy.beginWriteRaw();
            self.state = .number;
        }
        assert(self.state == .number);
        try sfy.writer.writeAll(frag);
    }

    fn numberEnd(self: *Self, frag: []const u8) !void {
        const sfy = &self.stringify;
        try self.numberPart(frag);
        sfy.endWriteRaw();
        self.state = .init;
    }

    fn pump(self: *Self) !Scanner.Token {
        const r = self.reader;
        print("peeking...\n", .{});
        const got = try r.readSliceShort(&self.foo);
        if (got == 0) {
            self.scanner.endInput();
        } else {
            self.scanner.feedInput(&self.foo);
        }
        return self.scanner.next();
    }

    fn next(self: *Self) !Scanner.Token {
        return self.scanner.next() catch |e| switch (e) {
            error.BufferUnderrun => self.pump(),
            else => e,
        };
    }

    fn echoArray(self: *Self) anyerror!void {
        const sfy = &self.stringify;
        var tok = try self.next();
        try sfy.beginArray();
        while (tok != .array_end) : (tok = try self.next()) {
            try self.echoAfterToken(tok);
        }
        try sfy.endArray();
    }

    fn echoObject(self: *Self) anyerror!void {
        const sfy = &self.stringify;
        var tok = try self.next();
        try sfy.beginObject();
        while (tok != .object_end) : (tok = try self.next()) {
            try self.echoAfterToken(tok);
            try self.echoAfterToken(try self.next());
        }
        try sfy.endObject();
    }

    fn echoAfterToken(self: *Self, tok: Scanner.Token) !void {
        const sfy = &self.stringify;
        switch (tok) {
            .end_of_document => unreachable,

            .null => try sfy.write(null),
            .false => try sfy.write(false),
            .true => try sfy.write(true),

            .array_begin => try self.echoArray(),
            .object_begin => try self.echoObject(),

            .partial_string => |str| try self.stringPart(str),
            .partial_string_escaped_1 => |str| try self.stringPart(&str),
            .partial_string_escaped_2 => |str| try self.stringPart(&str),
            .partial_string_escaped_3 => |str| try self.stringPart(&str),
            .partial_string_escaped_4 => |str| try self.stringPart(&str),
            .string => |str| try self.stringEnd(str),

            .partial_number => |num| try self.numberPart(num),
            .number => |num| try self.numberEnd(num),
            else => unreachable,
        }
    }

    fn addToPath(self: *Self, frag: []const u8) !void {
        try self.path.appendSlice(self.gpa, frag);
        print("path: {s}\n", .{self.path.items});
    }

    fn finishPath(self: *Self, frag: []const u8) !void {
        switch (self.scan_state) {
            .scan_key => {
                try self.addToPath(frag);
                if (std.mem.eql(u8, self.prefix, self.path.items)) {
                    try self.echo();
                } else {
                    try self.scan();
                }
            },
            else => {},
        }
    }

    fn triggered(self: *Self) bool {
        return std.mem.eql(u8, self.prefix, self.path.items);
    }

    fn scanArray(self: *Self) !void {
        const path_len = self.path.items.len;
        defer self.path.items.len = path_len;

        try self.addToPath("[*]");

        var tok = try self.next();
        while (tok != .array_end) : (tok = try self.next()) {
            try self.afterToken(tok);
        }
    }

    fn scanKeyAfterToken(self: *Self, tok: Scanner.Token) !void {
        try self.path.append(self.gpa, '.');
        var nt = tok;
        key: while (true) : (nt = try self.next()) {
            switch (nt) {
                .partial_string => |frag| try self.addToPath(frag),
                .partial_string_escaped_1 => |frag| try self.addToPath(&frag),
                .partial_string_escaped_2 => |frag| try self.addToPath(&frag),
                .partial_string_escaped_3 => |frag| try self.addToPath(&frag),
                .partial_string_escaped_4 => |frag| try self.addToPath(&frag),
                .string => |frag| {
                    try self.addToPath(frag);
                    break :key;
                },
                else => unreachable,
            }
        }
    }

    fn scanObject(self: *Self) !void {
        var tok = try self.next();
        while (tok != .object_end) : (tok = try self.next()) {
            const path_len = self.path.items.len;
            defer self.path.items.len = path_len;
            try self.scanKeyAfterToken(tok);
            try self.afterToken(try self.next());
        }
    }

    fn afterToken(self: *Self, tok: Scanner.Token) anyerror!void {
        if (self.triggered())
            try self.echoAfterToken(tok)
        else
            try self.scanAfterToken(tok);
    }

    fn scanAfterToken(self: *Self, tok: Scanner.Token) !void {
        var nt = tok;
        blk: while (true) : (nt = try self.next()) {
            switch (nt) {
                .null, .false, .true => break :blk,
                .partial_string => {},
                .partial_string_escaped_1 => {},
                .partial_string_escaped_2 => {},
                .partial_string_escaped_3 => {},
                .partial_string_escaped_4 => {},
                .string => break :blk,
                .partial_number => {},
                .number => break :blk,
                .array_begin => {
                    try self.scanArray();
                    break :blk;
                },
                .object_begin => {
                    try self.scanObject();
                    break :blk;
                },
                else => unreachable,
            }
        }
    }

    pub fn scan(self: *Self) !void {
        self.path.items.len = 0;
        try self.path.append(self.gpa, '$');
        return try self.scanAfterToken(try self.next());
    }
};

pub fn main(init: std.process.Init) !void {
    var r_buf: [128 * 1024]u8 = undefined;
    var w_buf: [128 * 1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &w_buf);
    var reader = std.Io.File.stdin().reader(init.io, &r_buf);

    var filt = JsonFilter.init(init.gpa, &reader.interface, &writer.interface, "");
    defer filt.deinit();
    try filt.scan();
}
