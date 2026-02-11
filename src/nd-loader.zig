const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
// const Allocator = std.mem.Allocator;
const Io = std.Io;
const Scanner = std.json.Scanner;

const multi = @import("./json/multi.zig");
const spread = @import("./json/spread.zig");

const CouchDoc = struct {
    pub const REST = "rest";
    _id: []const u8,
    _rev: ?[]const u8,
    _deleted: ?bool,
    rest: []const u8,
};

pub fn main(init: std.process.Init) !void {
    var r_buf: [128 * 1024]u8 = undefined;
    var reader = Io.File.stdin().reader(init.io, &r_buf);

    var iter: multi.ReaderIterator = .init(init.gpa, &reader.interface);
    defer iter.deinit();

    while (try iter.next()) |rdr| {
        var arena: std.heap.ArenaAllocator = .init(init.gpa);
        defer arena.deinit();
        const gpa = arena.allocator();
        const doc = try spread.parseFromScanner(CouchDoc, gpa, rdr);
        print("_id: {s:<32}\n", .{doc._id});
    }
}
