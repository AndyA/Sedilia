const std = @import("std");
const Timer = std.time.Timer;
const assert = std.debug.assert;

const bm = @import("../support/bm.zig");

const table = blk: {
    var t: [200]u8 = undefined;
    for (0..10) |h| {
        for (0..10) |l| {
            const slot = (h * 10 + l) * 2;
            t[slot] = 0x30 + h;
            t[slot + 1] = 0x30 + l;
        }
    }
    break :blk t;
};

fn makePicker(comptime size: usize, comptime in_bits: u16, comptime out_bits: u16) @Vector(size, i32) {
    var pv: [size]i32 = undefined;
    var pos = 0;
    for (0..size) |i| {
        pv[i] = pos;
        pos += in_bits / out_bits;
    }
    return @bitCast(pv);
}

fn compactor(
    comptime size: usize,
    comptime IT: type,
    comptime OT: type,
) type {
    const in_bits = @typeInfo(IT).int.bits;
    const out_bits = @typeInfo(OT).int.bits;
    assert(in_bits % out_bits == 0);

    const picker = blk: {
        var pv: [size]i32 = undefined;
        const stride = in_bits / out_bits;
        for (0..size) |i| {
            pv[i] = i * stride;
        }
        break :blk @as(@Vector(size, i32), @bitCast(pv));
    };

    return struct {
        pub fn compact(input: @Vector(size, IT)) @Vector(size, OT) {
            const v1: @Vector(size * in_bits / out_bits, OT) = @bitCast(input);
            std.debug.print("picker: {any}\n", .{picker});
            std.debug.print("v1: {any}\n", .{v1});

            return @shuffle(OT, v1, v1, picker);
        }
    };
}

const k10000: @Vector(2, u32) = @splat(10000);
const k100: @Vector(4, u16) = @splat(100);
const k10: @Vector(8, u8) = @splat(10);
const kzero: @Vector(16, u8) = @splat('0');

const mask1 = @Vector(4, i32){ @as(i32, 0), ~@as(i32, 0), @as(i32, 2), ~@as(i32, 2) };
const mask2 = @Vector(8, i32){
    @as(i32, 0),
    ~@as(i32, 0),
    @as(i32, 2),
    ~@as(i32, 2),
    @as(i32, 4),
    ~@as(i32, 4),
    @as(i32, 6),
    ~@as(i32, 6),
};
const mask3 = @Vector(16, i32){
    @as(i32, 0),
    ~@as(i32, 0),
    @as(i32, 1),
    ~@as(i32, 1),
    @as(i32, 2),
    ~@as(i32, 2),
    @as(i32, 3),
    ~@as(i32, 4),
    @as(i32, 4),
    ~@as(i32, 4),
    @as(i32, 5),
    ~@as(i32, 5),
    @as(i32, 6),
    ~@as(i32, 6),
    @as(i32, 7),
    ~@as(i32, 7),
};

fn toDecimalV3(value: u64, buf: *[16]u8) void {
    const v1: @Vector(2, u32) = .{
        @intCast(value / 100000000),
        @intCast(value % 100000000),
    };
    const d1: @Vector(4, u16) = @bitCast(v1 / k10000);
    const m1: @Vector(4, u16) = @bitCast(v1 % k10000);

    const v2: @Vector(4, u16) = @shuffle(u16, d1, m1, mask1);
    const d2: @Vector(8, u8) = @bitCast(v2 / k100);
    const m2: @Vector(8, u8) = @bitCast(v2 % k100);

    const v3: @Vector(8, u8) = @shuffle(u8, d2, m2, mask2);
    const d3 = v3 / k10;
    const m3 = v3 % k10;

    const v4: @Vector(16, u8) = @shuffle(u8, d3, m3, mask3) + kzero;
    const c4: [16]u8 = @bitCast(v4);
    @memcpy(buf, &c4);
}

fn toDecimal(value: u64, buf: *[16]u8) void {
    const t, const b = .{ value / 100000000, value % 100000000 };
    const tt, const tb = .{ t / 10000, t % 10000 };
    const bt, const bb = .{ b / 10000, b % 10000 };
    const ttt, const ttb = .{ tt / 100, tt % 100 };
    const tbt, const tbb = .{ tb / 100, tb % 100 };
    const btt, const btb = .{ bt / 100, bt % 100 };
    const bbt, const bbb = .{ bb / 100, bb % 100 };

    // std.debug.print(
    //     "t={d}, b={d}, " ++
    //         "tt={d}, tb={d}, bt={d}, bb={d}, " ++
    //         "ttt={d}, ttb={d}, tbt={d}, tbb={d}, " ++
    //         "btt={d}, btb={d}, bbt={d}, bbb={d}",
    //     .{ t, b, tt, tb, bt, bb, ttt, ttb, tbt, tbb, btt, btb, bbt, bbb },
    // );

    buf[0] = table[2 * ttt];
    buf[1] = table[2 * ttt + 1];
    buf[2] = table[2 * ttb];
    buf[3] = table[2 * ttb + 1];
    buf[4] = table[2 * tbt];
    buf[5] = table[2 * tbt + 1];
    buf[6] = table[2 * tbb];
    buf[7] = table[2 * tbb + 1];
    buf[8] = table[2 * btt];
    buf[9] = table[2 * btt + 1];
    buf[10] = table[2 * btb];
    buf[11] = table[2 * btb + 1];
    buf[12] = table[2 * bbt];
    buf[13] = table[2 * bbt + 1];
    buf[14] = table[2 * bbb];
    buf[15] = table[2 * bbb + 1];
}

const REPEATS = 1000;

pub fn main() !void {
    var buf: [16]u8 = undefined;
    var numbers: [100_000]u64 = undefined;

    var prng: std.Random.DefaultPrng = .init(123);
    const rand = prng.random();
    for (&numbers) |*n| {
        n.* = rand.intRangeAtMost(u64, 0, 10_000_000_000_000_000 - 1);
    }

    const fns = &[_][]const u8{ "toDecimal", "toDecimalV3" };
    inline for (fns) |name| {
        const impl = @field(@This(), name);

        impl(numbers[0], &buf);
        std.debug.print("# {s:>20} {d:>16} => {s}\n", .{ name, numbers[0], buf });

        var timer = try Timer.start();
        var snot: u8 = 0;
        for (0..REPEATS) |_| {
            for (numbers, 0..) |n, i| {
                impl(n, &buf);
                snot ^= buf[i % 16];
            }
        }
        std.debug.print("# snot: {x}\n", .{snot});
        bm.showRate(name, "encode", numbers.len * REPEATS, &timer);
    }
}
