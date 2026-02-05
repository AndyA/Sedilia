const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Stringify = std.json.Stringify;
const Scanner = std.json.Scanner;
const Allocator = std.mem.Allocator;

const types = @import("./support/types.zig");
const IbexTag = types.IbexTag;
const IbexError = types.IbexError;
const number = @import("./number/IbexNumber.zig");

const IbexReader = @import("./IbexReader.zig");
const IbexWriter = @import("./IbexWriter.zig");

const Json = @This();

json: []const u8,

const JsonWriter = struct {
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
        // TODO it may be quicker just to always use f128?
        if (!Scanner.isNumberFormattedLikeAnInteger(num)) {
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
        var scanner: Scanner = .initCompleteInput(self.gpa, json);
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

pub fn writeToIbex(self: *const Json, w: *IbexWriter) IbexError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var writer = JsonWriter{ .gpa = arena.allocator(), .w = w };
    try writer.write(self.json);
}

fn encodeString(r: *IbexReader, writer: *std.Io.Writer) IbexError!void {
    var st = r.stringTokeniser();
    try writer.writeByte('"');
    while (true) {
        const frag = try st.next();
        try Stringify.encodeJsonStringChars(frag.frag, .{}, writer);
        if (frag.terminal) break;
    }
    try writer.writeByte('"');
}

fn ibexToJsonAfterTag(r: *IbexReader, tag: IbexTag, sfy: *Stringify) IbexError!void {
    if (tag.isNumber()) {
        var peeker = r.r.fork();
        const meta = try number.IbexNumberMeta.fromReader(&peeker, tag);
        if (meta.intBits()) |bits| {
            if (bits <= 63) {
                const n = try r.readAfterTag(i64, tag);
                return sfy.write(n);
            } else {
                const n = try r.readAfterTag(i128, tag);
                return sfy.write(n);
            }
        } else {
            // TODO this test is wrong - because Ibex handles subnormal values using
            // more negative exponents. Doesn't affect correctness because f128 is
            // valid for those cases - just a bit slower.
            if (meta.exponent >= -1022 and meta.exponent <= 1023) {
                const n = try r.readAfterTag(f64, tag);
                return sfy.write(n);
            } else {
                const n = try r.readAfterTag(f128, tag);
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
                try ibexToJsonAfterTag(r, ntag, sfy);
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
                try ibexToJsonAfterTag(r, try r.nextTag(), sfy);
            }
            try sfy.endObject();
        },
        .End => return IbexError.SyntaxError,
        else => unreachable,
    }
}

pub fn readFromIbex(r: *IbexReader, tag: IbexTag) IbexError!Json {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.Io.Writer.Allocating.fromArrayList(r.gpa, &buf);
    errdefer w.deinit();
    var sfy = Stringify{ .writer = &w.writer };
    try ibexToJsonAfterTag(r, tag, &sfy);
    return Json{ .json = try w.toOwnedSlice() };
}

// Useful transformations

const bytes = @import("./support/bytes.zig");

const JsonCleaner = struct {
    const Self = @This();
    scanner: *Scanner,
    stringify: *Stringify,
    state: enum { INIT, STRING, NUMBER } = .INIT,

    fn stringPart(self: *Self, frag: []const u8) IbexError!void {
        const sfy = self.stringify;
        if (self.state == .INIT) {
            try sfy.beginWriteRaw();
            try sfy.writer.writeByte('"');
            self.state = .STRING;
        }
        assert(self.state == .STRING);
        try Stringify.encodeJsonStringChars(frag, .{}, sfy.writer);
    }

    fn stringEnd(self: *Self, frag: []const u8) IbexError!void {
        const sfy = self.stringify;
        try self.stringPart(frag);
        try sfy.writer.writeByte('"');
        sfy.endWriteRaw();
        self.state = .INIT;
    }

    fn numberPart(self: *Self, frag: []const u8) IbexError!void {
        const sfy = self.stringify;
        if (self.state == .INIT) {
            try sfy.beginWriteRaw();
            self.state = .NUMBER;
        }
        assert(self.state == .NUMBER);
        try sfy.writer.writeAll(frag);
    }

    fn numberEnd(self: *Self, frag: []const u8) IbexError!void {
        const sfy = self.stringify;
        try self.numberPart(frag);
        sfy.endWriteRaw();
        self.state = .INIT;
    }

    pub fn transform(self: *Self) IbexError!void {
        const sfy = self.stringify;
        doc: while (true) {
            const tok = try self.scanner.next();
            // print("{any}\n", .{tok});
            switch (tok) {
                .end_of_document => break :doc,

                .null => try sfy.write(null),
                .false => try sfy.write(false),
                .true => try sfy.write(true),

                .array_begin => try sfy.beginArray(),
                .array_end => try sfy.endArray(),
                .object_begin => try sfy.beginObject(),
                .object_end => try sfy.endObject(),

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

        assert(self.state == .INIT);
    }
};

const WritingTransform = fn (Allocator, []const u8, *std.Io.Writer) IbexError!void;
const AllocatingTransform = fn (Allocator, []const u8) IbexError![]const u8;

fn allocatingTransform(comptime trans_fn: WritingTransform) AllocatingTransform {
    const shim = struct {
        pub fn transform(gpa: Allocator, data: []const u8) IbexError![]const u8 {
            var writer = std.Io.Writer.Allocating.init(gpa);
            errdefer writer.deinit();
            try trans_fn(gpa, data, &writer.writer);
            return try writer.toOwnedSlice();
        }
    };

    return shim.transform;
}

/// Validate and minify Json
pub fn jsonToJson(gpa: Allocator, json: []const u8, writer: *std.Io.Writer) IbexError!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var scanner: Scanner = .initCompleteInput(arena.allocator(), json);
    defer scanner.deinit();
    var stringify = Stringify{ .writer = writer };
    var cleaner = JsonCleaner{ .scanner = &scanner, .stringify = &stringify };
    try cleaner.transform();
}

pub fn jsonToJsonAllocating(gpa: Allocator, json: []const u8) IbexError![]const u8 {
    return try allocatingTransform(jsonToJson)(gpa, json);
}

const TestCase = struct { input: []const u8, want: []const u8 };

fn testTransform(gpa: Allocator, transform: AllocatingTransform, cases: []const TestCase) !void {
    for (cases) |tc| {
        const got = try transform(gpa, tc.input);
        defer gpa.free(got);
        // print("want: \"{s}\", got: \"{s}\n", .{ tc.want, got });
        try std.testing.expectEqualDeep(tc.want, got);
    }
}

fn t(tag: IbexTag) u8 {
    return @intFromEnum(tag);
}

test jsonToJson {
    const gpa = std.testing.allocator;

    const cases = &[_]TestCase{
        .{ .input = "null", .want = "null" },
        .{ .input = "[1, false, \"Hello\"]", .want = "[1,false,\"Hello\"]" },
    };

    try testTransform(gpa, jsonToJsonAllocating, cases);
}

pub fn jsonToIbex(gpa: Allocator, json: []const u8, writer: *std.Io.Writer) IbexError!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var bw = bytes.ByteWriter{ .writer = writer };
    var iw = IbexWriter{ .w = &bw };
    var jw = JsonWriter{ .gpa = arena.allocator(), .w = &iw };
    try jw.write(json);
}

pub fn jsonToIbexAllocating(gpa: Allocator, json: []const u8) IbexError![]const u8 {
    return try allocatingTransform(jsonToIbex)(gpa, json);
}

test jsonToIbex {
    const gpa = std.testing.allocator;

    const cases = &[_]TestCase{.{
        .input =
        \\{ "name": "Andy", "checked": false, "rate": 1.5}
        ,
        .want = .{t(.Object)} ++
            .{t(.String)} ++ "name" ++ .{ t(.End), t(.String) } ++ "Andy" ++ .{t(.End)} ++
            .{t(.String)} ++ "checked" ++ .{ t(.End), t(.False) } ++
            .{t(.String)} ++ "rate" ++ .{ t(.End), t(.NumPos), 0x80, 0x80 } ++
            .{t(.End)},
    }};

    try testTransform(gpa, jsonToIbexAllocating, cases);
}

test "jsonToIbex fuzz" {
    const gpa = std.testing.allocator;
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            const got = jsonToIbexAllocating(gpa, input) catch return;
            defer gpa.free(got);
            print("{s}\n", .{input});
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{ .corpus = &.{
        \\{ "name": "Andy", "checked": false, "rate": 1.5, tags: ["zig", "c"]}
        ,
        \\null
        ,
        \\[1000000, 1e10, -3.1415]
        ,
        \\"\u0000\u0001\u0002\u02fe"
        ,
        \\[{ "funky\n": true }]
    } });
}

