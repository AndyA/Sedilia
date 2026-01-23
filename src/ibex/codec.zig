const std = @import("std");
const print = std.debug.print;

const ibex = @import("./ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const bytes = @import("./bytes.zig");
const ByteReader = bytes.ByteReader;
const ByteWriter = bytes.ByteWriter;
const IbexNumber = @import("./IbexNumber.zig");

test {
    // print("Hello\n", .{});
}

pub const IbexWriter = struct {
    const Self = @This();

    w: *ByteWriter,

    pub fn writeTag(self: *Self, tag: IbexTag) !void {
        try self.w.put(@intFromEnum(tag));
    }

    pub fn beginArray(self: *Self) !void {
        try self.writeTag(.Array);
    }

    pub fn endArray(self: *Self) !void {
        try self.writeTag(.End);
    }

    pub fn beginObject(self: *Self) !void {
        try self.writeTag(.Object);
    }

    pub fn endObject(self: *Self) !void {
        try self.writeTag(.End);
    }

    pub fn writeString(self: *Self, str: []const u8) !void {
        try self.writeTag(.String);
        // Any 0x00 / 0x01 / 0x02 in the string are escaped:
        //   0x00 => 0x02, 0x01
        //   0x01 => 0x02, 0x02
        //   0x02 => 0x02, 0x03
        var tail = str;
        while (std.mem.findAny(u8, tail, &.{ 0x00, 0x01, 0x02 })) |esc| {
            try self.w.append(tail[0..esc]);
            try self.w.append(&.{ 0x02, tail[esc] + 1 });
            tail = tail.slice[esc + 1 .. tail.len];
        }
        try self.w.append(tail);
    }

    pub fn write(self: *Self, v: anytype) !void {
        const T = @TypeOf(v);
        switch (@typeInfo(T)) {
            .null => try self.writeTag(.Null),
            .bool => try self.writeTag(if (v) .True else .False),
            inline .int, .float => {
                try IbexNumber(T).write(self.w, v);
            },
            .comptime_float => {
                try self.write(@as(f64, @floatCast(v)));
            },
            .comptime_int => {
                try self.write(@as(std.math.IntFittingRange(v, v), v));
            },
            .optional => {
                if (v) |payload| {
                    try self.write(payload);
                } else {
                    try self.write(null);
                }
            },
            .@"struct" => |strc| {
                if (strc.is_tuple) {
                    try self.beginArray();
                    inline for (strc.fields) |F| {
                        if (F.type == void) continue;
                        try self.write(@field(v, F.name));
                    }
                    try self.endArray();
                } else {
                    try self.beginObject();
                    inline for (strc.fields) |F| {
                        if (F.type == void) continue;
                        if (@typeInfo(F.type) == .optional and @field(v, F.name) == null)
                            continue;
                        try self.writeString(F.name);
                        try self.write(@field(v, F.name));
                    }
                    try self.endObject();
                }
            },
            .pointer => |ptr| {
                switch (ptr.size) {
                    .one => {
                        switch (@typeInfo(ptr.child)) {
                            .array => {
                                const S = []const std.meta.Elem(ptr.child);
                                try self.write(@as(S, v));
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
                }
            },
            .array => {
                try self.write(&v);
            },
            .vector => |vec| {
                const array: [vec.len]vec.child = v;
                try self.write(&array);
            },
            else => @compileError("Unable to encode type '" ++ @typeName(T) ++ "'"),
        }
    }
};
