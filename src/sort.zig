const std = @import("std");
const flag = @import("lib/flag.zig");
const util = @import("lib/util.zig");

fn check(options: SortOptions, args: *std.process.ArgIterator) !CheckResult {
    const allocator = std.heap.page_allocator;
    if (args.nextPosix()) |path| {
        if (args.skip()) {
            return error.TooManyArguments;
        }

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        return areLinesSorted(allocator, options, file.reader());
    } else {
        return areLinesSorted(allocator, options, std.io.getStdIn().reader());
    }
}

fn merge(options: SortOptions, out: std.fs.File, args: *std.process.ArgIterator) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator;

    var files = try fileList(allocator, args);
    defer {
        for (files) |f| {
            f.close();
        }
        allocator.free(files);
    }

    if (files.len == 1) {
        try out.writeFileAll(files[0], .{});
    } else {
        try mergeFiles(allocator, options, files, out.writer());
    }
}

fn sort(options: SortOptions, out: std.fs.File, args: *std.process.ArgIterator) !void {
    const allocator = &std.heap.ArenaAllocator.init(std.heap.page_allocator).allocator;

    var files = try fileList(allocator, args);
    defer {
        for (files) |f| {
            f.close();
        }
        allocator.free(files);
    }

    try sortFiles(allocator, options, files, out.writer());
}

fn fileList(allocator: *std.mem.Allocator, args: *std.process.ArgIterator) ![]std.fs.File {
    var files = std.ArrayList(std.fs.File).init(allocator);

    while (args.nextPosix()) |path| {
        try files.append(try std.fs.cwd().openFile(path, .{}));
    }
    if (files.items.len == 0) {
        try files.append(std.io.getStdIn());
    }

    return files.toOwnedSlice();
}

pub fn main() !u8 {
    var args = std.process.args();
    const flags = try flag.parse(struct {
        c: bool = false,
        C: bool = false,
        m: bool = false,
        o: ?[]const u8 = null,
        u: bool = false,

        d: bool = false,
        f: bool = false,
        i: bool = false,
        n: bool = false,
        r: bool = false,

        b: bool = false,
        t: ?u8 = null,

        k: ?[]const u8 = null,
    }, &args);

    const options = SortOptions{
        .unique = flags.u,

        .only_alnum = flags.d,
        .ignore_case = flags.f,
        .only_print = flags.i,
        .numeric = flags.n,
        .reverse = flags.r,
        // TODO: sort key stuff
    };

    if (flags.c or flags.C) {
        switch (try check(options, &args)) {
            .ok => return 0,
            .disorder => |line_no| {
                if (flags.c) {
                    try std.io.getStdErr().writer().print("line {} out of order\n", .{line_no});
                }
                return 1;
            },
            .duplicate => |line_no| {
                if (flags.c) {
                    try std.io.getStdErr().writer().print("line {} is a duplicate\n", .{line_no});
                }
                return 1;
            },
        }
    }

    const out = if (flags.o) |path|
        try std.fs.cwd().createFile(path, .{})
    else
        std.io.getStdOut();
    defer out.close();
    if (flags.m) {
        try merge(options, out, &args);
    } else {
        try sort(options, out, &args);
    }
    return 0;
}

const SortOptions = struct {
    unique: bool = false,

    only_alnum: bool = false,
    ignore_case: bool = false,
    only_print: bool = false,
    numeric: bool = false,
    reverse: bool = false,

    fn stringLess(self: SortOptions, lhs: []const u8, rhs: []const u8) bool {
        // TODO: support more options
        const order = std.mem.order(u8, lhs, rhs);
        return order.compare(if (self.reverse) .gt else .lt);
    }
};

fn areLinesSorted(allocator: *std.mem.Allocator, options: SortOptions, reader: anytype) !CheckResult {
    var a = try std.ArrayList(u8).initCapacity(allocator, std.mem.page_size);
    defer a.deinit();
    var b = try std.ArrayList(u8).initCapacity(allocator, std.mem.page_size);
    defer b.deinit();

    var lines = util.lineIterator(allocator, std.io.bufferedReader(reader).reader());
    if (!try lines.nextArrayList(&a)) {
        return CheckResult.ok; // Only one line
    }

    var line_no: u64 = 1;
    while (try lines.nextArrayList(&b)) {
        line_no += 1;

        if (options.stringLess(b.items, a.items)) {
            return CheckResult{ .disorder = line_no }; // Out of order lines
        }
        if (options.unique and !options.stringLess(a.items, b.items)) {
            return CheckResult{ .duplicate = line_no };
        }

        const tmp = a;
        a = b;
        b = tmp;
    }

    return CheckResult.ok;
}

