const std = @import("std");

const assert = std.debug.assert;
const print = std.debug.print;

const Allocator = std.mem.Allocator;

const Stringify = std.json.Stringify;
const Scanner = std.json.Scanner;

const Json = @import("../ibex/Json.zig");

fn isSpread(comptime T: type) bool {
    return @hasDecl(T, "REST");
}

fn spreadProxy(comptime T: type) type {
    assert(isSpread(T));
    return struct {
        const Self = @This();
        const fields = @typeInfo(T).@"struct".fields;
        const SetType = @Int(.unsigned, fields.len);

        const part_ix: usize = blk: {
            for (fields, 0..) |f, i| {
                if (std.mem.eql(u8, T.REST, f.name)) {
                    if (f.type != []const u8)
                        @compileError("part field must be a []const u8]");
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

        pub const FieldNames = ix.keys();

        const init_seen = blk: {
            var set: [fields.len]bool = @splat(false);
            set[part_ix] = true;
            break :blk set;
        };

        seen: [fields.len]bool = init_seen,
        obj: T = undefined,

        pub fn setDefaults(self: *Self) !void {
            inline for (fields, 0..) |f, i| {
                if (!self.seen[i]) {
                    if (f.defaultValue()) |*dv|
                        @field(self.obj, f.name) = dv.*
                    else if (@typeInfo(f.type) == .optional)
                        @field(self.obj, f.name) = null
                    else
                        return error.MissingField;
                    self.seen[i] = true;
                }
            }
        }

        fn parseField(
            comptime idx: usize,
            gpa: Allocator,
            source: anytype,
        ) std.json.ParseError(@TypeOf(source.*))!fields[idx].type {
            const options: std.json.ParseOptions = .{
                .max_value_len = std.json.default_max_value_len,
                .allocate = .alloc_always,
            };
            return try std.json.innerParse(fields[idx].type, gpa, source, options);
        }

        pub fn setField(
            self: *Self,
            idx: usize,
            gpa: Allocator,
            source: anytype,
        ) std.json.ParseError(@TypeOf(source.*))!void {
            switch (idx) {
                inline 0...fields.len - 1 => |i| {
                    if (i != part_ix) {
                        if (self.seen[i])
                            return error.DuplicateField;
                        @field(self.obj, fields[i].name) = try parseField(i, gpa, source);
                        self.seen[i] = true;
                    }
                },
                else => unreachable,
            }
        }

        pub fn setRest(self: *Self, json: []const u8) void {
            @field(self.obj, T.REST) = json;
        }

        pub fn lookupField(_: *const Self, name: []const u8) ?usize {
            return ix.get(name);
        }
    };
}

pub fn parseFromScanner(comptime T: type, gpa: Allocator, scanner: anytype) !T {
    assert(isSpread(T));
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const tmp_gpa = arena.allocator();

    var proxy: spreadProxy(T) = .{};

    var writer: std.Io.Writer.Allocating = .init(gpa);
    errdefer writer.deinit();
    var stringify: Stringify = .{ .writer = &writer.writer };
    try stringify.beginObject();

    if (try scanner.next() != .object_begin)
        return error.UnexpectedToken;

    var tok = try scanner.nextAlloc(tmp_gpa, .alloc_if_needed);
    while (tok != .object_end) : (tok = try scanner.nextAlloc(tmp_gpa, .alloc_if_needed)) {
        switch (tok) {
            .string, .allocated_string => |field| {
                if (proxy.lookupField(field)) |idx| {
                    if (tok == .allocated_string)
                        tmp_gpa.free(field);
                    try proxy.setField(idx, gpa, scanner);
                } else {
                    try stringify.objectField(field);
                    if (tok == .allocated_string)
                        tmp_gpa.free(field);
                    try Json.cleanJson(tmp_gpa, scanner, &stringify);
                }
            },
            else => return error.UnexpectedToken,
        }
    }

    try proxy.setDefaults();
    try stringify.endObject();
    proxy.setRest(try writer.toOwnedSlice());

    return proxy.obj;
}

pub fn parseSpread(comptime T: type, gpa: Allocator, json: []const u8) !T {
    var scanner: Scanner = .initCompleteInput(gpa, json);
    defer scanner.deinit();
    return parseFromScanner(T, gpa, &scanner);
}

const CouchDoc = struct {
    pub const REST = "rest";
    _id: []const u8,
    _rev: ?[]const u8,
    _deleted: ?bool,
    rest: []const u8,
};

const TestCase = struct { json: []const u8, doc: CouchDoc };

test parseSpread {
    const cases = &[_]TestCase{.{ .json =
        \\{ 
        \\  "_id": "peb673391", 
        \\  "title": "Hello, World!\n", 
        \\  "_deleted": true,
        \\  "tags": ["zig", "rocks", "couchdb"]
        \\}
    , .doc = .{ ._id = "peb673391", ._deleted = true, ._rev = null, .rest =
        \\{"title":"Hello, World!\n","tags":["zig","rocks","couchdb"]}
    } }};

    for (cases) |tc| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const doc = try parseSpread(CouchDoc, arena.allocator(), tc.json);
        try std.testing.expectEqualDeep(tc.doc, doc);
    }
}

pub fn stringifySpread(spread: anytype, writer: *std.Io.Writer) !void {
    const T = @TypeOf(spread);
    assert(isSpread(T));
    const fields = @typeInfo(T).@"struct".fields;
    const rest_field = T.REST;
    var stringify: Stringify = .{ .writer = writer };

    try stringify.beginObject();

    var need_comma = false;

    inline for (fields) |f| {
        if (!std.mem.eql(u8, rest_field, f.name)) {
            const value = @field(spread, f.name);
            if (@typeInfo(f.type) != .optional or value != null) {
                try stringify.objectField(f.name);
                try stringify.write(value);
                need_comma = true;
            }
        }
    }

    // Abandon stringify now and write directly

    const rest = @field(spread, rest_field);
    if (rest.len > 2) {
        if (need_comma)
            try writer.writeByte(',');
        try writer.writeAll(rest[1 .. rest.len - 1]);
    }
    try writer.writeByte('}');
}

test stringifySpread {
    const gpa = std.testing.allocator;
    const cases = &[_]TestCase{.{ .json =
        \\{"_id":"peb673391","_deleted":true,"title":"Hello, World!\n","tags":["zig","rocks"]}
    , .doc = .{ ._id = "peb673391", ._deleted = true, ._rev = null, .rest =
        \\{"title":"Hello, World!\n","tags":["zig","rocks"]}
    } }};
    for (cases) |tc| {
        var writer: std.Io.Writer.Allocating = .init(gpa);
        defer writer.deinit();
        try stringifySpread(tc.doc, &writer.writer);
        const got = try writer.toOwnedSlice();
        defer gpa.free(got);
        // print("got: {s}\n", .{got});
        try std.testing.expectEqualDeep(tc.json, got);
    }
}
