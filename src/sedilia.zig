const std = @import("std");
const rocksdb = @import("rocksdb");

pub fn main(init: std.process.Init) !void {
    try std.Io.Dir.createDirPath(std.Io.Dir.cwd(), init.io, "tmp");

    var err: ?rocksdb.Data = null;
    const db, const cf = try rocksdb.DB.open(
        init.gpa,
        "tmp/db.couchdb",
        .{ .create_if_missing = true },
        null,
        &err,
    );
    defer db.deinit();
    defer init.gpa.free(cf);
    std.debug.print("{any}\n", .{cf});
}

test "scratch" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    try std.Io.Dir.createDirPath(std.Io.Dir.cwd(), io, "tmp");

    var err: ?rocksdb.Data = null;
    const db, const cf = try rocksdb.DB.open(
        gpa,
        "tmp/db.couchdb",
        .{ .create_if_missing = true },
        null,
        &err,
    );
    defer db.deinit();
    defer gpa.free(cf);

    // std.debug.print("{any}\n", .{cf});
}

test {
    _ = @import("./tree.zig");
    _ = @import("./ibex/IbexInt.zig");
    _ = @import("./ibex/IbexNumber.zig");
    _ = @import("./ibex/IbexValue.zig");
    _ = @import("./support/bm.zig");
    _ = @import("./support/wildcard.zig");
    _ = @import("./mule.zig");
}