const CheckResult = union(enum) {
    ok: void,
    disorder: u64,
    duplicate: u64,
};

test "check sorted lines" {
    const result = try areLinesSorted(
        std.testing.allocator,
        .{},
        std.io.fixedBufferStream(
            \\
            \\abc
            \\def
            \\ghi
            \\jkl
            \\
        ).reader(),
    );
    try std.testing.expect(result == .ok);
}

test "check unsorted lines" {
    const result = try areLinesSorted(
        std.testing.allocator,
        .{},
        std.io.fixedBufferStream(
            \\def
            \\
            \\jkl
            \\ghi
            \\abc
            \\
        ).reader(),
    );
    try std.testing.expect(result == .disorder and result.disorder == 2);
}

test "check with duplicates" {
    const result = try areLinesSorted(
        std.testing.allocator,
        .{},
        std.io.fixedBufferStream(
            \\abc
            \\def
            \\def
            \\ghi
        ).reader(),
    );
    try std.testing.expect(result == .ok);
}

test "check for duplicates" {
    const result = try areLinesSorted(
        std.testing.allocator,
        .{ .unique = true },
        std.io.fixedBufferStream(
            \\abc
            \\def
            \\def
            \\ghi
        ).reader(),
    );
    try std.testing.expect(result == .duplicate and result.duplicate == 3);
}

fn mergeFiles(allocator: *std.mem.Allocator, options: SortOptions, readerables: anytype, writer: anytype) !void {
    const BufReader = std.io.BufferedReader(4096, @TypeOf(readerables[0].reader()));
    const lessThan = struct {
        fn lessThan(opts: SortOptions, lhs: util.LineIterator(BufReader.Reader), rhs: util.LineIterator(BufReader.Reader)) bool {
            if (lhs.buf) |l| {
                if (rhs.buf) |r| {
                    // GREATER THAN!!!
                    // We sort in reverse order to make deletion of empty streams a little faster
                    return opts.stringLess(r.items, l.items);
                } else {
                    return true;
                }
            } else {
                return false;
            }
        }
    }.lessThan;

    const readers = try allocator.alloc(BufReader, readerables.len);
    defer allocator.free(readers);
    for (readerables) |*r, i| {
        readers[i] = std.io.bufferedReader(r.reader());
    }

    const line_iters = try allocator.alloc(util.LineIterator(BufReader.Reader), readers.len);
    for (readers) |*r, i| {
        line_iters[i] = util.lineIterator(allocator, r.reader());
        _ = try line_iters[i].next();
    }
    defer {
        for (line_iters) |lines| {
            lines.deinit();
        }
        allocator.free(line_iters);
    }

    var active_iters = line_iters;

    // Initial sort
    std.sort.sort(util.LineIterator(BufReader.Reader), active_iters, options, lessThan);
    // Remove any empty streams
    var i = active_iters.len;
    while (i > 0) {
        i -= 1;
        if (active_iters[i].buf == null) {
            active_iters = active_iters[0..i];
        }
    }

    var prev_line: ?[]const u8 = null;
    while (active_iters.len > 0) {
        const lines = &active_iters[active_iters.len - 1];

        if (options.unique) print: {
            if (prev_line) |line| {
                if (std.mem.eql(u8, line, lines.buf.?.items)) {
                    break :print; // Don't print duplicates
                }
                allocator.free(line);
            }
            try writer.print("{s}\n", .{lines.buf.?.items});
            prev_line = lines.buf.?.toOwnedSlice();
        } else {
            try writer.print("{s}\n", .{lines.buf.?.items});
        }

        if (try lines.next()) |_| {
            // Insertion sort is very fast for almost-ordered lists, which this one is (at most one item in the wrong place)
            // TODO: compare speed against sort() just to double check
            // OPTIM: only sort the last item into place, since we know that's the only out-of-order one
            std.sort.insertionSort(util.LineIterator(BufReader.Reader), active_iters, options, lessThan);
        } else {
            // This stream is now empty, remove it from the active list
            active_iters = active_iters[0 .. active_iters.len - 1];
        }
    }
    if (prev_line) |line| {
        allocator.free(line);
    }
}

