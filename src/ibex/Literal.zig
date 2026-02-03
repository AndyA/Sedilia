const IbexError = @import("./ibex.zig").IbexError;
const IbexWriter = @import("./IbexWriter.zig");
const IbexReader = @import("./IbexReader.zig");
const skipper = @import("./skipper.zig");

const Self = @This();

ibex: []const u8,

pub fn writeIbex(self: *const Self, w: *IbexWriter) IbexError!void {
    try w.writeBytes(self.ibex);
}

pub fn readIbex(r: IbexReader) IbexError!Self {
    const before = r.r.pos;
    try skipper.skip(r);
    return Self{ .ibex = r.gpa.dupe(u8, r.r.buf[before..r.r.pos]) };
}
