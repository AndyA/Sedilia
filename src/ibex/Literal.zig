const std = @import("std");
const ibx = @import("./support/types.zig");
const IbexTag = ibx.IbexTag;
const IbexError = ibx.IbexError;
const IbexWriter = @import("./IbexWriter.zig");
const IbexReader = @import("./IbexReader.zig");
const Json = @import("./Json.zig");
const skipper = @import("./support/skipper.zig");

const Self = @This();

ibex: []const u8,

pub fn writeToIbex(self: *const Self, w: *IbexWriter) IbexError!void {
    try w.writeBytes(self.ibex);
}

pub fn readFromIbex(r: *IbexReader, tag: IbexTag) IbexError!Self {
    const before = r.r.pos - 1; // adjust for tag
    try skipper.skipAfterTag(r, tag);
    return Self{ .ibex = r.gpa.dupe(u8, r.r.buf[before..r.r.pos]) };
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    Json.ibexToJson(self.ibex, writer) catch return error.WriteFailed;
}
