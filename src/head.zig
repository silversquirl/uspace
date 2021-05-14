const std = @import("std");

pub fn main() void {
    const numLines: ?u32 = 10;

    const allocator = std.heap.page_allocator;

    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();

    
}
