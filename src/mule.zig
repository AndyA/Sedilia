const std = @import("std");
const print = std.debug.print;

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
