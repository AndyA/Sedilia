const std = @import("std");
const print = std.debug.print;
const ibex = @import("./ibex.zig");
const IbexError = ibex.IbexError;
const IbexWriter = @import("./IbexWriter.zig");
const isNumberFormattedLikeAnInteger = std.json.Scanner.isNumberFormattedLikeAnInteger;

const Self = @This();

json: []const u8,

fn writeNumber(w: *IbexWriter, num: []const u8) !void {
    if (!isNumberFormattedLikeAnInteger(num)) {
        const f = std.fmt.parseFloat(f64, num) catch unreachable;
        if (std.math.isFinite(f))
            return w.write(f);
        return IbexError.Overflow;
    }

    const i = try std.fmt.parseInt(i64, num, 10);
    try w.write(i);
}

pub fn writeIbex(self: *const Self, w: *IbexWriter) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var state: enum { INIT, STRING, NUMBER } = .INIT;

    var num_buf: std.ArrayList(u8) = .empty;
    // defer num_buf.deinit(gpa);

    var scanner: std.json.Scanner = .initCompleteInput(gpa, self.json);
    // defer scanner.deinit();

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
            .string => |str| {
                switch (state) {
                    .INIT => try w.beginString(),
                    .STRING => state = .INIT,
                    else => unreachable,
                }
                try w.writeEscapedBytes(str);
                try w.endString();
            },
            .partial_string => |str| {
                if (state == .INIT) {
                    try w.beginString();
                    state = .STRING;
                }
                try w.writeEscapedBytes(str);
            },
            inline .partial_string_escaped_1,
            .partial_string_escaped_2,
            .partial_string_escaped_3,
            .partial_string_escaped_4,
            => |str| {
                if (state == .INIT) {
                    try w.beginString();
                    state = .STRING;
                }
                try w.writeEscapedBytes(&str);
            },
            .number => |num| {
                switch (state) {
                    .INIT => try writeNumber(w, num),
                    .NUMBER => {
                        try num_buf.appendSlice(gpa, num);
                        try writeNumber(w, num_buf.items);
                        state = .INIT;
                    },
                    else => unreachable,
                }
            },
            .partial_number => |num| {
                if (state == .INIT) {
                    num_buf.items.len = 0;
                    state = .NUMBER;
                }
                try num_buf.appendSlice(gpa, num);
            },
            else => unreachable,
        }
    }
}
