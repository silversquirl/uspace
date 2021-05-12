const std = @import("std");

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    var args = std.process.args();
    _ = args.skip();
    if (args.nextPosix()) |arg| {
        try out.writeAll(arg);
    }
    while (args.nextPosix()) |arg| {
        try out.print(" {s}", .{arg});
    }
    try out.writeByte('\n');
}
