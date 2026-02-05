const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    print("Hello!\n", .{});
}

test {
    _ = @import("./ibex/IbexWriter.zig");
    _ = @import("./ibex/IbexReader.zig");
    _ = @import("./support/bm.zig");
    _ = @import("./support/wildcard.zig");
}
