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
        var walker = try std.fs.walkPath(b.allocator, "man");
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (entry.kind == .File) {
                b.getInstallStep().dependOn(&addPreprocessMan(b, entry.path, .Prefix, entry.path, tags).step);
            } else if (entry.kind == .SymLink) {
                // TODO uncomment this line when std handles symlinks
                // b.installFile(entry.path, entry.path);
            }
        }
    }
}

fn releaseOptions(b: *std.build.Builder) std.builtin.Mode {
    const release = b.option(bool, "release", "Optimize for speed; safety checking and debug symbols remain") orelse false;
    const small = b.option(bool, "small", "Optimize for size, disable safety checking and strip debug symbols") orelse false;

    if (release and small) {
        std.debug.print("-Drelease and -Dsmall are mutually exclusive\n\n", .{});
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

fn dupeInstallDir(self: std.build.InstallDir, builder: *std.build.Builder) std.build.InstallDir {
    if (self == .Custom) {
        // Written with this temporary to avoid RLS problems
        const duped_path = builder.dupe(self.Custom);
        return .{ .Custom = duped_path };
    } else {
        return self;
    }
}

const PreprocessManStep = struct {
    step: std.build.Step,
    builder: *std.build.Builder,
    src_path: []const u8,
    dir: std.build.InstallDir,
    dest_rel_path: []const u8,
    version: []const u8,

    const Self = @This();

    pub fn init(
        builder: *std.build.Builder,
        src_path: []const u8,
        dir: std.build.InstallDir,
        dest_rel_path: []const u8,
        version: []const u8,
    ) PreprocessManStep {
        builder.pushInstalledFile(dir, dest_rel_path);
        return PreprocessManStep{
            .builder = builder,
            .step = std.build.Step.init(.InstallFile, builder.fmt("preproccess and install {s}", .{src_path}), builder.allocator, make),
            .src_path = builder.dupePath(src_path),
            .dir = dupeInstallDir(dir), // TODO use std dupe when public
            .dest_rel_path = builder.dupePath(dest_rel_path),
            .version = version,
        };
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(PreprocessManStep, "step", step);
        const full_src_path = self.builder.pathFromRoot(self.src_path);
        const full_dest_path = self.builder.getInstallPath(self.dir, self.dest_rel_path);
        try self.updateMan(full_src_path, full_dest_path);
    }

    fn updateMan(self: *Self, src_path: []const u8, dest_path: []const u8) !void {
        const cwd = std.fs.cwd();

        if (self.builder.verbose) {
            std.debug.print("preprocess {s} and copy to {s}\n", .{ src_path, dest_path });
        }

        var src_file = try cwd.openFile(src_path, .{});
        defer src_file.close();

        if (std.fs.path.dirname(dest_path)) |dirname| {
            try cwd.makePath(dirname);
        }

        const atomic_file = try std.io.BufferedAtomicFile.create(self.builder.allocator, cwd, dest_path, .{});
        defer atomic_file.destroy();

        var buffered_reader = std.io.bufferedReader(src_file.reader());
        try self.preprocessMan(buffered_reader.reader(), atomic_file.writer());

        try atomic_file.finish();
    }

    fn preprocessMan(self: *Self, reader: anytype, writer: anytype) !void {
        const search_string = [_]u8{ '\n', '.', 'O', 's', ' ', 'u', 's', 'p', 'a', 'c', 'e' };
        var search_pos: usize = 0;
        while (true) {
            const byte = reader.readByte() catch |err| {
                switch (err) {
                    error.EndOfStream => break,
                    else => |e| return e,
                }
            };
            try writer.writeByte(byte);

            if (search_string[search_pos] == byte) {
                search_pos += 1;
            } else {
                search_pos = 0;
            }

            if (search_pos == search_string.len) {
                try writer.writeAll(self.builder.fmt(" {s}", .{self.version}));
                search_pos = 0;
            }
        }
    }
};

fn addPreprocessMan(
    self: *std.build.Builder,
    src_path: []const u8,
    dir: std.build.InstallDir,
    dest_rel_path: []const u8,
    version: []const u8,
) *PreprocessManStep {
    const install_step = self.allocator.create(PreprocessManStep) catch unreachable;
    install_step.* = PreprocessManStep.init(self, src_path, dir, dest_rel_path, version);
    return install_step;
}
