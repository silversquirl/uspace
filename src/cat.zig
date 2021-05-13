const std = @import("std");
const flag = @import("lib/flag.zig");

fn cat(file: std.fs.File) !void {
    const out = std.io.getStdOut();
    try out.writeFileAll(file, .{});
}

pub fn main() !void {
    var args = std.process.args();
    _ = try flag.parse(struct { u: bool = false }, &args);

    var opt_path = args.nextPosix();
    if (opt_path == null) {
        try cat(std.io.getStdIn());
    } else {
        while (opt_path) |path| {
            if (std.mem.eql(u8, path, "-")) {
                try cat(std.io.getStdIn());
            } else {
                const file = try std.fs.cwd().openFile(path, .{});
                defer file.close();
                try cat(file);
            }
            opt_path = args.nextPosix();
        }
    }
}
