const ibx = @import("./ibex.zig");
const IbexTag = ibx.IbexTag;
const IbexError = ibx.IbexError;
const IbexWriter = @import("./IbexWriter.zig");
const IbexReader = @import("./IbexReader.zig");
const skipper = @import("./skipper.zig");

const Self = @This();

ibex: []const u8,

pub fn writeIbex(self: *const Self, w: *IbexWriter) IbexError!void {
    try w.writeBytes(self.ibex);
}

pub fn readIbex(r: *IbexReader, tag: IbexTag) IbexError!Self {
    const before = r.r.pos - 1; // adjust for tag
    try skipper.skipTag(r, tag);
    return Self{ .ibex = r.gpa.dupe(u8, r.r.buf[before..r.r.pos]) };
}
