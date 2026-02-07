const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Timer = std.time.Timer;

const bytes = @import("../ibex/support/bytes.zig");
const ByteWriter = bytes.ByteWriter;
const ByteReader = bytes.ByteReader;

pub fn bitCount(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        inline .float, .int => |info| info.bits,
        else => unreachable,
    };
}

pub fn hexDump(mem: []const u8, offset: u16) void {
    var pos: usize = 0;
    while (pos < mem.len) : (pos += 16) {
        var avail = @min(16, mem.len - pos);
        const line = mem[pos .. pos + avail];
        std.debug.print("{x:0>4} |", .{pos +% offset});
        for (line) |byte|
            std.debug.print(" {x:0>2}", .{byte});
        while (avail < 16) : (avail += 1)
            std.debug.print("   ", .{});
        std.debug.print(" | ", .{});
        for (line) |byte| {
            const rep = if (std.ascii.isPrint(byte)) byte else '.';
            std.debug.print("{c}", .{rep});
        }
        std.debug.print("\n", .{});
    }
}

pub fn loadTestData(comptime T: type, io: std.Io, gpa: Allocator, file: []const u8) ![]T {
    const IT = @Int(.unsigned, bitCount(T));

    const raw = try std.Io.Dir.cwd().readFileAlloc(io, file, gpa, .unlimited);
    defer gpa.free(raw);

    const data: []const IT = @ptrCast(@alignCast(raw));
    var buf = try gpa.alloc(T, data.len);
    for (0..data.len) |i| {
        buf[i] = @bitCast(std.mem.bigToNative(IT, data[i]));
    }
    return buf;
}

pub fn showRate(io: Io, name: []const u8, metric: []const u8, total: usize, start_ts: Io.Timestamp) void {
    const elapsed = start_ts.untilNow(io, .awake).toNanoseconds();
    // std.debug.print("elapsed={d}\n", .{elapsed});
    const seconds = @as(f64, @floatFromInt(elapsed)) / 1_000_000_000;
    const rate = @as(f64, @floatFromInt(total)) / seconds;
    std.debug.print("[ {s:<40} ] {s:>30}: {d:>20.0} / s\n", .{ name, metric, rate });
}

pub const BMOptions = struct {
    output: bool = true,
    repeats: usize,
    name: []const u8,
};

pub fn benchmarkCodec(gpa: Allocator, io: Io, codec: anytype, numbers: anytype, options: BMOptions) !void {
    var enc_size: usize = undefined;
    const CT = @typeInfo(@TypeOf(numbers)).pointer.child;

    {
        const start_ts = std.Io.Clock.awake.now(io);

        for (0..options.repeats) |_| {
            enc_size = 0;
            for (numbers) |n| {
                enc_size += codec.encodedLength(n);
            }
        }
        if (options.output) {
            const avg_bytes: f64 = @as(f64, @floatFromInt(enc_size)) /
                @as(f64, @floatFromInt(numbers.len));
            std.debug.print("# average bytes: {d}\n", .{avg_bytes});
            showRate(io, options.name, "encodedLength", numbers.len * options.repeats, start_ts);
        }
    }

    const enc_buf = try gpa.alloc(u8, enc_size);
    defer gpa.free(enc_buf);

    {
        const start_ts = std.Io.Clock.awake.now(io);
        for (0..options.repeats) |_| {
            var writer = std.Io.Writer.fixed(enc_buf);
            var w = ByteWriter{ .writer = &writer };
            for (numbers) |n| {
                try codec.write(&w, n);
            }
        }
        if (options.output)
            showRate(io, options.name, "write", numbers.len * options.repeats, start_ts);
    }

    const output = try gpa.alloc(CT, numbers.len);
    defer gpa.free(output);

    // hexDump(enc_buf[0..0x80], 0);

    {
        const start_ts = std.Io.Clock.awake.now(io);
        for (0..options.repeats) |_| {
            var r = ByteReader{ .buf = enc_buf };
            for (0..numbers.len) |i| {
                output[i] = try codec.read(&r);
            }
        }
        if (options.output)
            showRate(io, options.name, "read", numbers.len * options.repeats, start_ts);
    }

    for (numbers, 0..) |n, i| {
        assert(n == output[i]);
    }
}
