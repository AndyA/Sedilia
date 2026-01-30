const IbexError = @import("./ibex.zig").IbexError;
const IbexWriter = @import("./IbexWriter.zig");

ibex: []const u8,

pub fn writeIbex(self: *const @This(), w: *IbexWriter) IbexError!void {
    try w.writeBytes(self.ibex);
}
