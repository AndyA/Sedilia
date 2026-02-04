const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Stringify = std.json.Stringify;
const Allocator = std.mem.Allocator;

const ibex = @import("./ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const number = @import("./number/IbexNumber.zig");

const IbexReader = @import("./IbexReader.zig");
const IbexWriter = @import("./IbexWriter.zig");

const isNumberFormattedLikeAnInteger = std.json.Scanner.isNumberFormattedLikeAnInteger;

const JSON = @This();

json: []const u8,

const JSONWriter = struct {
    const Self = @This();

    gpa: Allocator,
    w: *IbexWriter,
    state: enum { INIT, STRING, NUMBER } = undefined,
    num_buf: std.ArrayList(u8) = .empty,

    pub fn deinit(self: *Self) void {
        self.num_buf.deinit(self.gpa);
    }

    fn stringPart(self: *Self, str: []const u8) IbexError!void {
        if (self.state == .INIT) {
            try self.w.beginString();
            self.state = .STRING;
        }
        assert(self.state == .STRING);
        try self.w.writeEscapedBytes(str);
    }

    fn writeNumber(w: *IbexWriter, num: []const u8) IbexError!void {
        if (!isNumberFormattedLikeAnInteger(num)) {
            const f = std.fmt.parseFloat(f64, num) catch unreachable;
            if (std.math.isFinite(f)) return w.write(f);

            const ff = std.fmt.parseFloat(f128, num) catch unreachable;
            if (std.math.isFinite(ff)) return w.write(ff);

            return IbexError.Overflow;
        }

        if (std.fmt.parseInt(i64, num, 10)) |i|
            try w.write(i)
        else |e| switch (e) {
            error.Overflow => {
                const ii = try std.fmt.parseInt(i128, num, 10);
                try w.write(ii);
            },
            else => unreachable,
        }
    }

    pub fn write(self: *Self, json: []const u8) IbexError!void {
        var scanner: std.json.Scanner = .initCompleteInput(self.gpa, json);
        defer scanner.deinit();
        var w = self.w;

        self.state = .INIT;

        doc: while (true) {
            const tok = try scanner.next();
            // print("{any}\n", .{tok});
            switch (tok) {
                .end_of_document => break :doc,

                .null => try w.write(null),
                .false => try w.write(false),
                .true => try w.write(true),

                .array_begin => try w.beginArray(),
                .array_end => try w.endArray(),
                .object_begin => try w.beginObject(),
                .object_end => try w.endObject(),

                .partial_string => |str| try self.stringPart(str),
                .partial_string_escaped_1 => |str| try self.stringPart(&str),
                .partial_string_escaped_2 => |str| try self.stringPart(&str),
                .partial_string_escaped_3 => |str| try self.stringPart(&str),
                .partial_string_escaped_4 => |str| try self.stringPart(&str),

                .string => |str| {
                    try self.stringPart(str);
                    try w.endString();
                    self.state = .INIT;
                },

                .partial_number => |num| {
                    if (self.state == .INIT) {
                        self.num_buf.items.len = 0;
                        self.state = .NUMBER;
                    }
                    assert(self.state == .NUMBER);
                    try self.num_buf.appendSlice(self.gpa, num);
                },

                .number => |num| {
                    switch (self.state) {
                        .INIT => try writeNumber(w, num), // no need to buffer
                        .NUMBER => {
                            try self.num_buf.appendSlice(self.gpa, num);
                            try writeNumber(w, self.num_buf.items);
                            self.state = .INIT;
                        },
                        else => unreachable,
                    }
                    assert(self.state == .INIT);
                },

                else => unreachable,
            }
        }
    }
};

pub fn writeIbex(self: *const JSON, w: *IbexWriter) IbexError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var writer = JSONWriter{ .gpa = arena.allocator(), .w = w };
    try writer.write(self.json);
}

fn encodeString(r: *IbexReader, writer: *std.Io.Writer) IbexError!void {
    var st = r.stringTokeniser();
    try writer.writeByte('"');
    while (true) {
        const frag = try st.next();
        try Stringify.encodeJsonStringChars(frag.frag, .{ .escape_unicode = true }, writer);
        if (frag.terminal) break;
    }
    try writer.writeByte('"');
}

fn ibexToJSONFromTag(r: *IbexReader, tag: IbexTag, sfy: *Stringify) IbexError!void {
    if (tag.isNumber()) {
        var peeker = r.r.fork();
        const meta = try number.IbexNumberMeta.fromReader(&peeker, tag);
        if (meta.intBits()) |bits| {
            if (bits <= 63) {
                const n = try r.readFromTag(i64, tag);
                return sfy.write(n);
            } else {
                const n = try r.readFromTag(i128, tag);
                return sfy.write(n);
            }
        } else {
            // TODO this test is wrong - because Ibex handles subnormal values using
            // more negative exponents. Doesn't affect correctness because f128 is
            // valid for those cases - just a bit slower.
            if (meta.exponent >= -1022 and meta.exponent <= 1023) {
                const n = try r.readFromTag(f64, tag);
                return sfy.write(n);
            } else {
                const n = try r.readFromTag(f128, tag);
                return sfy.write(n);
            }
        }
    }

    switch (tag) {
        .Null => try sfy.write(null),
        .False, .True => try sfy.write(tag == .True),
        .String => {
            try sfy.beginWriteRaw();
            try encodeString(r, sfy.writer);
            sfy.endWriteRaw();
        },
        .Array => {
            try sfy.beginArray();
            var ntag = try r.nextTag();
            while (ntag != .End) : (ntag = try r.nextTag()) {
                try ibexToJSONFromTag(r, ntag, sfy);
            }
            try sfy.endArray();
        },
        .Object => {
            try sfy.beginObject();
            var ntag = try r.nextTag();
            while (ntag != .End) : (ntag = try r.nextTag()) {
                if (ntag != .String)
                    return IbexError.TypeMismatch;
                try sfy.beginObjectFieldRaw();
                try encodeString(r, sfy.writer);
                sfy.endObjectFieldRaw();
                try ibexToJSONFromTag(r, try r.nextTag(), sfy);
            }
            try sfy.endObject();
        },
        else => unreachable,
    }
}

pub fn readIbex(r: *IbexReader, tag: IbexTag) IbexError!JSON {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.Io.Writer.Allocating.fromArrayList(r.gpa, &buf);
    errdefer w.deinit();
    var sfy = Stringify{ .writer = &w.writer };
    try ibexToJSONFromTag(r, tag, &sfy);
    return JSON{ .json = try w.toOwnedSlice() };
}
