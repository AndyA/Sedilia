const std = @import("std");
const rocksdb = @import("rocksdb");

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    var err: ?rocksdb.Data = null;
    const db, const cf = try rocksdb.DB.open(
        gpa,
        "tmp/db.couchdb",
        .{ .create_if_missing = true },
        null,
        &err,
    );
    defer db.deinit();
    // _ = cf;
    std.debug.print("{any}\n", .{cf});
}

test {
    _ = @import("./tree.zig");
    _ = @import("./ibex/IbexInt.zig");
    _ = @import("./ibex/IbexNumber.zig");
    _ = @import("./ibex/IbexValue.zig");
    _ = @import("./support/bm.zig");
    _ = @import("./support/wildcard.zig");
}
