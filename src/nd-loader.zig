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
    const Self = @This();
    pub const REST = "rest";
    _id: []const u8,
    _rev: ?[]const u8,
    _deleted: ?bool,
    rest: []const u8,

    pub const Header = @Tuple(&.{ u64, bool });

    pub fn revision(self: *const Self) !u64 {
        if (self._rev) |rev| {
            if (std.mem.findScalar(u8, rev, '-')) |hyphen| {
                return try std.fmt.parseInt(u64, rev[0..hyphen], 10);
            }
            return error.SyntaxError;
        }
        return 0; // never a real rev
    }

    pub fn deleted(self: *const Self) bool {
        return self._deleted orelse false;
    }

    pub fn header(self: *const Self) !Header {
        return .{ try self.revision(), self.deleted() };
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
        args[1],
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

            var iw: IbexWriter = .init(&writer.writer);
            try iw.write(try doc.header());

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
