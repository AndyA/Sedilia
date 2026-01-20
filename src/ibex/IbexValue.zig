const std = @import("std");

pub const IbexClass = struct {}; // TODO

pub const IbexValue = union(u8) {
    const Self = @This();

    null,
    boolean: bool,
    int: i64,
    float: f64,
    array: []Self,
    object: []Self, // like an array but the first item must be a class
    string: []u8,
    class: *IbexClass,
    // an IbexValue can include literal fields of JSON or Ibex/Oryx
    json: []u8,
    ibex: []u8,
};

test {
    // std.debug.print("Hello!\n", .{});
}
