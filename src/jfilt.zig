const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

fn jfilt(gpa: Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, prefix: []const u8) !void {
    _ = gpa;
    _ = reader;
    _ = writer;
    _ = prefix;
}

pub fn main(init: std.process.Init) !void {
    _ = init;
}
