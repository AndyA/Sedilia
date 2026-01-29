const std = @import("std");
const ibex = @import("./ibex.zig");
const IbexError = ibex.IbexError;

const IbexWriter = @import("./IbexWriter.zig");

const Self = @This();

json: []const u8,

pub fn writeIbex(self: *const Self, w: *IbexWriter) IbexError!void {
    _ = self;
    _ = w;
    unreachable;
}
