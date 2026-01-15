const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;

const wildMatch = @import("./support/wildcard.zig").wildMatch;
const bm = @import("./support/bm.zig");
const rocksdb = @import("rocksdb");

const Benchmarks = struct {
    const Self = @This();

    io: std.Io,
    gpa: Allocator,

    const BatchSpec = struct {
        total_docs: usize,
        batch_size: usize,
        doc_size: usize,
    };

    fn batchWrite(
        self: *Self,
        comptime name: []const u8,
        comptime spec: BatchSpec,
    ) !void {
        const reps = spec.total_docs / spec.batch_size;
        const actual_docs = spec.batch_size * reps;
        var label_buf: [200]u8 = undefined;
        const label = try std.fmt.bufPrint(
            &label_buf,
            "{d:>7}/{d:>5}/{d:>6}",
            .{ actual_docs, spec.batch_size, spec.doc_size },
        );

        try std.Io.Dir.deleteTree(std.Io.Dir.cwd(), self.io, "tmp/bulk.db");

        var err: ?rocksdb.Data = null;
        const db, const cf = rocksdb.DB.open(
            self.gpa,
            "tmp/bulk.db",
            .{ .create_if_missing = true },
            null,
            &err,
        ) catch |e| {
            std.debug.print("{s}: {s}\n", .{ @errorName(e), err.?.data });
            return e;
        };
        defer db.deinit();
        defer self.gpa.free(cf);

        var prng = std.Random.DefaultPrng.init(123);
        const rand = prng.random();

        var timer = try Timer.start();

        for (0..reps) |_| {
            const batch = rocksdb.batch.WriteBatch.init();
            defer batch.deinit();
            for (0..spec.batch_size) |_| {
                const key = rand.int(u64);
                var value: [spec.doc_size]u8 = undefined;
                rand.bytes(&value);
                batch.put(cf[0].handle, std.mem.asBytes(&key), &value);
            }

            try db.write(batch, &err);
        }

        bm.showRate(name, label, actual_docs, &timer);
    }

    pub fn @"Rocks/Batch/Write"(self: *Self, comptime name: []const u8) !void {
        const total_docs = [_]usize{ 10_000, 1_000_000, 5_000_000 };
        const batch_size = [_]usize{ 10, 100, 1_000, 10_000 };
        const doc_size = [_]usize{ 100, 10_000, 100_000 };

        inline for (total_docs) |td| {
            inline for (batch_size) |bs| {
                inline for (doc_size) |ds| {
                    const spec = BatchSpec{
                        .total_docs = td,
                        .batch_size = bs,
                        .doc_size = ds,
                    };
                    try self.batchWrite(name, spec);
                }
            }
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);

    try std.Io.Dir.createDirPath(std.Io.Dir.cwd(), init.io, "tmp");

    var runner = Benchmarks{ .io = init.io, .gpa = init.gpa };

    inline for (@typeInfo(Benchmarks).@"struct".decls) |d| {
        const selected = blk: {
            if (args.len == 1)
                break :blk true;
            for (args[1..]) |arg| {
                if (wildMatch(arg, d.name))
                    break :blk true;
            }
            break :blk false;
        };
        if (selected) {
            const bm_fn = @field(Benchmarks, d.name);
            try bm_fn(&runner, d.name);
        }
    }
}
