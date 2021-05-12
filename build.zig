const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    {
        var srcDir = try std.fs.cwd().openDir("src", .{ .access_sub_paths = false, .iterate = true });
        defer srcDir.close();
        var iter = srcDir.iterate();
        while (try iter.next()) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
            const name = entry.name[0 .. entry.name.len - 4];

            const exe = b.addExecutable(name, b.fmt("src/{s}", .{entry.name}));
            exe.setTarget(target);
            exe.setBuildMode(mode);
            exe.install();

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
