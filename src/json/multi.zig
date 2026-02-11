const std = @import("std");

const assert = std.debug.assert;
const print = std.debug.print;

const Allocator = std.mem.Allocator;

const Stringify = std.json.Stringify;
const Scanner = std.json.Scanner;

pub const ReaderIterator = struct {
    const Self = @This();

    // TODO diagnostics

    gpa: Allocator,
    reader: *std.Io.Reader,
    previous: ?*Scanner.Reader = null,

    pub fn init(gpa: Allocator, reader: *std.Io.Reader) Self {
        return Self{ .gpa = gpa, .reader = reader };
    }

    pub fn deinit(self: *Self) void {
        if (self.previous) |prev| {
            prev.deinit();
            self.gpa.destroy(prev);
        }
    }

    fn isInterObject(c: u8) bool {
        return std.ascii.isWhitespace(c) or c == ',';
    }

    fn scannerResidue(scanner: *const Scanner) []const u8 {
        return scanner.input[scanner.cursor..scanner.input.len];
    }

    fn skipInterSlice(str: []const u8) []const u8 {
        for (str, 0..) |c, i| {
            if (!isInterObject(c))
                return str[i..str.len];
        }
        return "";
    }

    pub fn tail(self: *const Self) []const u8 {
        if (self.previous) |prev| {
            return skipInterSlice(scannerResidue(&prev.scanner));
        }
        return "";
    }

    fn hasMore(self: *Self) !bool {
        while (true) {
            const nc = self.reader.peekByte() catch |err| switch (err) {
                error.EndOfStream => return false,
                else => |other_err| return other_err,
            };
            if (!isInterObject(nc)) return true;
            self.reader.toss(1);
        }
    }

    fn makeReader(self: *Self, feed: []const u8) !*Scanner.Reader {
        const rdr = try self.gpa.create(Scanner.Reader);
        rdr.* = .init(self.gpa, self.reader);
        rdr.scanner.feedInput(feed);
        self.previous = rdr;
        return rdr;
    }

    fn isFinished(scanner: *const Scanner) bool {
        return scanner.state == .post_value and scanner.stackHeight() == 0;
    }

    pub fn next(self: *Self) !?*Scanner.Reader {
        if (self.previous) |prev| {
            defer {
                prev.deinit();
                self.gpa.destroy(prev);
            }

            assert(isFinished(&prev.scanner));

            // If there's anything left feed it to the next scanner
            const residue = self.tail();
            if (residue.len > 0)
                return self.makeReader(residue);

            self.previous = null;

            // If the previous scanner hit the end of input we're done
            if (prev.scanner.is_end_of_input)
                return null;
        }

        // Advance past whitespace, commas and check we're not EOF.
        if (!try self.hasMore())
            return null;

        return self.makeReader("");
    }
};

fn consume(rdr: *Scanner.Reader) !void {
    while (true) {
        const tok = try rdr.next();
        switch (tok) {
            .end_of_document => unreachable,
            .number, .partial_number => |str| print(
                "tok: .{{ .{s} = {s}}}\n",
                .{ @tagName(tok), str },
            ),
            .string,
            .partial_string,
            => |str| print(
                "tok: .{{ .{s} = \"{s}\"}}\n",
                .{ @tagName(tok), str },
            ),
            inline .partial_string_escaped_1,
            .partial_string_escaped_2,
            .partial_string_escaped_3,
            .partial_string_escaped_4,
            => |str| print(
                "tok: .{{ .{s} = \"{s}\"}}\n",
                .{ @tagName(tok), &str },
            ),
            else => print("tok: {any}\n", .{tok}),
        }
        if (rdr.stackHeight() == 0)
            break;
    }

    print("state: {any}\n", .{rdr.scanner.state});
}

test {
    var reader = std.Io.Reader.fixed(
        \\{}
        \\{"tags": ["zig", "couchdb", "rocksdb", 123]}
    );
    var iter = ReaderIterator.init(std.testing.allocator, &reader);
    defer iter.deinit();
    while (try iter.next()) |rdr| {
        try consume(rdr);
    }
}
