const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Value = std.json.Value;

const types = @import("./support/types.zig");
const IbexTag = types.IbexTag;
const IbexError = types.IbexError;

const bytes = @import("./support/bytes.zig");
const ByteReader = bytes.ByteReader;

const number = @import("./number/IbexNumber.zig");
const skipper = @import("./support/skipper.zig");

const StringTokeniser = @import("./support/StringTokeniser.zig");

fn ObjectProxy(comptime T: type) type {
    const fields = @typeInfo(T).@"struct".fields;
    const SetType = @Int(.unsigned, fields.len);

    return struct {
        const OP = @This();
        seen: SetType = 0,
        obj: T = undefined,

        const ix: std.StaticStringMap(usize) = blk: {
            const KV = struct { []const u8, usize };
            var kvs: [fields.len]KV = undefined;
            for (fields, 0..) |f, i|
                kvs[i] = .{ f.name, i };
            break :blk .initComptime(kvs);
        };

        pub fn lookupKey(_: *const OP, rdr: *Self) IbexError!?usize {
            var st = rdr.stringTokeniser();
            var stok = try st.next();

            if (stok.terminal)
                return ix.get(stok.frag);

            var ar: std.ArrayList(u8) = .empty;
            defer ar.deinit(rdr.gpa);

            while (true) : (stok = try st.next()) {
                try ar.appendSlice(rdr.gpa, stok.frag);
                if (stok.terminal)
                    break;
            }

            return ix.get(ar.items);
        }

        pub fn readField(self: *OP, rdr: *Self, idx: usize) !void {
            switch (idx) {
                inline 0...fields.len - 1 => |i| {
                    self.seen |= @as(SetType, 1) << i;
                    @field(self.obj, fields[i].name) =
                        try rdr.read(fields[i].type);
                },
                else => return IbexError.UnknownKey,
            }
        }

        pub fn cleanup(self: *OP) IbexError!T {
            if (~self.seen == 0)
                return self.obj;

            inline for (fields, 0..) |f, i| {
                if ((self.seen & @as(SetType, 1) << i) == 0) {
                    if (f.defaultValue()) |*dv|
                        @field(self.obj, f.name) = dv.*
                    else if (@typeInfo(f.type) == .optional)
                        @field(self.obj, f.name) = null
                    else
                        return IbexError.MissingKeys;
                }
            }

            return self.obj;
        }
    };
}

const Self = @This();

pub const Options = struct {
    strict_keys: bool = false,
};

r: ByteReader,
gpa: Allocator,
opt: Options = .{},

pub fn initWithOptions(gpa: Allocator, ibex: []const u8, opt: Options) Self {
    return Self{
        .gpa = gpa,
        .r = bytes.ByteReader{ .buf = ibex },
        .opt = opt,
    };
}

pub fn init(gpa: Allocator, ibex: []const u8) Self {
    return initWithOptions(gpa, ibex, .{});
}

fn skipPastZero(self: *Self) IbexError!void {
    if (std.mem.findScalar(u8, self.r.tail(), 0x00)) |pos|
        return self.r.skip(pos + 1);

    return IbexError.SyntaxError;
}

pub fn nextTag(self: *Self) IbexError!IbexTag {
    while (true) {
        const tag = try self.r.nextTag();
        if (tag != .Collation) return tag;
        try self.skipPastZero();
    }
}

fn readValue(self: *Self, tag: IbexTag) IbexError!Value {
    if (tag.isNumber()) {
        var peeker = self.r.fork();
        const meta = try number.IbexNumberMeta.fromReaderAfterTag(&peeker, tag);
        if (meta.intBits()) |_|
            return Value{ .integer = try number.IbexNumber(i64).read(self.r) }
        else
            return Value{ .float = try number.IbexNumber(f64).read(self.r) };
    }

    switch (tag) {
        .Null => return Value{ .null = {} },
        .False => return Value{ .bool = false },
        .True => return Value{ .bool = true },
        .String => {
            const str = try self.readAfterTag([]const u8, tag);
            return Value{ .string = str };
        },
        .Array => {
            var arr: std.json.Array = .init(self.gpa);
            errdefer arr.deinit();

            var ntag = try self.nextTag();
            while (ntag != .End) : (ntag = try self.nextTag()) {
                try arr.append(self.readValue(ntag));
            }
            return Value{ .array = arr };
        },
        .Object => {
            var obj: std.json.ObjectMap = .init(self.gpa);
            errdefer obj.deinit();

            var ntag = try self.nextTag();
            while (ntag != .End) : (ntag = try self.nextTag()) {
                const key = try self.readAfterTag([]const u8, ntag);
                const value = try self.readValue(try self.nextTag());
                try obj.put(key, value);
            }

            return Value{ .object = obj };
        },
        .End => return IbexError.SyntaxError,
        else => unreachable,
    }
}

pub fn stringTokeniser(self: *Self) StringTokeniser {
    return .{ .r = &self.r };
}

