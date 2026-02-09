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
    reader: Scanner.Reader,
    writer: *std.Io.Writer,
    stringify: Stringify = undefined,
    prefix: []const u8,
    foo: [128 * 1024]u8 = undefined,

    path: std.ArrayList(u8) = .empty,

    pub fn init(
        gpa: Allocator,
        reader: *std.Io.Reader,
        writer: *std.Io.Writer,
        prefix: []const u8,
    ) Self {
        return Self{
            .gpa = gpa,
            .reader = Scanner.Reader.init(gpa, reader),
            .writer = writer,
            // .stringify = Stringify{ .writer = writer },
            .prefix = prefix,
        };
    }

    pub fn deinit(self: *Self) void {
        self.path.deinit(self.gpa);
        self.reader.deinit();
    }

    fn next(self: *Self) !Scanner.Token {
        return try self.reader.next();
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

    fn encodeChars(self: *Self, frag: []const u8) !void {
        try Stringify.encodeJsonStringChars(frag, .{}, self.stringify.writer);
    }

    fn echoPartialAfterToken(self: *Self, tok: Scanner.Token) anyerror!void {
        const sfy = &self.stringify;
        var ntok = tok;
        blk: while (true) : (ntok = try self.next()) {
            switch (ntok) {
                .partial_number => |str| try sfy.writer.writeAll(str),
                .number => |str| {
                    try sfy.writer.writeAll(str);
                    break :blk;
                },
                .partial_string => |str| try self.encodeChars(str),
                .partial_string_escaped_1 => |str| try self.encodeChars(&str),
                .partial_string_escaped_2 => |str| try self.encodeChars(&str),
                .partial_string_escaped_3 => |str| try self.encodeChars(&str),
                .partial_string_escaped_4 => |str| try self.encodeChars(&str),
                .string => |str| {
                    try self.encodeChars(str);
                    break :blk;
                },
                else => unreachable,
            }
        }
    }

    fn echoStringBodyAfterToken(self: *Self, tok: Scanner.Token) !void {
        const sfy = &self.stringify;
        try sfy.writer.writeByte('"');
        try self.echoPartialAfterToken(tok);
        try sfy.writer.writeByte('"');
    }

    fn echoObject(self: *Self) anyerror!void {
        const sfy = &self.stringify;
        var tok = try self.next();
        try sfy.beginObject();
        while (tok != .object_end) : (tok = try self.next()) {
            try sfy.beginObjectFieldRaw();
            try self.echoStringBodyAfterToken(tok);
            sfy.endObjectFieldRaw();
            try self.echoAfterToken(try self.next());
        }
        try sfy.endObject();
    }

    fn echoStringAfterToken(self: *Self, tok: Scanner.Token) !void {
        const sfy = &self.stringify;
        try sfy.beginWriteRaw();
        try self.echoStringBodyAfterToken(tok);
        sfy.endWriteRaw();
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

            .partial_number, .number => {
                try sfy.beginWriteRaw();
                try self.echoPartialAfterToken(tok);
                sfy.endWriteRaw();
            },

            .partial_string => try self.echoStringAfterToken(tok),
            .partial_string_escaped_1 => try self.echoStringAfterToken(tok),
            .partial_string_escaped_2 => try self.echoStringAfterToken(tok),
            .partial_string_escaped_3 => try self.echoStringAfterToken(tok),
            .partial_string_escaped_4 => try self.echoStringAfterToken(tok),
            .string => try self.echoStringAfterToken(tok),

            else => unreachable,
        }
    }

    fn scanArray(self: *Self) !void {
        const path_len = self.path.items.len;
        defer self.path.items.len = path_len;

        try self.addToPath("[*]");

        var tok = try self.next();
        while (tok != .array_end) : (tok = try self.next()) {
            try self.walkAfterToken(tok);
        }
    }

    fn addToPath(self: *Self, frag: []const u8) !void {
        try self.path.appendSlice(self.gpa, frag);
    }

    fn scanKeyAfterToken(self: *Self, tok: Scanner.Token) !void {
        try self.path.append(self.gpa, '.');
        var ntok = tok;
        key: while (true) : (ntok = try self.next()) {
            switch (ntok) {
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
            try self.walkAfterToken(try self.next());
        }
    }

    fn walkAfterToken(self: *Self, tok: Scanner.Token) anyerror!void {
        if (std.mem.eql(u8, self.prefix, self.path.items)) {
            self.stringify = Stringify{ .writer = self.writer };
            try self.echoAfterToken(tok);
            try self.stringify.writer.writeByte('\n');
        } else {
            try self.scanAfterToken(tok);
        }
    }

    fn scanAfterToken(self: *Self, tok: Scanner.Token) !void {
        var ntok = tok;
        blk: while (true) : (ntok = try self.next()) {
            switch (ntok) {
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

    pub fn transform(self: *Self) !void {
        self.path.items.len = 0;
        try self.path.append(self.gpa, '$');
        return try self.walkAfterToken(try self.next());
    }
};

pub fn main(init: std.process.Init) !void {
    var r_buf: [128 * 1024]u8 = undefined;
    var w_buf: [128 * 1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &w_buf);
    var reader = std.Io.File.stdin().reader(init.io, &r_buf);

    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);

    var filt = JsonFilter.init(init.gpa, &reader.interface, &writer.interface, args[1]);
    defer filt.deinit();
    try filt.transform();

    try writer.interface.flush();
}
