const std = @import("std");
const flag = @import("lib/flag.zig");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const allocator = std.heap.page_allocator;

// Byte and line indexes are 1-indexed. Additionally, the `line_idx` field is
// incremented for `\n` characters, so on binary files this value will be
// meaningless.
const Diff = struct {
    byte_idx: u64 = 1,
    line_idx: u64 = 1,
    a: u8 = 0,
    b: u8 = 0,
};

// Open a file relative to the current working directory.
fn openFile(filename: []const u8) !std.fs.File {
    return std.fs.cwd().openFile(filename, std.fs.File.OpenFlags{});
}

// Same as `reader.readByte` but returns `null` on EOF rather than raising
// `error.EndOfStream`.
fn readByteOrEOF(reader: anytype) !?u8 {
    return reader.readByte() catch |err| switch(err) {
        error.EndOfStream => return null,
        else => |e| return err,
    };
}

// Display a diagnostic message when two files differ in length.
// It is unspecified if a diagnostic message is printed using the `-s`
// flag, here I've chosen to print it regardless for simplicity.
fn diag(filename: []const u8) !void {
    try stderr.print("cmp: EOF on {s}\n", .{filename});
}

// TODO: This deviates from the specification, also not consistent with other
// uspace utils.
// Instead of returning an error code >1 for errors, it currently returns
// one of:
//     * error.MutuallExclusiveFlags
//     * error.NotEnoughArgs
//     * error.TooManyArgs
// TODO: POSIX locale environment variables.

pub fn main() !u8 {

    var args = std.process.args();
    const flags = try flag.parse(struct {
        l: bool = false,
        s: bool = false,
    }, &args);

    // Try to get two filenames arguments then open the files. A return value
    // of >1 indicates an error.
    var file_a_name = try args.nextPosix() orelse error.NotEnoughArgs;
    var file_b_name = try args.nextPosix() orelse error.NotEnoughArgs;
    var file_a = (try openFile(file_a_name)).reader();
    var file_b = (try openFile(file_b_name)).reader();

    // The `-s` and `-l` flags are mutually exclusive by specification.
    if (flags.l and flags.s) return error.MutuallExclusiveFlags;
    if (args.skip()) return error.TooManyArgs;

    var df  = Diff{};
    var diffs = std.ArrayList(Diff).init(allocator);

    // Find all differences in the files and append a `Diff` object to `diffs`
    // for each. In the case that the `-l` flag is NOT set, break after the
    // first diff.
    while (true) {
        var a = try readByteOrEOF(file_a);
        var b = try readByteOrEOF(file_b);
        if (a == null and b == null) break;

        // In the case that one file ends early, write a message to stderr
        // to indicate this then break the loop.
        df.a = a orelse { try diag(file_a_name); break; };
        df.b = b orelse { try diag(file_b_name); break; };

        if (df.a != df.b) {
            try diffs.append(df);
            if (!flags.l) break;
        }
        df.byte_idx += 1;
        if (df.a == '\n') df.line_idx += 1;
    }

    // Output the diffs. For the `-s` flag, report via the return code, else
    // print each diff on a line. For the `-l` flag, instead output the octal
    // value of the differing bytes.
    if (flags.s) {
        return if (diffs.items.len == 0) 0 else 1;
    } else {
        for (diffs.items) |d| {
            if (flags.l) {
                try stdout.print("{d} {o} {o}\n", .{d.byte_idx, d.a, d.b});
            } else {
                try stdout.print("{s} {s} differ: char {d}, line {d}\n", .{
                    file_a_name, file_b_name, d.byte_idx, d.line_idx
                });
            }
        }
        // This is unspecified, but since it does not matter 0 is a good
        // default exit status.
        return 0;
    }
}
