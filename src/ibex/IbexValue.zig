const std = @import("std");
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const Stringify = std.json.Stringify;

const shadow = @import("./shadow.zig");
const IbexClass = shadow.IbexClass;

test {
    std.testing.refAllDecls(@This());
}

pub fn Slice(comptime T: type, comptime bits: usize) type {
    return packed struct {
        const Self = @This();
        pub const Type = []const T;

        len: @Int(.unsigned, bits - @bitSizeOf([*]const T)),
        ptr: [*]const T,

        pub fn init(value: Type) Self {
            return Self{ .len = @intCast(value.len), .ptr = value.ptr };
        }

        pub fn get(self: Self) Type {
            return self.ptr[0..self.len];
        }
    };
}

test Slice {
    try expectEqual(120, @bitSizeOf(Slice(u8, 120)));
    const is = Slice(u8, 120).init("Hello");
    try expectEqual("Hello", is.get());
}

pub fn Padded(comptime T: type, comptime bits: usize) type {
    return packed struct {
        const Self = @This();
        pub const Type = T;

        pad: @Int(.unsigned, bits - @bitSizeOf(T)) = 0,
        v: T,

        pub fn init(value: Type) Self {
            return Self{ .v = value };
        }

        pub fn get(self: Self) Type {
            return self.v;
        }
    };
}

const IbexValue = packed struct {
    const Self = @This();

    const TagType = u8;
    const budget = 128 - @bitSizeOf(TagType);

    pub const Tag = enum(TagType) {
        null,
        bool,
        integer,
        float,
        array,
        object,
        string,
        class,
        json,
        ibex,
    };

    pub const Payload = packed union {
        null: Padded(void, budget),
        bool: Padded(bool, budget),
        integer: Padded(i64, budget),
        float: Padded(f64, budget),
        array: Slice(IbexValue, budget),
        // An object is like an array but its first element must be a `class`
        object: Slice(IbexValue, budget),
        string: Slice(u8, budget),
        class: Padded(*const IbexClass, budget),
        json: Slice(u8, budget), // literal JSON
        ibex: Slice(u8, budget), // Ibex/Oryx bytes
    };

    tag: Tag,
    payload: Payload,

    pub fn tagType(comptime tag: Tag) type {
        return @FieldType(Payload, @tagName(tag)).Type;
    }

    pub fn init(comptime tag: Tag, value: tagType(tag)) Self {
        const FT = @FieldType(Payload, @tagName(tag));
        const payload = @unionInit(Payload, @tagName(tag), FT.init(value));
        return Self{ .tag = tag, .payload = payload };
    }

    pub fn get(self: Self, comptime tag: Tag) tagType(tag) {
        assert(tag == self.tag);
        return @field(self.payload, @tagName(tag)).get();
    }

    pub fn getObject(self: Self) struct { *const IbexClass, []const Self } {
        const contents = self.get(.object);
        assert(contents.len > 0);
        const class = contents[0].get(.class);
        const elts = contents[1..contents.len];
        assert(class.keys.len == elts.len);
        return .{ class, elts };
    }

    pub fn stringify(self: Self, sfy: *Stringify) !void {
        switch (self.tag) {
            .null => try sfy.write(null),
            inline .bool, .integer, .float, .string => |t| try sfy.write(self.get(t)),
            .array => {
                try sfy.beginArray();
                for (self.get(.array)) |elt| {
                    try elt.stringify(sfy);
                }
                try sfy.endArray();
            },
            .object => {
                const class, const elts = self.getObject();
                try sfy.beginObject();
                for (elts, class.keys) |e, n| {
                    try sfy.objectField(n);
                    try e.stringify(sfy);
                }
                try sfy.endObject();
            },
            .class => unreachable,
            .json => {
                try sfy.beginWriteRaw();
                try sfy.writer.writeAll(self.get(.json));
                sfy.endWriteRaw();
            },
            else => unreachable,
        }
    }
};

test IbexValue {
    const ivNull = IbexValue.init(.null, {});
    try expectEqual(.null, ivNull.tag);

    const ivInt = IbexValue.init(.integer, 12345);
    try expectEqual(.integer, ivInt.tag);
    try expectEqual(12345, ivInt.get(.integer));

    const ivStr = IbexValue.init(.string, "Hello!");
    try expectEqual(.string, ivStr.tag);
    try expectEqual("Hello!", ivStr.get(.string));
}

test "stringify" {
    const gpa = std.testing.allocator;

    const IV = IbexValue;
    const iv = IV.init;

    const TestCase = struct {
        const Self = @This();
        iv: IV,
        expect: []const u8,

        pub fn init(comptime tag: IV.Tag, value: IV.tagType(tag), expect: []const u8) Self {
            return Self{ .iv = iv(tag, value), .expect = expect };
        }
    };

    const t = TestCase.init;

    // Build shadow classes
    var root = shadow.IbexShadow{};
    defer root.deinit(gpa);

    const x = try root.getClassForKeys(gpa, &.{"x"});
    const xy = try root.getClassForKeys(gpa, &.{ "x", "y" });

    const cases = [_]TestCase{
        t(.null, {}, "null"),
        t(.integer, 1234, "1234"),
        t(.float, 1234.5, "1234.5"),
        t(.bool, true, "true"),
        t(.string, "Hello!", "\"Hello!\""),
        t(.array, &[_]IV{}, "[]"),
        t(.array, &[_]IV{iv(.integer, 123)}, "[123]"),
        t(.array, &[_]IV{ iv(.integer, 123), iv(.integer, 456) }, "[123,456]"),
        t(.object, &[_]IV{ iv(.class, x), iv(.integer, 123) }, "{\"x\":123}"),
        t(
            .object,
            &[_]IV{ iv(.class, xy), iv(.integer, 123), iv(.integer, 456) },
            "{\"x\":123,\"y\":456}",
        ),
        t(
            .array,
            &[_]IV{ iv(.integer, 123), iv(.json, "[true]"), iv(.integer, 456) },
            "[123,[true],456]",
        ),
    };

    for (cases) |tc| {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        var w = std.Io.Writer.Allocating.fromArrayList(gpa, &buf);
        defer w.deinit();

        var sfy = Stringify{ .writer = &w.writer };
        try tc.iv.stringify(&sfy);

        var output = w.toArrayList();
        defer output.deinit(gpa);

        try expectEqualDeep(tc.expect, output.items);
    }
}

test "layout" {
    try expectEqual(128, @bitSizeOf(IbexValue));
    comptime {
        const pi = @typeInfo(IbexValue.Payload).@"union";
        const ti = @typeInfo(IbexValue.Tag).@"enum";
        try expectEqual(pi.fields.len, ti.fields.len);
        for (pi.fields, ti.fields, 0..) |p, t, i| {
            try expectEqual(p.name, t.name);
            try expectEqual(t.value, i);
        }
    }
}
