const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const IndexType = usize;

pub const IbexClass = struct {
    const Self = @This();
    const IndexMap = std.StringHashMapUnmanaged(IndexType);

    index: IndexMap = .empty,
    keys: []const []const u8,
    shadow: *const IbexShadow, // non owning

    fn indexForKeys(gpa: Allocator, keys: []const []const u8) !IndexMap {
        var index: IndexMap = .empty;
        if (keys.len == 0)
            return index;
        try index.ensureTotalCapacity(gpa, @intCast(keys.len));
        for (keys, 0..) |n, i|
            index.putAssumeCapacity(n, @intCast(i));
        return index;
    }

    pub fn initFromShadow(gpa: Allocator, shadow: *const IbexShadow) !Self {
        const size = shadow.size();

        var keys = try gpa.alloc([]const u8, size);
        errdefer gpa.free(keys);

        var class = shadow;
        while (class.size() > 0) : (class = class.parent.?) {
            assert(class.index < size);
            keys[class.index] = class.key;
        }

        return Self{
            .index = try indexForKeys(gpa, keys),
            .keys = keys,
            .shadow = shadow,
        };
    }

    pub fn deinit(self: *Self, gpa: Allocator) void {
        self.index.deinit(gpa);
        gpa.free(self.keys);
        self.* = undefined;
    }

    pub fn get(self: Self, key: []const u8) ?IndexType {
        return self.index.get(key);
    }
};

pub const IbexShadow = struct {
    const Self = @This();
    pub const NextMap = std.StringHashMapUnmanaged(*Self);
    pub const RootIndex = std.math.maxInt(IndexType);
    const ctx = std.hash_map.StringContext{};

    parent: ?*const Self = null,
    object_class: ?IbexClass = null,
    key: []const u8 = "$", // not normally referred to
    next: NextMap = .empty,
    index: IndexType = RootIndex,
    usage: usize = 0,

    pub fn size(self: *const Self) IndexType {
        return self.index +% 1;
    }

    fn deinitContents(self: *Self, gpa: Allocator) void {
        var iter = self.next.valueIterator();
        while (iter.next()) |v| v.*.deinitNonRoot(gpa);
        if (self.object_class) |*class| class.deinit(gpa);
        self.next.deinit(gpa);
    }

    fn deinitNonRoot(self: *Self, gpa: Allocator) void {
        self.deinitContents(gpa);
        gpa.free(self.key);
        gpa.destroy(self);
    }

    pub fn deinit(self: *Self, gpa: Allocator) void {
        assert(self.size() == 0); // Must be root
        self.deinitContents(gpa);
        self.* = undefined;
    }

    pub fn startWalk(self: *Self) *Self {
        self.usage +|= 1;
        return self;
    }

    pub fn getNext(self: *Self, gpa: Allocator, key: []const u8) !*Self {
        const slot = try self.next.getOrPutContextAdapted(gpa, key, ctx, ctx);
        if (!slot.found_existing) {
            const key_name = try gpa.dupe(u8, key);
            const next = try gpa.create(Self);
            next.* = .{
                .parent = self,
                .key = key_name,
                .index = self.size(),
            };
            slot.key_ptr.* = key_name;
            slot.value_ptr.* = next;
        }
        return slot.value_ptr.*.startWalk();
    }

    pub fn getForKeys(self: *Self, gpa: Allocator, keys: []const []const u8) !*Self {
        var class = self.startWalk();
        for (keys) |key| {
            class = try class.getNext(gpa, key);
        }
        return class;
    }

    pub fn getClass(self: *Self, gpa: Allocator) !*const IbexClass {
        if (self.object_class == null)
            self.object_class = try IbexClass.initFromShadow(gpa, self);

        return &self.object_class.?;
    }

    pub fn getClassForKeys(self: *Self, gpa: Allocator, keys: []const []const u8) !*const IbexClass {
        const class = try self.getForKeys(gpa, keys);
        return try class.getClass(gpa);
    }
};

test IbexShadow {
    const SC = IbexShadow;
    const gpa = std.testing.allocator;
    var root = SC{};
    defer root.deinit(gpa);

    try std.testing.expectEqual(root.key, "$");

    var foo1 = try root.getNext(gpa, "foo");
    try std.testing.expectEqual(foo1.index, 0);
    try std.testing.expectEqual(foo1.parent, &root);

    var bar1 = try foo1.getNext(gpa, "bar");
    try std.testing.expectEqual(bar1.index, 1);
    try std.testing.expectEqual(bar1.parent, foo1);

    var foo2 = try root.getNext(gpa, "foo");
    try std.testing.expectEqual(foo1, foo2);
    var bar2 = try foo2.getNext(gpa, "bar");
    try std.testing.expectEqual(bar1, bar2);

    const cls1 = try bar1.getClass(gpa);
    const cls2 = try bar2.getClass(gpa);

    try std.testing.expectEqual(cls1, cls2);

    const empty = try root.getClass(gpa);
    try std.testing.expectEqualDeep(0, empty.keys.len);
}