pub fn ibexToJson(gpa: Allocator, ibex: []const u8, writer: *std.Io.Writer) IbexError!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var br = bytes.ByteReader{ .buf = ibex };
    var ir = IbexReader{ .gpa = arena.allocator(), .r = &br };
    var sfy = Stringify{ .writer = writer };
    try ibexToJsonAfterTag(&ir, try ir.nextTag(), &sfy);
}

pub fn ibexToJsonAllocating(gpa: Allocator, ibex: []const u8) IbexError![]const u8 {
    return try allocatingTransform(ibexToJson)(gpa, ibex);
}

test ibexToJson {
    const gpa = std.testing.allocator;

    const cases = &[_]TestCase{.{
        .input = .{t(.Object)} ++
            .{t(.String)} ++ "name" ++ .{ t(.End), t(.String) } ++ "Andy" ++ .{t(.End)} ++
            .{t(.String)} ++ "checked" ++ .{ t(.End), t(.False) } ++
            .{t(.String)} ++ "rate" ++ .{ t(.End), t(.NumPos), 0x80, 0x80 } ++
            .{t(.End)},
        .want =
        \\{"name":"Andy","checked":false,"rate":1.5}
        ,
    }};

    try testTransform(gpa, ibexToJsonAllocating, cases);
}

// test "ibexToJson fuzz" {
//     const gpa = std.testing.allocator;
//     const Context = struct {
//         fn testOne(context: @This(), input: []const u8) anyerror!void {
//             _ = context;
//             const got = ibexToJsonAllocating(gpa, input) catch return;
//             defer gpa.free(got);
//             // print("{s}\n", .{got});
//         }
//     };
//     try std.testing.fuzz(Context{}, Context.testOne, .{});
// }
