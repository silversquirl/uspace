const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = releaseOptions(b);

    var code: u8 = undefined;
    const tags = b.execAllowFail(
        &.{ "git", "describe", "--tags" },
        &code,
        std.ChildProcess.StdIo.Ignore,
    ) catch b.fmt("v0.0.0-{s}", .{try b.execAllowFail(
        &.{ "git", "rev-parse", "--short", "HEAD" },
        &code,
        std.ChildProcess.StdIo.Ignore,
    )});

    // Iterate through the src dir
    var srcDir = try std.fs.cwd().openDir("src", .{ .access_sub_paths = false, .iterate = true });
    defer srcDir.close();
    var iter = srcDir.iterate();

    while (try iter.next()) |entry| {
        if (stripSuffix(u8, entry.name, ".zig")) |name| {
            // Add executable to the build
            const exe = b.addExecutable(name, b.fmt("src/{s}", .{entry.name}));
            exe.strip = mode == .ReleaseSmall;

            exe.addBuildOption(
                []const u8,
                "tags",
                tags,
            );

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

fn releaseOptions(b: *std.build.Builder) std.builtin.Mode {
    const release = b.option(bool, "release", "Optimize for speed; safety checking and debug symbols remain") orelse false;
    const small = b.option(bool, "small", "Optimize for size, disable safety checking and strip debug symbols") orelse false;

    if (release and small) {
        std.debug.warn("-Drelease and -Dsmall are mutually exclusive\n\n", .{});
        b.invalid_user_input = true;
    } else if (release) {
        return .ReleaseSafe;
    } else if (small) {
        return .ReleaseSmall;
    }
    return .Debug;
}

fn stripSuffix(comptime T: type, slice: []const T, suffix: []const T) ?[]const T {
    if (std.mem.endsWith(T, slice, suffix)) {
        return slice[0 .. slice.len - suffix.len];
    } else {
        return null;
    }
}
