const std = @import("std");
const print = std.debug.print;
const Value = std.json.Value;

const ibex = @import("./ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const bytes = @import("./bytes.zig");
const ByteReader = bytes.ByteReader;
const ByteWriter = bytes.ByteWriter;
const IbexNumber = @import("./IbexNumber.zig").IbexNumber;

const Self = @This();

w: *ByteWriter,

pub fn writeTag(self: *Self, tag: IbexTag) IbexError!void {
    try self.w.put(@intFromEnum(tag));
}

pub fn writeBytes(self: *Self, b: []const u8) IbexError!void {
    try self.w.append(b);
}

pub fn beginArray(self: *Self) IbexError!void {
    try self.writeTag(.Array);
}

pub fn endArray(self: *Self) IbexError!void {
    try self.writeTag(.End);
}

pub fn beginObject(self: *Self) IbexError!void {
    try self.writeTag(.Object);
}

pub fn endObject(self: *Self) IbexError!void {
    try self.writeTag(.End);
}

pub fn beginString(self: *Self) IbexError!void {
    try self.writeTag(.String);
}

pub fn endString(self: *Self) IbexError!void {
    try self.writeTag(.End);
}

pub fn writeEscapedBytes(self: *Self, b: []const u8) IbexError!void {
    // Any 0x00 / 0x01 / 0x02 in the string are escaped:
    //   0x00 => 0x02, 0x02
    //   0x01 => 0x02, 0x03
    //   0x02 => 0x02, 0x04
    var pos: usize = 0;
    while (std.mem.findAnyPos(u8, b, pos, &.{ 0x00, 0x01, 0x02 })) |esc| {
        try self.writeBytes(b[pos..esc]);
        try self.writeBytes(&.{ 0x02, b[esc] + 2 });
        pos = esc + 1;
    }
    try self.writeBytes(b[pos..b.len]);
}

pub fn writeString(self: *Self, str: []const u8) IbexError!void {
    try self.beginString();
    try self.writeEscapedBytes(str);
    try self.endString();
}

pub fn writeValue(self: *Self, v: Value) IbexError!void {
    switch (v) {
        .null => try self.write(null),
        inline .bool, .integer, .float, .string => |vv| try self.write(vv),
        .array => |a| try self.write(a.items),
        .object => |o| {
            try self.beginObject();
            var iter = o.iterator();
            while (iter.next()) |kv| {
                try self.writeString(kv.key_ptr.*);
                try self.writeValue(kv.value_ptr.*);
            }
            try self.endObject();
        },
        .number_string => unreachable,
    }
}

pub fn write(self: *Self, v: anytype) IbexError!void {
    const T = @TypeOf(v);

    if (T == Value)
        return self.writeValue(v);

    return switch (@typeInfo(T)) {
        .null => try self.writeTag(.Null),
        .bool => try self.writeTag(if (v) .True else .False),
        .int, .float => try IbexNumber(T).write(self.w, v),
        .comptime_float => try self.write(@as(f64, @floatCast(v))),
        .comptime_int => try self.write(@as(std.math.IntFittingRange(v, v), v)),
        .optional => {
            if (v) |payload|
                try self.write(payload)
            else
                try self.write(null);
        },
        .array => try self.write(&v),
        .vector => |vec| {
            const array: [vec.len]vec.child = v;
            try self.write(&array);
        },
        .pointer => |ptr| {
            switch (ptr.size) {
                .one => {
                    switch (@typeInfo(ptr.child)) {
                        .array => {
                            const E = []const std.meta.Elem(ptr.child);
                            try self.write(@as(E, v));
                        },
                        else => try self.write(v.*),
                    }
                },
                .many, .slice => {
                    if (ptr.size == .many and ptr.sentinel() == null)
                        @compileError("unable to encode type '" ++
                            @typeName(T) ++ "' without sentinel");
                    const slice = if (ptr.size == .many) std.mem.span(v) else v;
                    if (ptr.child == u8) {
                        try self.writeString(slice);
                    } else {
                        try self.beginArray();
                        for (slice) |x| try self.write(x);
                        try self.endArray();
                    }
                },
                else => unreachable,
            }
        },
        .@"struct" => |strc| {
            if (strc.is_tuple) {
                try self.beginArray();
                inline for (strc.fields) |fld| {
                    if (fld.type == void) continue;
                    try self.write(@field(v, fld.name));
                }
                try self.endArray();
            } else {
                try self.beginObject();
                inline for (strc.fields) |fld| {
                    if (fld.type == void) continue;
                    if (@typeInfo(fld.type) == .optional and @field(v, fld.name) == null)
                        continue;
                    try self.writeString(fld.name);
                    try self.write(@field(v, fld.name));
                }
                try self.endObject();
            }
        },
        else => @compileError("Unable to encode type '" ++ @typeName(T) ++ "'"),
    };
}

const bm = @import("../support/bm.zig");

fn testWrite(value: anytype, expect: []const u8) !void {
    var buf: [256]u8 = undefined;
    var bw = ByteWriter{ .buf = &buf };
    var iw = Self{ .w = &bw };
    try iw.write(value);
    // print(">> {any} ({any})\n", .{ value, @TypeOf(value) });
    // bm.hexDump(bw.slice(), 0);
    try std.testing.expectEqualDeep(expect, bw.slice());
}

fn t(tag: IbexTag) u8 {
    return @intFromEnum(tag);
}

test {
    try testWrite(null, &.{t(.Null)});
    try testWrite(false, &.{t(.False)});
    try testWrite(true, &.{t(.True)});
    try testWrite(0, &.{t(.NumPosZero)});
    try testWrite(1, &.{ t(.NumPos), 0x80, 0x00 });
    try testWrite(@as(u8, 1), &.{ t(.NumPos), 0x80, 0x00 });
    try testWrite(@as(f16, 1), &.{ t(.NumPos), 0x80, 0x00 });
    try testWrite(1.5, &.{ t(.NumPos), 0x80, 0x80 });
    try testWrite(@as(f16, 1.5), &.{ t(.NumPos), 0x80, 0x80 });
    try testWrite(@as(f32, 1.5), &.{ t(.NumPos), 0x80, 0x80 });
    try testWrite(@as(f64, 1.5), &.{ t(.NumPos), 0x80, 0x80 });
    try testWrite("Hello", .{t(.String)} ++ "Hello" ++ .{t(.End)});
    try testWrite(
        .{ .name = "Andy", .checked = false, .rate = 1.5 },
        .{t(.Object)} ++
            .{t(.String)} ++ "name" ++ .{ t(.End), t(.String) } ++ "Andy" ++ .{t(.End)} ++
            .{t(.String)} ++ "checked" ++ .{ t(.End), t(.False) } ++
            .{t(.String)} ++ "rate" ++ .{ t(.End), t(.NumPos), 0x80, 0x80 } ++
            .{t(.End)},
    );
}

test "Value" {
    try testWrite(Value{ .null = {} }, &.{t(.Null)});
    try testWrite(Value{ .bool = false }, &.{t(.False)});
    try testWrite(Value{ .integer = 0 }, &.{t(.NumPosZero)});
    try testWrite(Value{ .integer = 1 }, &.{ t(.NumPos), 0x80, 0x00 });
    try testWrite(Value{ .float = 0 }, &.{t(.NumPosZero)});
    try testWrite(Value{ .float = 1 }, &.{ t(.NumPos), 0x80, 0x00 });
    try testWrite(Value{ .string = "Hello" }, .{t(.String)} ++ "Hello" ++ .{t(.End)});
}
