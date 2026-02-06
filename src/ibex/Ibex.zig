const std = @import("std");
const ibx = @import("./support/types.zig");
const IbexTag = ibx.IbexTag;
const IbexError = ibx.IbexError;
const skipper = @import("./support/skipper.zig");

pub const IbexWriter = @import("./IbexWriter.zig");
pub const IbexReader = @import("./IbexReader.zig");
pub const Json = @import("./Json.zig");

test {
    std.testing.refAllDecls(@This());
}

const Self = @This();

ibex: []const u8,

pub fn writeToIbex(self: *const Self, w: *IbexWriter) IbexError!void {
    try w.writeBytes(self.ibex);
}

pub fn readFromIbex(r: *IbexReader, tag: IbexTag) IbexError!Self {
    const before = r.r.pos - 1; // adjust for tag
    try skipper.skipAfterTag(&r.r, tag);
    return Self{ .ibex = try r.gpa.dupe(u8, r.r.buf[before..r.r.pos]) };
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    Json.ibexToJson(self.ibex, writer) catch return error.WriteFailed;
}
