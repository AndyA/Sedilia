const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const wildMatch = @import("./support/wildcard.zig").wildMatch;
const bm = @import("./support/bm.zig");

const IbexNumber = @import("./ibex/IbexNumber.zig").IbexNumber;
const IbexInt = @import("./ibex/IbexInt.zig");

const Benchmarks = struct {
    const Self = @This();

    io: std.Io,
    gpa: Allocator,

    pub fn @"IbexNumber/f64"(self: *Self, comptime name: []const u8) !void {
        const numbers = try bm.loadTestData(f64, self.io, self.gpa, "ref/testdata/f64sample.bin");
        defer self.gpa.free(numbers);
        const codec = IbexNumber(f64);
        try bm.benchmarkCodec(self.gpa, codec, numbers, .{ .repeats = 1000, .name = name });
    }

    pub fn @"IbexInt/lengths"(self: *Self, comptime name: []const u8) !void {
        const numbers = try bm.loadTestData(i64, self.io, self.gpa, "ref/testdata/i64lengths.bin");
        defer self.gpa.free(numbers);
        try bm.benchmarkCodec(self.gpa, IbexInt, numbers, .{ .repeats = 5000, .name = name });
    }
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);

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
