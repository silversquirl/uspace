const std = @import("std");
const flag = @import("lib/flag.zig");
const util = @import("lib/util.zig");

fn check(options: SortOptions, nowarn: bool, args: *std.process.ArgIterator) !bool {
    // TODO: handle nowarn

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

fn merge(options: SortOptions, args: *std.process.ArgIterator) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator;

    var files = try fileList(allocator, args);
    defer {
        for (files) |f| {
            f.close();
        }
        allocator.free(files);
    }

    const out = std.io.getStdOut();
    if (files.len == 1) {
        try out.writeFileAll(files[0], .{});
    } else {
        try mergeFiles(allocator, options, files, out.writer());
    }
}

fn sort(options: SortOptions, args: *std.process.ArgIterator) !void {
    const allocator = &std.heap.ArenaAllocator.init(std.heap.page_allocator).allocator;

    var files = try fileList(allocator, args);
    defer {
        for (files) |f| {
            f.close();
        }
        allocator.free(files);
    }

    const out = std.io.getStdOut();
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
        .only_alnum = flags.d,
        .ignore_case = flags.f,
        .only_print = flags.i,
        .numeric = flags.n,
        .reverse = flags.r,
        // TODO: sort key stuff
    };

    // TODO: handle -o

    if (flags.c or flags.C) {
        if (try check(options, flags.C, &args)) {
            return 0;
        } else {
            return 1;
        }
    } else if (flags.m) {
        try merge(options, &args);
    } else {
        try sort(options, &args);
    }
    return 0;
}

const SortOptions = struct {
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

fn areLinesSorted(allocator: *std.mem.Allocator, options: SortOptions, reader: anytype) !bool {
    var a = try std.ArrayList(u8).initCapacity(allocator, std.mem.page_size);
    defer a.deinit();
    var b = try std.ArrayList(u8).initCapacity(allocator, std.mem.page_size);
    defer b.deinit();

    var lines = util.lineIterator(allocator, reader);
    if (!try lines.nextArrayList(&a)) {
        return true; // Only one line
    }

    var done = false;
    while (try lines.nextArrayList(&b)) {
        if (options.stringLess(b.items, a.items)) {
            return false; // Out of order lines
        }

        const tmp = a;
        a = b;
        b = tmp;
    }

    return true;
}

test "check sorted lines" {
    try std.testing.expect(try areLinesSorted(
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
    ));
}

test "check unsorted lines" {
    try std.testing.expect(!try areLinesSorted(
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
    ));
}

fn mergeFiles(allocator: *std.mem.Allocator, options: SortOptions, readerables: anytype, writer: anytype) !void {
    const Reader = @TypeOf(readerables[0].reader());
    const lessThan = struct {
        fn lessThan(opts: SortOptions, lhs: util.LineIterator(Reader), rhs: util.LineIterator(Reader)) bool {
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

    const line_iters = try allocator.alloc(util.LineIterator(Reader), readerables.len);
    for (readerables) |r, i| {
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
    std.sort.sort(util.LineIterator(Reader), active_iters, options, lessThan);
    // Remove any empty streams
    var i = active_iters.len;
    while (i > 0) {
        i -= 1;
        if (active_iters[i].buf == null) {
            active_iters = active_iters[0..i];
        }
    }

    while (active_iters.len > 0) {
        const lines = &active_iters[active_iters.len - 1];
        try writer.print("{s}\n", .{lines.buf.?.items});
        if (try lines.next()) |_| {
            // Insertion sort is very fast for almost-ordered lists, which this one is (at most one item in the wrong place)
            // TODO: compare speed against sort() just to double check
            // OPTIM: only sort the last item into place, since we know that's the only out-of-order one
            std.sort.insertionSort(util.LineIterator(Reader), active_iters, options, lessThan);
        } else {
            // This stream is now empty, remove it from the active list
            active_iters = active_iters[0 .. active_iters.len - 1];
        }
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
        &[_]*std.io.FixedBufferStream([]const u8){
            &std.io.fixedBufferStream(a),
            &std.io.fixedBufferStream(b),
        },
        std.io.fixedBufferStream(&out).writer(),
    );

    try std.testing.expectEqualStrings(expect, &out);
}

fn sortFiles(allocator: *std.mem.Allocator, options: SortOptions, readerables: anytype, writer: anytype) !void {
    var lines = std.ArrayList([]const u8).init(allocator);
    for (readerables) |r| {
        var line_iter = util.lineIterator(allocator, r.reader());
        while (try line_iter.nextOwned()) |line| {
            try lines.append(line);
        }
    }

    std.sort.sort([]const u8, lines.items, options, SortOptions.stringLess);

    for (lines.items) |line| {
        try writer.print("{s}\n", .{line});
    }
}
