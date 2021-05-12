const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    // Iterate through the src dir
    var srcDir = try std.fs.cwd().openDir("src", .{ .access_sub_paths = false, .iterate = true });
    defer srcDir.close();
    var iter = srcDir.iterate();
    while (try iter.next()) |entry| {
        if (stripSuffix(u8, entry.name, ".zig")) |name| {
            // Add executable to the build
            const exe = b.addExecutable(name, b.fmt("src/{s}", .{entry.name}));
            exe.setTarget(target);
            exe.setBuildMode(mode);
            exe.install();

            // Add a run step for the executable
            const run_cmd = exe.run();
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }
            const run_step = b.step(name, b.fmt("Run {s}", .{name}));
            run_step.dependOn(&run_cmd.step);
        }
    }
}

fn stripSuffix(comptime T: type, slice: []const T, suffix: []const T) ?[]const T {
    if (std.mem.endsWith(T, slice, suffix)) {
        return slice[0 .. slice.len - suffix.len];
    } else {
        return null;
    }
}
