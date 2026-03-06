const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const assert = std.debug.assert;

fn zeroPad(gpa: Allocator, str: []const u8, quant: usize) ![]const u8 {
    const buf_size = ((str.len + quant - 1) / quant) * quant;
    const buf = try gpa.alloc(u8, buf_size);
    @memcpy(buf[0..str.len], str);
    @memset(buf[str.len..buf_size], 0);
    return buf;
}

const Teddy = struct {
    const Self = @This();
    const ChunkBytes = 16;
    const Chunk = @Vector(ChunkBytes, u8);

    groups: [8]?[]const u8 = undefined,

    fn makeSets(self: Self) [256]u8 {
        var set_map: [256]u8 = @splat(0);
        for (self.groups, 0..) |group, i| {
            if (group) |g| {
                const mask = @as(u8, 1) << @intCast(i);
                for (g) |char| {
                    set_map[char] |= mask;
                }
            }
        }
        return set_map;
    }

    fn makeNybbleSets(self: Self) struct { Chunk, Chunk } {
        var lo_map: [16]u8 = @splat(0);
        var hi_map: [16]u8 = @splat(0);
        for (self.makeSets(), 0..) |mask, i| {
            const index: u8 = @intCast(i);
            lo_map[index & 0x0f] |= mask;
            hi_map[index >> 4] |= mask;
        }
        return .{ lo_map, hi_map };
    }

    // end from https://gist.github.com/sharpobject/80dc1b6f3aaeeada8c0e3a04ebc4b60a
    fn lookupX86(x: Chunk, mask: Chunk) Chunk {
        return asm (
            \\vpshufb %[mask], %[x], %[out]
            : [out] "=x" (-> Chunk),
            : [x] "x" (x),
              [mask] "x" (mask),
        );
    }
    // https://ziggit.dev/t/simd-is-there-an-equivalent-to-mm-shuffle-ep/2251/6
    // https://developer.arm.com/architectures/instruction-sets/intrinsics/vqtbl1q_s8
    fn lookupAarch64(x: Chunk, mask: Chunk) Chunk {
        return asm (
            \\tbl  %[out].16b, {%[mask].16b}, %[x].16b
            : [out] "=&x" (-> Chunk),
            : [x] "x" (x),
              [mask] "x" (mask),
        );
    }

    fn lookup(x: Chunk, mask: Chunk) Chunk {
        return switch (builtin.cpu.arch) {
            .aarch64, .aarch64_be => lookupAarch64(x, mask),
            .x86_64 => lookupX86(x, mask),
            else => @compileError("Unsupported Arch"),
        };
    }

    pub fn search(self: Self, gpa: Allocator, haystack: []const u8) !void {
        const buf = try zeroPad(gpa, haystack, @sizeOf(Chunk));
        defer gpa.free(buf);
        const lo_map, const hi_map = self.makeNybbleSets();
        var pos: usize = 0;
        const lo_mask: Chunk = @splat(0x0f);
        const hi_shift: Chunk = @splat(4);
        while (pos != buf.len) {
            const chars: Chunk = buf[pos..][0..ChunkBytes].*;
            const lo_chars: Chunk = chars & lo_mask;
            const hi_chars: Chunk = chars >> hi_shift;
            const lo_sets = lookup(lo_chars, lo_map);
            const hi_sets = lookup(hi_chars, hi_map);
            const sets: Chunk = lo_sets & hi_sets;
            print("sets: {any}\n", .{sets});
            pos += ChunkBytes;
        }
    }
};

test Teddy {
    const gpa = std.testing.allocator;
    const teddy = Teddy{ .groups = .{
        "0123456789",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "abc",
        "defghijklmnopqrstuvwxyz",
        "Hel",
        null,
        null,
        null,
    } };

    try teddy.search(gpa, "Hello, World");
}

pub fn main() !void {
    print("Hello!\n", .{});
}

test {
    _ = @import("./ibex/Ibex.zig");
    _ = @import("./json/spread.zig");
    _ = @import("./json/multi.zig");
    _ = @import("./support/bm.zig");
    _ = @import("./support/wildcard.zig");
    _ = @import("./nd-loader.zig");
}