test "merge" {
    const a =
        \\abc
        \\ghi
        \\jkl
        \\xyz
    ;
    const b =
        \\abc
        \\def
        \\jkl
        \\mno
        \\pqrst
        \\
    ;

    const expect =
        \\abc
        \\abc
        \\def
        \\ghi
        \\jkl
        \\jkl
        \\mno
        \\pqrst
        \\xyz
        \\
    ;

    var out: [expect.len]u8 = undefined;
    try mergeFiles(
        std.testing.allocator,
        .{},
        &[_]std.io.FixedBufferStream([]const u8){
            std.io.fixedBufferStream(a),
            std.io.fixedBufferStream(b),
        },
        std.io.fixedBufferStream(&out).writer(),
    );

    try std.testing.expectEqualStrings(expect, &out);
}

test "merge unique" {
    const a =
        \\abc
        \\ghi
        \\jkl
        \\xyz
    ;
    const b =
        \\abc
        \\def
        \\jkl
        \\mno
        \\pqrst
        \\
    ;

    const expect =
        \\abc
        \\def
        \\ghi
        \\jkl
        \\mno
        \\pqrst
        \\xyz
        \\
    ;

    var out: [expect.len]u8 = undefined;
    try mergeFiles(
        std.testing.allocator,
        .{ .unique = true },
        &[_]std.io.FixedBufferStream([]const u8){
            std.io.fixedBufferStream(a),
            std.io.fixedBufferStream(b),
        },
        std.io.fixedBufferStream(&out).writer(),
    );

    try std.testing.expectEqualStrings(expect, &out);
}
fn sortFiles(allocator: *std.mem.Allocator, options: SortOptions, readerables: anytype, writer: anytype) !void {
    var lines = std.ArrayList([]const u8).init(allocator);
    defer {
        for (lines.items) |line| {
            allocator.free(line);
        }
        lines.deinit();
    }

    for (readerables) |*r| {
        var buf_reader = std.io.bufferedReader(r.reader());
        var line_iter = util.lineIterator(allocator, buf_reader.reader());
        defer line_iter.deinit();
        while (try line_iter.nextOwned()) |line| {
            try lines.append(line);
        }
    }

    std.sort.sort([]const u8, lines.items, options, SortOptions.stringLess);

    for (lines.items) |line, i| {
        if (options.unique and i > 0 and std.mem.eql(u8, line, lines.items[i - 1])) {
            continue; // Don't print duplicates
        }
        try writer.print("{s}\n", .{line});
    }
}

test "sort" {
    const a =
        \\ghi
        \\xyz
        \\jkl
        \\abc
    ;
    const b =
        \\jkl
        \\def
        \\mno
        \\abc
        \\
        \\pqrst
        \\
    ;

    const expect =
        \\
        \\abc
        \\abc
        \\def
        \\ghi
        \\jkl
        \\jkl
        \\mno
        \\pqrst
        \\xyz
        \\
    ;

    var out: [expect.len]u8 = undefined;
    try sortFiles(
        std.testing.allocator,
        .{},
        &[_]std.io.FixedBufferStream([]const u8){
            std.io.fixedBufferStream(a),
            std.io.fixedBufferStream(b),
        },
        std.io.fixedBufferStream(&out).writer(),
    );

    try std.testing.expectEqualStrings(expect, &out);
}

test "sort unique" {
    const a =
        \\ghi
        \\xyz
        \\xyz
        \\jkl
        \\abc
    ;
    const b =
        \\jkl
        \\def
        \\mno
        \\abc
        \\
        \\pqrst
        \\
    ;

    const expect =
        \\
        \\abc
        \\def
        \\ghi
        \\jkl
        \\mno
        \\pqrst
        \\xyz
        \\
    ;

    var out: [expect.len]u8 = undefined;
    try sortFiles(
        std.testing.allocator,
        .{ .unique = true },
        &[_]std.io.FixedBufferStream([]const u8){
            std.io.fixedBufferStream(a),
            std.io.fixedBufferStream(b),
        },
        std.io.fixedBufferStream(&out).writer(),
    );

    try std.testing.expectEqualStrings(expect, &out);
}
