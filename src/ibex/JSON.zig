const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ibex = @import("./ibex.zig");
const IbexError = ibex.IbexError;
const IbexWriter = @import("./IbexWriter.zig");
const isNumberFormattedLikeAnInteger = std.json.Scanner.isNumberFormattedLikeAnInteger;

const JSON = @This();

json: []const u8,

const JSONWriter = struct {
    const Self = @This();

    gpa: Allocator,
    w: *IbexWriter,
    state: enum { INIT, STRING, NUMBER } = .INIT,
    num_buf: std.ArrayList(u8) = .empty,

    pub fn deinit(self: *Self) void {
        self.num_buf.deinit(self.gpa);
    }

    fn partialString(self: *Self, str: []const u8) IbexError!void {
        switch (self.state) {
            .INIT => {
                try self.w.beginString();
                self.state = .STRING;
            },
            .STRING => {},
            else => unreachable,
        }
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

                .partial_string => |str| try self.partialString(str),
                .partial_string_escaped_1 => |str| try self.partialString(&str),
                .partial_string_escaped_2 => |str| try self.partialString(&str),
                .partial_string_escaped_3 => |str| try self.partialString(&str),
                .partial_string_escaped_4 => |str| try self.partialString(&str),

                .string => |str| {
                    try self.partialString(str);
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