pub fn readAfterTag(self: *Self, comptime T: type, tag: IbexTag) IbexError!T {
    switch (T) {
        Value => return self.readValue(tag),
        else => {},
    }

    switch (@typeInfo(T)) {
        .int, .float => return number.IbexNumber(T).readAfterTag(&self.r, tag),
        .bool => return switch (tag) {
            .False => false,
            .True => true,
            else => IbexError.TypeMismatch,
        },
        .optional => |o| {
            return switch (tag) {
                .Null => null,
                else => try self.readAfterTag(o.child, tag),
            };
        },
        .array => |arr| {
            if (tag != .Array)
                return IbexError.TypeMismatch;
            var buf: T = undefined;
            var ntag = try self.nextTag();
            var idx: usize = 0;
            while (ntag != .End) : (ntag = try self.nextTag()) {
                if (idx == arr.len)
                    return IbexError.ArraySizeMismatch;
                buf[idx] = try self.readAfterTag(arr.child, ntag);
                idx += 1;
            }

            if (idx < buf.len) {
                if (@typeInfo(arr.child) == .optional)
                    @memset(buf[idx..buf.len], null)
                else
                    return IbexError.ArraySizeMismatch;
            }

            return buf;
        },
        .vector => |vec| {
            return @as(T, try self.readAfterTag([vec.len]vec.child, tag));
        },
        .pointer => |ptr| {
            const CT = ptr.child;

            switch (ptr.size) {
                .one => {
                    const v: *CT = try self.gpa.create(CT);
                    errdefer self.gpa.destroy(v);
                    v.* = try self.readAfterTag(CT, tag);
                    return v;
                },
                .many, .slice => {
                    var ar: std.ArrayList(CT) = .empty;
                    errdefer ar.deinit(self.gpa);

                    switch (tag) {
                        .String => {
                            if (CT != u8)
                                return IbexError.TypeMismatch;
                            var st = self.stringTokeniser();
                            while (true) {
                                const stok = try st.next();
                                try ar.appendSlice(self.gpa, stok.frag);
                                if (stok.terminal) break;
                            }
                        },
                        .Array => {
                            var ntag = try self.nextTag();
                            while (ntag != .End) : (ntag = try self.nextTag()) {
                                try ar.append(self.gpa, try self.readAfterTag(CT, ntag));
                            }
                        },
                        else => return IbexError.TypeMismatch,
                    }

                    if (ptr.sentinel()) |sentinel| {
                        const sl = try ar.toOwnedSliceSentinel(self.gpa, sentinel);
                        return @ptrCast(sl);
                    } else {
                        const sl = try ar.toOwnedSlice(self.gpa);
                        return @ptrCast(sl);
                    }
                },
                else => unreachable,
            }
        },
        .@"struct" => |strc| {
            if (@hasDecl(T, "readFromIbex"))
                return T.readFromIbex(self, tag);

            var prox = ObjectProxy(T){};

            if (strc.is_tuple) {
                if (tag != .Array)
                    return IbexError.TypeMismatch;

                var ntag = try self.nextTag();
                var idx: usize = 0;
                while (ntag != .End) : (ntag = try self.nextTag()) {
                    try prox.readField(self, idx);
                    idx += 1;
                }
            } else {
                if (tag != .Object)
                    return IbexError.TypeMismatch;

                var ntag = try self.nextTag();
                while (ntag != .End) : (ntag = try self.nextTag()) {
                    if (ntag != .String)
                        return IbexError.TypeMismatch;

                    if (try prox.lookupKey(self)) |idx| {
                        try prox.readField(self, idx);
                    } else if (self.opt.strict_keys) {
                        return IbexError.UnknownKey;
                    } else {
                        try skipper.skip(&self.r);
                    }
                }
            }

            return prox.cleanup();
        },
        else => @compileError("Unable to read type '" ++ @typeName(T) ++ "'"),
    }
}

pub fn read(self: *Self, comptime T: type) IbexError!T {
    return self.readAfterTag(T, try self.nextTag());
}

fn testRead(gpa: Allocator, msg: []const u8, comptime T: type, expect: T) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var ir = Self{ .gpa = arena.allocator(), .r = ByteReader{ .buf = msg } };
    const got: T = try ir.read(T);
    try std.testing.expectEqualDeep(expect, got);
}

fn t(tag: IbexTag) u8 {
    return @intFromEnum(tag);
}

