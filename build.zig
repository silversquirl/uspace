const std = @import("std");

const InstallManStep = struct {
    step: std.build.Step,
    builder: *std.build.Builder,
    src_path: []const u8,
    dir: std.build.InstallDir,
    dest_rel_path: []const u8,

    const Self = @This();

    pub fn init(
        builder: *std.build.Builder,
        src_path: []const u8,
        dir: std.build.InstallDir,
        dest_rel_path: []const u8,
    ) InstallManStep {
        builder.pushInstalledFile(dir, dest_rel_path);
        return InstallManStep{
            .builder = builder,
            .step = std.build.Step.init(.InstallFile, builder.fmt("install {s}", .{src_path}), builder.allocator, make),
            .src_path = builder.dupePath(src_path),
            .dir = dir,
            .dest_rel_path = builder.dupePath(dest_rel_path),
        };
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(InstallManStep, "step", step);
        const full_src_path = self.builder.pathFromRoot(self.src_path);
        const full_dest_path = self.builder.getInstallPath(self.dir, self.dest_rel_path);
        try self.updateMan(full_src_path, full_dest_path);
    }

    fn updateMan(self: *Self, src_path: []const u8, dest_path: []const u8) !void {
        const cwd = std.fs.cwd();

        if (self.builder.verbose) {
            std.debug.warn("cp {s} {s} ", .{ src_path, dest_path });
        }

        var src_file = try cwd.openFile(self.src_path, .{});
        defer src_file.close();

        if (std.fs.path.dirname(dest_path)) |dirname| {
            try cwd.makePath(dest_path);
        }

        var atomic_file = try cwd.atomicFile(dest_path, .{});
        defer atomic_file.deinit();

        const reader = src_file.reader();
        const writer = atomic_file.file.writer();

        while (true) {
            // TODO check for os string
            const byte = reader.readByte() catch |err| {
                if (err == error.EndOfStream) {
                    break;
                } else {
                    return err;
                }
            };

            try writer.writeByte(byte);
        }
    }
};

fn addInstallMan(self: *std.build.Builder, path: []const u8) *InstallManStep {
    const install_step = self.allocator.create(InstallManStep) catch unreachable;
    install_step.* = InstallManStep.init(self, path, .Prefix, path);
    return install_step;
}

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

    { // Add all executables
        var srcDir = try std.fs.cwd().openDir("src", .{ .access_sub_paths = false, .iterate = true });
        defer srcDir.close();
        var iter = srcDir.iterate();
        while (try iter.next()) |entry| {
            if (stripSuffix(u8, entry.name, ".zig")) |name| {
                // Add executable to the build
                const exe = b.addExecutable(name, b.fmt("src/{s}", .{entry.name}));

                exe.addBuildOption(
                    []const u8,
                    "tags",
                    tags,
                );

                exe.strip = mode == .ReleaseSmall;
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

    { // Add tests for everything
        const test_step = b.step("run-tests", "Run library tests");

        var walker = try std.fs.walkPath(b.allocator, "src");
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (std.mem.endsWith(u8, entry.basename, ".zig")) {
                // Add tests to test step
                var tests = b.addTest(entry.path);
                tests.setBuildMode(mode);
                test_step.dependOn(&tests.step);
            }
        }
    }

    { // Install manpages
        inline for ([_][]const u8{"man1"}) |dir| {
            var manDir = try std.fs.cwd().openDir("man/" ++ dir, .{ .access_sub_paths = false, .iterate = true });
            defer manDir.close();
            var iter = manDir.iterate();
            while (try iter.next()) |entry| {
                const path = try std.mem.concat(b.allocator, u8, &.{ "man/" ++ dir ++ "/", entry.name });
                b.getInstallStep().dependOn(&addInstallMan(b, path).step);
            }
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
