const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello!\n", .{});
}

test {
    _ = @import("./ibex/IbexInt.zig");
    _ = @import("./ibex/IbexNumber.zig");
    _ = @import("./ibex/IbexWriter.zig");
    _ = @import("./ibex/JSON.zig");
    _ = @import("./ibex/Literal.zig");
    _ = @import("./support/bm.zig");
    _ = @import("./support/wildcard.zig");
    _ = @import("./mule.zig");
}
