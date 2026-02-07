const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const wildMatch = @import("./support/wildcard.zig").wildMatch;
const bm = @import("./support/bm.zig");

const IbexNumber = @import("./ibex/number/IbexNumber.zig").IbexNumber;
const IbexVarInt = @import("./ibex/number/IbexVarInt.zig");

fn i64inRange(gpa: Allocator, count: usize, comptime RT: type) ![]i64 {
    var arr = try gpa.alloc(i64, count);
    errdefer gpa.free(arr);

    var prng: std.Random.DefaultPrng = .init(123);
    const rand = prng.random();

    for (0..count) |i| {
        arr[i] = rand.int(RT);
    }

    return arr;
}

fn benchmarkIntRange(gpa: Allocator, io: Io, comptime T: type, comptime options: bm.BMOptions) !void {
    const ints = try i64inRange(gpa, 1_000_000, T);
    defer gpa.free(ints);
    try bm.benchmarkCodec(gpa, io, IbexVarInt, ints, options);
}

const Benchmarks = struct {
    const Self = @This();

    io: std.Io,
    gpa: Allocator,

    const BASE = 500;

    pub fn @"IbexNumber/f64"(self: *Self, comptime name: []const u8) !void {
        const numbers = try bm.loadTestData(f64, self.io, self.gpa, "ref/testdata/f64sample.bin");
        defer self.gpa.free(numbers);
        const codec = IbexNumber(f64);
        try bm.benchmarkCodec(self.gpa, self.io, codec, numbers, .{ .repeats = BASE * 1, .name = name });
    }

    pub fn @"IbexVarInt/lengths"(self: *Self, comptime name: []const u8) !void {
        const numbers = try bm.loadTestData(i64, self.io, self.gpa, "ref/testdata/i64lengths.bin");
        defer self.gpa.free(numbers);
        try bm.benchmarkCodec(self.gpa, self.io, IbexVarInt, numbers, .{ .repeats = BASE, .name = name });
    }

    pub fn @"IbexVarInt/u7"(self: *Self, comptime name: []const u8) !void {
        try benchmarkIntRange(self.gpa, self.io, u7, .{ .repeats = BASE, .name = name });
    }

    pub fn @"IbexVarInt/u8"(self: *Self, comptime name: []const u8) !void {
        try benchmarkIntRange(self.gpa, self.io, u8, .{ .repeats = BASE, .name = name });
    }

    pub fn @"IbexVarInt/i8"(self: *Self, comptime name: []const u8) !void {
        try benchmarkIntRange(self.gpa, self.io, i8, .{ .repeats = BASE, .name = name });
    }

    pub fn @"IbexVarInt/i9"(self: *Self, comptime name: []const u8) !void {
        try benchmarkIntRange(self.gpa, self.io, i9, .{ .repeats = BASE, .name = name });
    }

    pub fn @"IbexVarInt/u16"(self: *Self, comptime name: []const u8) !void {
        try benchmarkIntRange(self.gpa, self.io, u16, .{ .repeats = BASE, .name = name });
    }

    pub fn @"IbexVarInt/i16"(self: *Self, comptime name: []const u8) !void {
        try benchmarkIntRange(self.gpa, self.io, i16, .{ .repeats = BASE, .name = name });
    }

    pub fn @"IbexVarInt/u32"(self: *Self, comptime name: []const u8) !void {
        try benchmarkIntRange(self.gpa, self.io, u32, .{ .repeats = BASE, .name = name });
    }

    pub fn @"IbexVarInt/i32"(self: *Self, comptime name: []const u8) !void {
        try benchmarkIntRange(self.gpa, self.io, i32, .{ .repeats = BASE, .name = name });
    }

    pub fn @"IbexVarInt/i64"(self: *Self, comptime name: []const u8) !void {
        try benchmarkIntRange(self.gpa, self.io, i64, .{ .repeats = BASE, .name = name });
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
