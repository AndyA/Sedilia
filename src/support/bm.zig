const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const bytes = @import("../ibex/bytes.zig");
const ByteWriter = bytes.ByteWriter;
const ByteReader = bytes.ByteReader;

pub fn bitCount(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        inline .float, .int => |info| info.bits,
        else => unreachable,
    };
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

pub fn showRate(name: []const u8, metric: []const u8, total: usize, timer: *Timer) void {
    const elapsed = timer.lap();
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

pub fn benchmarkCodec(gpa: Allocator, codec: anytype, numbers: anytype, options: BMOptions) !void {
    var enc_size: usize = undefined;
    const CT = @typeInfo(@TypeOf(numbers)).pointer.child;

    {
        var timer = try Timer.start();
        for (0..options.repeats) |_| {
            enc_size = 0;
            for (numbers) |n| {
                enc_size += codec.encodedLength(n);
            }
        }
        if (options.output)
            showRate(options.name, "encodedLength", numbers.len * options.repeats, &timer);
    }

    const enc_buf = try gpa.alloc(u8, enc_size);
    defer gpa.free(enc_buf);

    var w = ByteWriter{ .buf = enc_buf };
    {
        var timer = try Timer.start();
        for (0..options.repeats) |_| {
            w.pos = 0;
            for (numbers) |n| {
                try codec.write(&w, n);
            }
            assert(w.pos == enc_size);
        }
        if (options.output)
            showRate(options.name, "write", numbers.len * options.repeats, &timer);
    }

    const output = try gpa.alloc(CT, numbers.len);
    defer gpa.free(output);

    var r = ByteReader{ .buf = w.slice() };
    {
        var timer = try Timer.start();
        for (0..options.repeats) |_| {
            r.pos = 0;
            for (0..numbers.len) |i| {
                output[i] = try codec.read(&r);
            }
            assert(w.pos == r.pos);
        }
        if (options.output)
            showRate(options.name, "read", numbers.len * options.repeats, &timer);
    }

    for (numbers, 0..) |n, i| {
        assert(n == output[i]);
    }
}

pub fn benchmarkCodecV2(gpa: Allocator, codec: anytype, numbers: anytype, options: BMOptions) !void {
    var enc_size: usize = undefined;
    const CT = @typeInfo(@TypeOf(numbers)).pointer.child;

    {
        var timer = try Timer.start();
        for (0..options.repeats) |_| {
            enc_size = 0;
            for (numbers) |n| {
                enc_size += codec.encodedLength(n);
            }
        }
        if (options.output)
            showRate(options.name, "encodedLength", numbers.len * options.repeats, &timer);
    }

    const enc_buf = try gpa.alloc(u8, enc_size);
    defer gpa.free(enc_buf);

    {
        var timer = try Timer.start();
        for (0..options.repeats) |_| {
            var w = Writer.fixed(enc_buf);
            // defer w.deinit();
            // w.pos = 0;
            for (numbers) |n| {
                try codec.write(&w, n);
            }
            // assert(w.pos == enc_size);
        }
        if (options.output)
            showRate(options.name, "write", numbers.len * options.repeats, &timer);
    }

    const output = try gpa.alloc(CT, numbers.len);
    defer gpa.free(output);

    {
        var timer = try Timer.start();
        for (0..options.repeats) |_| {
            var r = Reader.fixed(enc_buf);
            for (0..numbers.len) |i| {
                output[i] = try codec.read(&r);
            }
        }
        if (options.output)
            showRate(options.name, "read", numbers.len * options.repeats, &timer);
    }

    for (numbers, 0..) |n, i| {
        assert(n == output[i]);
    }
}
