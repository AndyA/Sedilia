const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const Value = std.json.Value;

test {
    _ = @import("./value.zig");
}
