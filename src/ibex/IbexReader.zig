const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Value = std.json.Value;

const ibex = @import("./ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;

const bytes = @import("./bytes.zig");
const ByteReader = bytes.ByteReader;

const IbexNumber = @import("./IbexNumber.zig").IbexNumber;

test {
    std.testing.refAllDecls(@This());
}

const Self = @This();

pub const Options = struct {
    strict_keys: bool = false,
};

r: *ByteReader,
gpa: Allocator,
opt: Options = .{},

pub const StringToken = struct {
    frag: []const u8,
    terminal: bool = false,
};

pub const StringTokeniser = struct {
    const ST = @This();
    r: *ByteReader,
    state: enum { INIT, ESCAPE, INSIDE } = .INIT,

    pub fn next(self: *ST) IbexError!StringToken {
        const tail = self.r.tail();
        switch (self.state) {
            .INIT, .INSIDE => {
                if (std.mem.findAny(u8, tail, &.{ 0x00, 0x01 })) |esc| {
                    try self.r.skip(esc + 1);
                    switch (tail[esc]) {
                        0x00 => {
                            return .{ .frag = tail[0..esc], .terminal = true };
                        },
                        0x01 => {
                            self.state = .ESCAPE;
                            return .{ .frag = tail[0..esc] };
                        },
                        else => unreachable,
                    }
                }

                return IbexError.SyntaxError;
            },
            .ESCAPE => {
                try self.r.skip(1);
                self.state = .INSIDE;
                return switch (tail[0]) {
                    0x01 => .{ .frag = "\x00" },
                    0x02 => .{ .frag = "\x01" },
                    else => IbexError.SyntaxError,
                };
            },
        }
    }
};

fn nextTag(self: *Self) IbexError!IbexTag {
    return ibex.tagFromByte(try self.r.next());
}

fn readValueTag(self: *Self, tag: IbexTag) IbexError!Value {
    _ = self;
    _ = tag;
}

pub fn readTag(self: *Self, comptime T: type, tag: IbexTag) IbexError!T {
    switch (T) {
        Value => return self.readValueTag(tag),
        else => {},
    }

    switch (@typeInfo(T)) {
        .int, .float => return IbexNumber(T).readTag(self.r, tag),
        .bool => return switch (tag) {
            .False => false,
            .True => true,
            else => IbexError.TypeMismatch,
        },
        .optional => |o| {
            return switch (tag) {
                .Null => null,
                else => try self.readTag(o.child, tag),
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
                buf[idx] = try self.readTag(arr.child, ntag);
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
            const AT = [vec.len]vec.child;
            const arr: T = try self.readTag(AT, tag);
            return arr;
        },
        .pointer => |ptr| {
            const CT = ptr.child;

            switch (ptr.size) {
                .one => {
                    const v: *CT = try self.gpa.create(CT);
                    errdefer self.gpa.destroy(v);
                    v.* = try self.readTag(CT, tag);
                    return v;
                },
                .many, .slice => {
                    var ar: std.ArrayList(CT) = .empty;
                    errdefer ar.deinit(self.gpa);

                    switch (tag) {
                        .String => {
                            if (CT != u8)
                                return IbexError.TypeMismatch;
                            var st: StringTokeniser = .{ .r = self.r };
                            while (true) {
                                const stok = try st.next();
                                try ar.appendSlice(self.gpa, stok.frag);
                                if (stok.terminal) break;
                            }
                        },
                        .Array => {
                            var ntag = try self.nextTag();
                            while (ntag != .End) : (ntag = try self.nextTag()) {
                                try ar.append(self.gpa, try self.readTag(CT, ntag));
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
            if (@hasDecl(T, "readIbex"))
                return T.readIbex(self);

            const SetType = @Int(.unsigned, strc.fields.len);
            const SetFull = std.math.maxInt(SetType);

            const optional, const defaulted = comptime blk: {
                var opt: SetType = 0;
                var def: SetType = 0;
                for (strc.fields, 0..) |f, i| {
                    if (@typeInfo(f.type) == .optional)
                        opt |= 1 << i;
                    if (f.defaultValue() != null)
                        def |= 1 << i;
                }
                break :blk .{ opt, def };
            };

            const wrapper = comptime struct {
                // TODO: why not build the index using Ibex escaped strings?
                // Then we never have to handle escaped keys explicitly
                const ix: std.StaticStringMap(usize) = blk: {
                    const KV = struct { []const u8, usize };
                    var kvs: [strc.fields.len]KV = undefined;
                    for (strc.fields, 0..) |f, i|
                        kvs[i] = .{ f.name, i };
                    break :blk .initComptime(kvs);
                };

                pub fn set(s: *Self, obj: *T, idx: usize) !void {
                    switch (idx) {
                        inline 0...strc.fields.len - 1 => |i| {
                            @field(obj, strc.fields[i].name) =
                                try s.read(strc.fields[i].type);
                        },
                        else => return IbexError.UnknownKey,
                    }
                }

                pub fn lookup(s: *Self) IbexError!?usize {
                    var st: StringTokeniser = .{ .r = s.r };
                    var stok = try st.next();

                    if (stok.terminal)
                        return ix.get(stok.frag);

                    var ar: std.ArrayList(u8) = .empty;
                    defer ar.deinit(s.gpa);

                    while (true) : (stok = try st.next()) {
                        try ar.appendSlice(s.gpa, stok.frag);
                        if (stok.terminal)
                            break;
                    }

                    return ix.get(ar.items);
                }
            };

            var obj: T = undefined;
            var seen: SetType = 0;

            if (strc.is_tuple) {
                if (tag != .Array)
                    return IbexError.TypeMismatch;

                var ntag = try self.nextTag();
                var idx: usize = 0;
                while (ntag != .End) : (ntag = try self.nextTag()) {
                    seen |= @as(SetType, 1) << @intCast(idx);
                    try wrapper.set(self, &obj, idx);
                    idx += 1;
                }
            } else {
                if (tag != .Object)
                    return IbexError.TypeMismatch;

                var ntag = try self.nextTag();
                while (ntag != .End) : (ntag = try self.nextTag()) {
                    if (ntag != .String)
                        return IbexError.TypeMismatch;

                    if (try wrapper.lookup(self)) |idx| {
                        seen |= @as(SetType, 1) << @intCast(idx);
                        try wrapper.set(self, &obj, idx);
                    } else if (self.opt.strict_keys) {
                        return IbexError.UnknownKey;
                    }
                }
            }

            if (seen != SetFull) {
                inline for (strc.fields, 0..) |f, i| {
                    const bit = @as(SetType, 1) << i;
                    if (seen & bit == 0) {
                        if (defaulted & bit != 0)
                            @field(obj, f.name) = f.defaultValue().?
                        else if (optional & bit != 0)
                            @field(obj, f.name) = null
                        else
                            return IbexError.MissingKeys;
                    }
                }
            }

            return obj;
        },
        else => @compileError("Unable to read type '" ++ @typeName(T) ++ "'"),
    }
}

pub fn read(self: *Self, comptime T: type) IbexError!T {
    return self.readTag(T, try self.nextTag());
}

fn testRead(gpa: Allocator, msg: []const u8, comptime T: type, expect: T) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var br = ByteReader{ .buf = msg };
    var ir = Self{ .gpa = arena.allocator(), .r = &br };
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
    };

    try testRead(
        gpa,
        .{t(.Object)} ++
            .{t(.String)} ++ "name" ++ .{ t(.End), t(.String) } ++ "Andy" ++ .{t(.End)} ++
            .{t(.String)} ++ "checked" ++ .{ t(.End), t(.False) } ++
            .{t(.String)} ++ "rate" ++ .{ t(.End), t(.NumPos), 0x80, 0x80 } ++
            .{t(.End)},
        S1,
        .{ .name = "Andy", .checked = false, .rate = 1.5 },
    );

    try testRead(
        gpa,
        .{t(.Object)} ++
            .{t(.String)} ++ "checked" ++ .{ t(.End), t(.False) } ++
            .{t(.String)} ++ "rate" ++ .{ t(.End), t(.NumPos), 0x80, 0x80 } ++
            .{t(.String)} ++ "name" ++ .{ t(.End), t(.String) } ++ "Andy" ++ .{t(.End)} ++
            .{t(.End)},
        S1,
        .{ .name = "Andy", .checked = false, .rate = 1.5 },
    );

    try testRead(
        gpa,
        .{t(.Object)} ++
            .{t(.String)} ++ "name" ++ .{ t(.End), t(.String) } ++ "Andy" ++ .{t(.End)} ++
            .{t(.String)} ++ "checked" ++ .{ t(.End), t(.False) } ++
            .{t(.End)},
        S1,
        .{ .name = "Andy", .checked = false, .rate = 17.5 },
    );
}
