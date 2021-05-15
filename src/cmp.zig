const std = @import("std");
const flag = @import("lib/flag.zig");

// Byte and line indexes are 1-indexed. Additionally, the `line_idx` field is incremented for `\n`
// characters, so on binary files this value will not be useful as it would in text files.
const Diff = struct {
    byte_idx: u64,
    line_idx: u64,
    a: u8,
    b: u8,
};

// Same as `reader.readByte` but returns `null` on EOF rather than raising `error.EndOfStream`.
fn readByteOrEof(reader: anytype) !?u8 {
    return reader.readByte() catch |err| switch (err) {
        error.EndOfStream => return null,
        else => |e| return err,
    };
}

// TODO: This deviates from the specification, also not consistent with other uspace utils.
// Instead of returning an error code >1 for errors, it currently returns one of:
//     * error.MutuallyExclusiveFlags
//     * error.NotEnoughArgs
//     * error.TooManyArgs
// TODO: POSIX locale environment variables.
fn cmp(filename_a: []const u8, filename_b: []const u8, flag_l: bool, flag_s: bool) !u8 {
    var file_a = (try std.fs.cwd().openFile(filename_a, .{})).reader();
    var file_b = (try std.fs.cwd().openFile(filename_b, .{})).reader();

    const out = std.io.getStdOut().writer();
    const err = std.io.getStdErr().writer();

    var diff = Diff{ .byte_idx = 1, .line_idx = 1, .a = undefined, .b = undefined };
    var diffs = std.ArrayList(Diff).init(std.heap.page_allocator);

    // Find all differences in the files and append a `Diff` object to `diffs` for each. In the
    // case that the `-l` flag is NOT set, break after the first diff.
    while (true) {
        const a = try readByteOrEof(file_a);
        const b = try readByteOrEof(file_b);
        if (a == null and b == null) break;

        // In the case that one file ends early, write a message to stderr to indicate this then
        // break the loop.  It is unspecified if a diagnostic message is printed using the `-s`
        // flag, here I've chosen to print it regardless for simplicity.
        diff.a = a orelse {
            try err.print("cmp: EOF on {s}\n", .{filename_a});
            break;
        };
        diff.b = b orelse {
            try err.print("cmp: EOF on {s}\n", .{filename_b});
            break;
        };

        if (diff.a != diff.b) {
            try diffs.append(diff);
            if (!flag_l) break;
        }
        diff.byte_idx += 1;
        if (diff.a == '\n') diff.line_idx += 1;
    }

    // Output the diffs. For the `-s` flag, report via the return code, else print each diff on a
    // line. For the `-l` flag, instead output the octal value of the differing bytes.
    if (!flag_s) {
        for (diffs.items) |d| {
            if (flag_l) {
                try out.print("{d} {o} {o}\n", .{ d.byte_idx, d.a, d.b });
            } else {
                try out.print("{s} {s} differ: char {d}, line {d}\n", .{
                    filename_a,
                    filename_b,
                    d.byte_idx,
                    d.line_idx,
                });
            }
        }
    }

    // An exit code of `1` means some difference was found.
    return @boolToInt(diffs.items.len > 0);
}

pub fn main() !u8 {
    var args = std.process.args();
    const flags = try flag.parse(struct {
        l: bool = false,
        s: bool = false,
    }, &args);

    // Try to get two filename arguments.
    const a = try args.nextPosix() orelse error.NotEnoughArgs;
    const b = try args.nextPosix() orelse error.NotEnoughArgs;
    if (args.skip()) return error.TooManyArgs;

    // The `-s` and `-l` flags are mutually exclusive by specification.
    if (flags.l and flags.s) return error.MutuallyExclusiveFlags;

    return cmp(a, b, flags.l, flags.s);
}