test {
    const gpa = std.testing.allocator;
    try testRead(gpa, &.{ t(.NumPos), 0x80, 0x00 }, i64, 1);
    try testRead(gpa, &.{t(.False)}, bool, false);
    try testRead(gpa, &.{ t(.NumPos), 0x80, 0x00 }, ?i64, 1);
    try testRead(gpa, &.{t(.Null)}, ?i64, null);

    const n1: f64 = 1.5;
    try testRead(gpa, &.{ t(.NumPos), 0x80, 0x80 }, *const f64, &n1);
    try testRead(gpa, .{t(.String)} ++ "Hello" ++ .{t(.End)}, []const u8, "Hello");
    try testRead(
        gpa,
        &.{ t(.Array), t(.False), t(.True), t(.False), t(.End) },
        []const bool,
        &.{ false, true, false },
    );
    try testRead(
        gpa,
        &.{ t(.Array), t(.False), t(.True), t(.False), t(.End) },
        [3]bool,
        .{ false, true, false },
    );
    try testRead(
        gpa,
        &.{ t(.Array), t(.False), t(.True), t(.End) },
        [3]?bool,
        .{ false, true, null },
    );
    try testRead(
        gpa,
        &.{ t(.Array), t(.False), t(.True), t(.False), t(.End) },
        *const [3]bool,
        &.{ false, true, false },
    );
    try testRead(
        gpa,
        &.{ t(.Array), t(.False), t(.True), t(.False), t(.End) },
        @Vector(3, bool),
        .{ false, true, false },
    );

    const S1 = struct {
        name: []const u8,
        checked: bool,
        rate: f64 = 17.5,
        tags: ?[]const []const u8,
    };

    try testRead(
        gpa,
        .{t(.Object)} ++
            .{t(.String)} ++ "name" ++ .{ t(.End), t(.String) } ++ "Andy" ++ .{t(.End)} ++
            .{t(.String)} ++ "checked" ++ .{ t(.End), t(.False) } ++
            .{t(.String)} ++ "rate" ++ .{ t(.End), t(.NumPos), 0x80, 0x80 } ++
            .{t(.End)},
        S1,
        .{ .name = "Andy", .checked = false, .rate = 1.5, .tags = null },
    );

    try testRead(
        gpa,
        .{t(.Object)} ++
            .{t(.String)} ++ "checked" ++ .{ t(.End), t(.False) } ++
            .{t(.String)} ++ "rate" ++ .{ t(.End), t(.NumPos), 0x80, 0x80 } ++
            .{t(.String)} ++ "name" ++ .{ t(.End), t(.String) } ++ "Andy" ++ .{t(.End)} ++
            .{t(.End)},
        S1,
        .{ .name = "Andy", .checked = false, .rate = 1.5, .tags = null },
    );

    try testRead(
        gpa,
        .{t(.Object)} ++
            .{t(.String)} ++ "name" ++ .{ t(.End), t(.String) } ++ "Andy" ++ .{t(.End)} ++
            .{t(.String)} ++ "checked" ++ .{ t(.End), t(.False) } ++
            .{t(.End)},
        S1,
        .{ .name = "Andy", .checked = false, .rate = 17.5, .tags = null },
    );

    try testRead(
        gpa,
        .{t(.Object)} ++
            .{t(.String)} ++ "name" ++ .{ t(.End), t(.String) } ++ "Andy" ++ .{t(.End)} ++
            .{t(.String)} ++ "checked" ++ .{ t(.End), t(.False) } ++
            .{t(.String)} ++ "tags" ++ .{t(.End)} ++
            .{t(.Array)} ++
            "" ++ .{t(.String)} ++ "zig" ++ .{t(.End)} ++
            "" ++ .{t(.String)} ++ "c" ++ .{t(.End)} ++
            "" ++ .{t(.String)} ++ "perl" ++ .{t(.End)} ++
            "" ++ .{t(.End)} ++
            .{t(.End)},
        S1,
        .{ .name = "Andy", .checked = false, .rate = 17.5, .tags = &.{ "zig", "c", "perl" } },
    );

    try testRead(
        gpa,
        .{t(.Object)} ++
            .{t(.String)} ++ "name" ++ .{ t(.End), t(.String) } ++ "Andy" ++ .{t(.End)} ++
            .{t(.String)} ++ "unknown key" ++ .{ t(.End), t(.True) } ++
            .{t(.String)} ++ "checked" ++ .{ t(.End), t(.False) } ++
            .{t(.End)},
        S1,
        .{ .name = "Andy", .checked = false, .rate = 17.5, .tags = null },
    );
}

test "readFromIbex Json" {
    const Json = @import("./Json.zig");
    const gpa = std.testing.allocator;

    try testRead(gpa, &.{t(.Null)}, Json, .{ .json = "null" });
    try testRead(gpa, &.{ t(.NumPos), 0x80, 0x00 }, Json, .{ .json = "1" });

    try testRead(
        gpa,
        .{t(.Object)} ++
            .{t(.String)} ++ "name" ++ .{ t(.End), t(.String) } ++ "Andy" ++ .{t(.End)} ++
            .{t(.String)} ++ "checked" ++ .{ t(.End), t(.False) } ++
            .{t(.String)} ++ "tags" ++ .{t(.End)} ++
            .{t(.Array)} ++
            "" ++ .{t(.String)} ++ "zig" ++ .{t(.End)} ++
            "" ++ .{t(.String)} ++ "c" ++ .{t(.End)} ++
            "" ++ .{t(.String)} ++ "perl" ++ .{t(.End)} ++
            "" ++ .{t(.End)} ++
            .{t(.End)},
        Json,
        .{ .json =
        \\{"name":"Andy","checked":false,"tags":["zig","c","perl"]}
    },
    );
}
