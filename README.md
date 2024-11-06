
# zigrope
A zig [rope (data structure)](https://en.wikipedia.org/wiki/Rope_(data_structure)) implementation.
# Examples
- 'Hello, world!'
```zig
const StringRope = @import("rope.zig").StringRope;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();

const allocator = gpa.allocator();

var rope = try StringRope(5).initSlice(allocator, "Hello, ");
defer rope.deinit();

try rope.append("world!");
try rope.debugPrint(); // prints 'Hello, world!'
```
