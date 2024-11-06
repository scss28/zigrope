const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub fn StringRope(max_chunk_len: comptime_int) type {
    return Rope(u8, max_chunk_len);
}

pub fn Rope(T: type, max_chunk_len: comptime_int) type {
    return struct {
        allocator: Allocator,
        lhs: ?*@This() = null,
        rhs: ?*@This() = null,
        weight: usize = 0,
        chunk: std.BoundedArray(T, max_chunk_len) = .{},

        /// Initialize an empty rope.
        pub fn init(allocator: Allocator) @This() {
            return .{ .allocator = allocator };
        }

        /// Initialize a rope with elements from the `slice`.
        pub fn initSlice(allocator: Allocator, slice: []const T) !@This() {
            if (slice.len <= max_chunk_len) {
                var chunk: std.BoundedArray(T, max_chunk_len) = .{};
                chunk.appendSlice(slice) catch unreachable;

                return .{
                    .allocator = allocator,
                    .weight = slice.len,
                    .chunk = chunk,
                };
            }

            var self = try @This().initSlice(allocator, slice[0 .. slice.len / 2]);
            errdefer self.deinit();

            const rhs = try @This().initSlice(allocator, slice[slice.len / 2 ..]);
            errdefer rhs.deinit();

            try self.append(rhs);
            return self;
        }

        /// Free all the memory owned by this rope.
        pub fn deinit(self: @This()) void {
            if (self.lhs) |lhs| {
                lhs.deinit();
                self.allocator.destroy(lhs);
            }

            if (self.rhs) |rhs| {
                rhs.deinit();
                self.allocator.destroy(rhs);
            }
        }

        /// Returns the length of all elements of the rope.
        pub fn len(self: @This()) usize {
            var length = self.weight;
            if (self.rhs) |rhs| {
                length += rhs.len();
            }

            return length;
        }

        /// Appends the rope with `rhs`.
        pub fn append(self: *@This(), rhs: anytype) Allocator.Error!void {
            const RhsType = @TypeOf(rhs);
            switch (@typeInfo(RhsType)) {
                .pointer => {
                    const rope = try @This().initSlice(self.allocator, rhs);
                    errdefer rope.deinit();

                    try self.append(rope);
                },
                .@"struct" => {
                    const allocator = self.allocator;

                    const lhs = try allocator.create(@This());
                    errdefer allocator.destroy(lhs);

                    lhs.* = self.*;

                    self.rhs = try allocator.create(@This());
                    self.rhs.?.* = rhs;

                    self.lhs = lhs;
                    self.weight = lhs.len();
                    self.chunk.clear();
                },
                inline else => @compileError("Expected slice type or Rope, found '" ++ @typeName(RhsType) ++ "'"),
            }
        }

        /// Prepends the rope with `lhs`.
        pub fn prepend(self: *@This(), lhs: anytype) Allocator.Error!void {
            const LhsType = @TypeOf(lhs);
            switch (@typeInfo(LhsType)) {
                .pointer => {
                    const rope = try @This().initSlice(self.allocator, lhs);
                    errdefer rope.deinit();

                    try self.prepend(rope);
                },
                .@"struct" => {
                    var new_self = lhs;
                    try new_self.append(self.*);

                    self.* = new_self;
                },
                inline else => @compileError("Expected slice type or Rope, found '" ++ @typeName(LhsType) ++ "'"),
            }
        }

        pub const SplitError = error{IndexOutOfRange} || Allocator.Error;

        /// Splits the rope in two, returning the right chunk.
        /// Deinitialize the returned rope using `deinit`.
        pub fn split(self: *@This(), index: usize) SplitError!@This() {
            const allocator = self.allocator;
            if (index >= self.weight and self.rhs != null) {
                return self.rhs.?.split(index - self.weight);
            }

            if (self.lhs) |lhs| {
                const rope = try allocator.create(@This());
                rope.* = try lhs.split(index);

                defer self.rhs = null;
                return .{
                    .allocator = allocator,
                    .lhs = rope,
                    .rhs = self.rhs,
                    .weight = rope.weight,
                    .chunk = .{},
                };
            }

            if (index > self.weight) return SplitError.IndexOutOfRange;

            var right_chunk: std.BoundedArray(T, max_chunk_len) = .{};
            right_chunk.appendSlice(self.chunk.slice()[index..]) catch unreachable;

            self.chunk.resize(index) catch unreachable;
            return .{
                .allocator = self.allocator,
                .weight = right_chunk.len,
                .chunk = right_chunk,
            };
        }

        /// Removes part of the rope.
        pub fn remove(self: *@This(), index: usize, length: usize) SplitError!void {
            const self_len = self.len();
            if (index >= self_len or index + length > self_len) {
                return SplitError.IndexOutOfRange;
            }

            var mid = try self.split(index);
            defer mid.deinit();

            const rhs = try mid.split(length);
            try self.append(rhs);
        }

        /// Inserts the provided items at the specified index.
        pub fn insert(self: *@This(), index: usize, items: anytype) SplitError!void {
            const rhs = try self.split(index);
            try self.append(items);
            try self.append(rhs);
        }

        /// Uses `sliceAlloc` then prints the result and frees the slice. (*should be used only for debugging*)
        pub fn print(self: *const @This()) Allocator.Error!void {
            const slice = try self.sliceAlloc(self.allocator);
            defer self.allocator.free(slice);

            std.debug.print("{s}\n", .{slice});
        }

        /// Allocates a slice with elements of the rope.
        /// Call `allocator.free` to free the slice.
        pub fn sliceAlloc(self: *const @This(), allocator: Allocator) Allocator.Error![]T {
            var list = try std.ArrayList(T).initCapacity(allocator, self.len());
            try self.sliceAllocInner(&list);

            return list.toOwnedSlice();
        }

        fn sliceAllocInner(self: *const @This(), list: *std.ArrayList(T)) Allocator.Error!void {
            if (self.lhs) |lhs| try lhs.sliceAllocInner(list);
            try list.appendSlice(self.chunk.slice());
            if (self.rhs) |rhs| try rhs.sliceAllocInner(list);
        }
    };
}

