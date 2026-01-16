const std = @import("std");
const assert = std.debug.assert;

pub fn wildMatch(pattern: []const u8, target: []const u8) bool {
    // std.debug.print("wildMatch(\"{s}\", \"{s}\")\n", .{ pattern, target });
    for (pattern, 0..) |c, pp| {
        if (c == '*') {
            const tail = pattern[pp + 1 ..];
            for (pp..target.len + 1) |tp|
                if (wildMatch(tail, target[tp..]))
                    return true;
            return false;
        }

        if (pp == target.len)
            return false;

        if (c != '?' and c != target[pp])
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
        .{ .pattern = "**", .yes = &.{ "Hello", "x", "" } },
        .{ .pattern = "***", .yes = &.{ "Hello", "x", "" } },
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
