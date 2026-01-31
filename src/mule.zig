const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello!\n", .{});
}

test {
    _ = @import("./ibex/IbexWriter.zig");
    _ = @import("./support/bm.zig");
    _ = @import("./support/wildcard.zig");
}