test "Rope.append" {
    const allocator = std.testing.allocator;

    var rope = try StringRope(5).initSlice(allocator, "Hello, ");
    defer rope.deinit();

    try rope.append("world!");

    const slice = try rope.sliceAlloc(allocator);
    defer allocator.free(slice);

    try std.testing.expect(std.mem.eql(u8, slice, "Hello, world!"));
}

test "Rope.prepend" {
    const allocator = std.testing.allocator;

    var rope = try StringRope(5).initSlice(allocator, "world!");
    defer rope.deinit();

    try rope.prepend("Hello, ");

    const slice = try rope.sliceAlloc(allocator);
    defer allocator.free(slice);

    try std.testing.expect(std.mem.eql(u8, slice, "Hello, world!"));
}

test "Rope.split" {
    const allocator = std.testing.allocator;

    var rope = try StringRope(5).initSlice(allocator, "Hello, world!");
    defer rope.deinit();

    const other_rope = try rope.split(7);
    defer other_rope.deinit();

    const slice = try rope.sliceAlloc(allocator);
    defer allocator.free(slice);

    const other_slice = try other_rope.sliceAlloc(allocator);
    defer allocator.free(other_slice);

    try std.testing.expect(std.mem.eql(u8, slice, "Hello, "));
    try std.testing.expect(std.mem.eql(u8, other_slice, "world!"));
}

test "Rope.split(0)" {
    const allocator = std.testing.allocator;

    var rope = try StringRope(5).initSlice(allocator, "Hello, world!");
    defer rope.deinit();

    const other_rope = try rope.split(0);
    defer other_rope.deinit();

    const slice = try rope.sliceAlloc(allocator);
    defer allocator.free(slice);

    const other_slice = try other_rope.sliceAlloc(allocator);
    defer allocator.free(other_slice);

    try std.testing.expect(std.mem.eql(u8, slice, ""));
    try std.testing.expect(std.mem.eql(u8, other_slice, "Hello, world!"));
}

test "Rope.split(len)" {
    const allocator = std.testing.allocator;

    var rope = try StringRope(5).initSlice(allocator, "Hello, world!");
    defer rope.deinit();

    const other_rope = try rope.split(rope.len());
    defer other_rope.deinit();

    const slice = try rope.sliceAlloc(allocator);
    defer allocator.free(slice);

    const other_slice = try other_rope.sliceAlloc(allocator);
    defer allocator.free(other_slice);

    try std.testing.expect(std.mem.eql(u8, slice, "Hello, world!"));
    try std.testing.expect(std.mem.eql(u8, other_slice, ""));
}

test "Rope.remove" {
    const allocator = std.testing.allocator;

    var rope = try StringRope(5).initSlice(allocator, "Hello, world!");
    defer rope.deinit();

    try rope.remove(4, 5);

    const slice = try rope.sliceAlloc(allocator);
    defer allocator.free(slice);

    try std.testing.expect(std.mem.eql(u8, slice, "Hellrld!"));
}
