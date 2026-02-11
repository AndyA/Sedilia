const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
// const Allocator = std.mem.Allocator;
const Io = std.Io;
const Scanner = std.json.Scanner;

const rocksdb = @import("rocksdb");

const multi = @import("./json/multi.zig");
const spread = @import("./json/spread.zig");

const IbexWriter = @import("./ibex/IbexWriter.zig");
const bm = @import("./support/bm.zig");

const CouchDoc = struct {
    pub const REST = "rest";
    _id: []const u8,
    _rev: ?[]const u8,
    _deleted: ?bool,
    rest: []const u8,
};

const CouchHeader = struct {
    pub const Self = @This();
    rev: ?[]const u8,
    deleted: ?bool,

    pub fn fromDoc(doc: CouchDoc) Self {
        return Self{ .rev = doc._rev, .deleted = doc._deleted };
    }
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);

    var r_buf: [128 * 1024]u8 = undefined;
    var reader = Io.File.stdin().reader(init.io, &r_buf);

    var err: ?rocksdb.Data = null;
    const db, const cf = rocksdb.DB.open(
        init.gpa,
        args[0],
        .{ .create_if_missing = true },
        null,
        &err,
    ) catch |e| {
        std.debug.print("{s}: {s}\n", .{ @errorName(e), err.?.data });
        return e;
    };
    defer db.deinit();
    defer init.gpa.free(cf);

    var iter: multi.ReaderIterator = .init(init.gpa, &reader.interface);
    defer iter.deinit();

    var more = true;
    var count: usize = 0;
    while (more) {
        const batch = rocksdb.batch.WriteBatch.init();
        defer batch.deinit();

        for (1..1000) |_| {
            const rdr = try iter.next();
            if (rdr == null) {
                more = false;
                break;
            }
            var arena: std.heap.ArenaAllocator = .init(init.gpa);
            defer arena.deinit();
            const gpa = arena.allocator();
            const doc = try spread.parseFromScanner(CouchDoc, gpa, rdr.?);
            if (count % 10000 == 0)
                print("{d:>10} _id: {s:<32}\n", .{ count, doc._id });
            var writer: Io.Writer.Allocating = .init(gpa);
            defer writer.deinit();

            const hdr: CouchHeader = .fromDoc(doc);
            var iw: IbexWriter = .init(&writer.writer);
            try iw.write(hdr);

            try writer.writer.writeAll(doc.rest);

            const body = try writer.toOwnedSlice();
            defer gpa.free(body);

            batch.put(cf[0].handle, doc._id, body);
            count += 1;
        }

        db.write(batch, &err) catch |e| {
            std.debug.print("{s}: {s}\n", .{ @errorName(e), err.?.data });
            return e;
        };
    }
}
