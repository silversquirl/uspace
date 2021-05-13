const std = @import("std");

const Flags = struct {
    left_just: bool = false,
    show_sign: bool = false,
    no_sign_prefix: bool = false,
    alt_form: bool = false,
    zero_pad: bool = false,
};

const SpecifierData = struct {
    flags: Flags = Flags{},
    field_width: usize = 0,
    precision: usize = 0,
};

fn noSpecifier(str: []const u8) bool {
    for (str) |c| {
        if (c == '%') {
            return false;
        }
    }
    return true;
}

// All of these parsers parse only part of a string; i.e they parse whatever is
// valid from a starting index, this could be no characters at all, in which
// case there will be a default value specified. As an example strToInt parsing
// the string "123hello" will return 123 and increment idx to be sitting at the
// position of 'h'
const Parser = struct {
    str: []const u8,
    idx: usize = 0,

    const Self = @This();

    fn int(self: *Self) usize {
        var n: usize = 0;
        while (true) : (self.idx += 1) {
            const digit = std.fmt.charToDigit(self.str[self.idx], 10) catch |err| {
                if (err == error.InvalidCharacter) {
                    break;
                } else {
                    return err;
                }
            };

            n = n * 10 + digit;
        }
        return n;
    }

    fn flags(self: *Self) Flags {
        var out = Flags{};
        while (true) : (self.idx += 1) {
            switch (self.str[self.idx]) {
                '-' => out.left_just = true,
                '+' => out.show_sign = true,
                ' ' => out.no_sign_prefix = true,
                '#' => out.alt_form = true,
                '0' => out.zero_pad = true,
                else => return out,
            }
        }
    }

    fn spec(self: *Self) ?fn (*std.process.ArgIterator, SpecifierData) []const u8 {
        return switch (self.str[self.idx]) {
            // 'a' => {},
            // 'A' => {},
            // 'd' => {},
            // 'i' => {},
            // 'o' => {},
            // 'u' => {},
            // 'x' => {},
            // 'X' => {},
            // 'f' => {},
            // 'F' => {},
            // 'e' => {},
            // 'E' => {},
            // 'g' => {},
            // 'G' => {},
            // 'c' => {},
            // 's' => {},
            '%' => fmt_functions.percent,
            else => null,
        };
    }
};

const fmt_functions = struct {
    fn evalEscape(allocator: *std.mem.Allocator, str: []const u8) ![]const u8 {
        var list = std.ArrayList(u8).init(allocator);

        var i: usize = 0;
        while (i < str.len) : (i += 1) {
            if (str[i] == '\\') {
                i += 1;
                try list.appendSlice(switch (str[i]) {
                    '\\' => "\\", // backslash
                    'a' => &.{7}, //alert
                    'b' => &.{8}, // backspace
                    'f' => &.{12}, // form-feed
                    'n' => &.{'\n'}, // newline
                    'r' => &.{'\r'}, // carrige-return
                    't' => &.{'\t'}, // tab
                    'v' => &.{11}, // vertical tab
                    else => &.{ '\\', str[i] },
                });
            } else try list.append(str[i]);
        }

        return list.items;
    }

    fn percent(
        args: *std.process.ArgIterator,
        data: SpecifierData,
    ) []const u8 {
        return "%";
    }
};

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    const err = std.io.getStdErr().writer();
    var args = std.process.args();
    _ = args.skip();

    const allocator = std.heap.page_allocator;

    const fmt = try fmt_functions.evalEscape(allocator, args.nextPosix() orelse {
        try err.print("printf: not enough arguments\n", .{});
        return;
    });
    defer allocator.free(fmt);

    if (noSpecifier(fmt)) {
        try out.print("{s}", .{fmt});
        return;
    }

    var arg: ?[:0]const u8 = "";
    while (arg != null) {
        var i: usize = 0;
        while (i < fmt.len) : (i += 1) {
            if (fmt[i] == '%') {
                const start = i;
                i += 1;

                var parser = Parser{
                    .str = fmt,
                    .idx = i,
                };

                var spec_data = SpecifierData{};
                spec_data.flags = parser.flags();

                spec_data.field_width = parser.int();

                if (fmt[i] == '.') {
                    i += 1;
                    spec_data.precision = parser.int();
                }

                const fmt_fn = parser.spec();
                if (fmt_fn == null) {} else {
                    try out.print("{s}", .{fmt_fn.?(&args, spec_data)});
                }
            } else {
                try out.print("{c}", .{fmt[i]});
            }
        }
        arg = args.nextPosix();
    }
}
