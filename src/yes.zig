const std = @import("std");

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    var args = std.process.args();
    _ = args.skip();

    const allocator = std.heap.page_allocator;

    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();

    while (args.nextPosix()) |arg| : (try string.append(' ')) {
        try string.appendSlice(arg);
    }

    if (string.items.len == 0) {
        try string.append('y');
    }

    while (true) {
        try out.print("{s}\n", .{string.items});
    }
}
