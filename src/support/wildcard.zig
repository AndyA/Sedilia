const std = @import("std");
const assert = std.debug.assert;

pub fn wildMatch(pattern: []const u8, target: []const u8) bool {
    // std.debug.print("wildMatch(\"{s}\", \"{s}\")\n", .{ pattern, target });
    for (pattern, 0..) |c, i| {
        if (c == '*') {
            const tail = pattern[i + 1 ..];
            var tpos = i;
            while (true) : (tpos += 1) {
                if (wildMatch(tail, target[tpos..]))
                    return true;
                if (tpos == target.len) return false;
            }
        }

        if (i == target.len)
            return false;

        if (c != '?' and c != target[i])
            return false;
    }
    return pattern.len == target.len;
}

test {
    const TC = struct {
        pattern: []const u8,
        yes: []const []const u8 = &.{},
        no: []const []const u8 = &.{},
    };

    const cases = &[_]TC{
        .{ .pattern = "", .yes = &.{""}, .no = &.{"foo"} },
        .{ .pattern = "*", .yes = &.{ "Hello", "x", "" } },
        .{ .pattern = "Hello", .yes = &.{"Hello"}, .no = &.{ "x", "Hello, World" } },
        .{ .pattern = "A?C?E", .yes = &.{ "A?C?E", "AbCdE" }, .no = &.{ "AbcdE", "Hello, World" } },
        .{ .pattern = "Aa*Bb*Cc", .yes = &.{ "AaBbCc", "AaABbBCc" }, .no = &.{ "ABC", "abc" } },
    };

    for (cases) |tc| {
        for (tc.yes) |y| {
            // std.debug.print("{s} yes: {s}\n", .{ tc.pattern, y });
            try std.testing.expect(wildMatch(tc.pattern, y));
        }
        for (tc.no) |n| {
            // std.debug.print("{s}  no: {s}\n", .{ tc.pattern, n });
            try std.testing.expect(!wildMatch(tc.pattern, n));
        }
    }
}
