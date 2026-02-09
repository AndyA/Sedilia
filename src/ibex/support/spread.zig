const std = @import("std");
const Allocator = std.mem.Allocator;

fn isSpread(comptime T: type) bool {
    return @hasDecl(T, "REST");
}

fn spreadProxy(comptime T: type) type {
    return struct {
        const fields = @typeInfo(T).@"struct".fields;
        const SetType = @Int(.unsigned, fields.len);
        const Self = @This();

        const part_ix: usize = blk: {
            for (fields, 0..) |f, i| {
                if (std.mem.eql(u8, T.REST, f.name)) {
                    if (f.type != []const u8)
                        @compileError("part field must be a []const u8");
                    break :blk i;
                }
            }

            @compileError("No part field");
        };

        const ix: std.StaticStringMap(usize) = blk: {
            const KV = struct { []const u8, usize };
            var kvs: [fields.len - 1]KV = undefined;
            var pos: usize = 0;
            for (fields, 0..) |f, i| {
                if (i != part_ix) {
                    kvs[pos] = .{ f.name, i };
                    pos += 1;
                }
            }
            break :blk .initComptime(kvs);
        };

        seen: SetType = 1 << part_ix,
        obj: T = undefined,
    };
}

test spreadProxy {
    const CouchDoc = struct {
        pub const REST = "rest";
        _id: []const u8,
        _rev: ?[]const u8,
        _deleted: ?bool,
        rest: []const u8,
    };

    const prox = spreadProxy(CouchDoc){};
    try std.testing.expectEqual(8, prox.seen);
}

pub fn parseSpread(comptime T: type, gpa: Allocator, json: []const u8) !T {
    _ = gpa;
    _ = json;
}

pub fn stringifySpread(partial: anytype, writer: std.Io.Writer) !void {
    _ = partial;
    _ = writer;
}
