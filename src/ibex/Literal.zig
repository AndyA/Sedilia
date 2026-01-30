const std = @import("std");
const IbexError = @import("./ibex.zig").IbexError;

const IbexWriter = @import("./IbexWriter.zig");

const Self = @This();

ibex: []const u8,

pub fn writeIbex(self: *const Self, w: *IbexWriter) IbexError!void {
    try w.writeBytes(self.ibex);
}
