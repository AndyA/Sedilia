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

    lo_map: Chunk = undefined,
    hi_map: Chunk = undefined,

    pub fn init(groups: []const []const u8) !Self {
        if (groups.len > 8)
            return error.TooManyGroups;

        // Map each byte to the bitset of groups it belongs to
        var group_map: [256]u8 = @splat(0);
        for (groups, 0..) |group, i| {
            const mask = @as(u8, 1) << @intCast(i);
            for (group) |char| {
                group_map[char] |= mask;
            }
        }

        // Split group_map into lo and hi nybble parts
        var lo_map: [16]u8 = @splat(0);
        var hi_map: [16]u8 = @splat(0);
        for (group_map, 0..) |mask, i| {
            const index: u8 = @intCast(i);
            lo_map[index & 0x0f] |= mask;
            hi_map[index >> 4] |= mask;
        }

        return Self{
            .lo_map = lo_map,
            .hi_map = hi_map,
        };
    }

    // https://ziggit.dev/t/simd-is-there-an-equivalent-to-mm-shuffle-ep/2251/6
    fn lookupX86_64(mask: Chunk, index: Chunk) Chunk {
        return asm (
            \\vpshufb %[index], %[mask], %[out]
            : [out] "=x" (-> Chunk),
            : [index] "x" (index),
              [mask] "x" (mask),
        );
    }

    fn lookupAArch64(mask: Chunk, index: Chunk) Chunk {
        return asm (
            \\tbl %[out].16b, {%[mask].16b}, %[index].16b
            : [out] "=&x" (-> Chunk),
            : [index] "x" (index),
              [mask] "x" (mask),
        );
    }

    fn lookup(mask: Chunk, index: Chunk) Chunk {
        return switch (builtin.cpu.arch) {
            .aarch64, .aarch64_be => lookupAArch64(mask, index),
            .x86_64 => lookupX86_64(mask, index),
            else => @compileError("Unsupported Arch"),
        };
    }

    pub fn search(self: Self, gpa: Allocator, haystack: []const u8) !void {
        const buf = try zeroPad(gpa, haystack, @sizeOf(Chunk));
        defer gpa.free(buf);
        var pos: usize = 0;
        const lo_mask: Chunk = @splat(0x0f);
        const hi_shift: Chunk = @splat(4);
        while (pos != buf.len) {
            const chars: Chunk = buf[pos..][0..ChunkBytes].*;
            const lo_sets = lookup(self.lo_map, chars & lo_mask);
            const hi_sets = lookup(self.hi_map, chars >> hi_shift);
            const sets: Chunk = lo_sets & hi_sets;
            print("sets: {any}\n", .{sets});
            pos += ChunkBytes;
        }
    }
};

test Teddy {
    const gpa = std.testing.allocator;
    const teddy: Teddy = try .init(&[_][]const u8{
        "0123456789",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "abc",
        "defghijklmnopqrstuvwxyz",
        "Hel",
        ",.",
        " ",
    });

    try teddy.search(gpa, "Hello, World, 123.456");
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const teddy: Teddy = try .init(&[_][]const u8{
        "0123456789",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "abc",
        "defghijklmnopqrstuvwxyz",
        "Hel",
        ",.",
        " ",
    });

    try teddy.search(gpa, "Hello, World, 123.456");
}

test {
    _ = @import("./ibex/Ibex.zig");
    _ = @import("./json/spread.zig");
    _ = @import("./json/multi.zig");
    _ = @import("./support/bm.zig");
    _ = @import("./support/wildcard.zig");
    _ = @import("./nd-loader.zig");
}
