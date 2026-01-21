const std = @import("std");

pub const IbexClass = struct {}; // TODO

// IbexValues need at least two associated arenas - so why not limit indexes to 32
// bits, lengths to 24 bits - so a single tagged value fits in 64 bits? Or 8/32/32?

pub const IbexValue = union(enum) {
    const Self = @This();

    null,
    bool: bool,
    integer: i64,
    float: f64,
    array: []const Self,
    object: []const Self, // like an array but the first item must be a class
    string: []const u8,
    class: *const IbexClass,
    // an IbexValue can include literal fields of JSON or Ibex/Oryx
    json: []const u8,
    ibex: []const u8,
};

test {
    try std.testing.expect(@bitSizeOf(IbexValue) <= 192);
}
