const std = @import("std");
const StringRope = @import("rope.zig").StringRope;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var rope = try StringRope(5).initSlice(allocator, "Hello, ");
    defer rope.deinit();

    try rope.append("world!");
    try rope.debugPrint();

    try rope.remove(4, 3);
    try rope.insert(4, " ");
    try rope.debugPrint();
}

test {
    std.testing.refAllDecls(@import("rope.zig"));
}
