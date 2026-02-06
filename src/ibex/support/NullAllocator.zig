const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const mem = std.mem;

const NullAllocator = @This();

pub fn allocator(self: *NullAllocator) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = Allocator.noAlloc,
            .resize = Allocator.noResize,
            .remap = Allocator.noRemap,
            .free = Allocator.noFree,
        },
    };
}

pub fn threadSafeAllocator(self: *NullAllocator) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = Allocator.noAlloc,
            .resize = Allocator.noResize,
            .remap = Allocator.noRemap,
            .free = Allocator.noFree,
        },
    };
}
