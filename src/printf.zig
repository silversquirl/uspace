const std = @import("std");

fn contains(array: []const u8, char: u8) bool {
    for (array) |element| {
        if (element == char) {
            return true;
        }
    }
    return false;
}

const Flags = struct {
    left_just: bool = false,
    show_sign: bool = false,
    no_sign_prefix: bool = false,
    alt_form: bool = false,
    zero_pad: bool = false,
};

fn intParse(str: []const u8, pos: *usize) usize {
    var n: usize = 0;
    while (true) : (pos.* += 1) {
        const digit = std.fmt.charToDigit(str[pos.*], 10) catch |err| {
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

fn fmt_percent(
    args: *std.process.ArgIterator,
    flags: Flags,
    field_width: usize,
    precision: usize,
) []const u8 {
    return "%";
}

fn fmt_blank(
    args: *std.process.ArgIterator,
    flags: Flags,
    field_width: usize,
    precision: usize,
) []const u8 {
    return "";
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    const err = std.io.getStdErr().writer();
    var args = std.process.args();
    _ = args.skip();

    const fmt_optional = args.nextPosix();
    if (fmt_optional == null) {
        try err.print("printf: not enough arguments\n", .{});
        return;
    }
    const fmt = fmt_optional.?;

    for (fmt) |c| {
        if (c == '%') {
            break;
        }
    } else {
        try out.print("{s}", .{fmt});
        return;
    }

    var arg = args.nextPosix();
    while (arg != null) {
        var i: usize = 0;
        while (i < fmt.len) : (i += 1) {
            if (fmt[i] == '%') {
                const start = i;
                i += 1;

                var flags = Flags{};
                while (true) : (i += 1) {
                    switch (fmt[i]) {
                        '-' => flags.left_just = true,
                        '+' => flags.show_sign = true,
                        ' ' => flags.no_sign_prefix = true,
                        '#' => flags.alt_form = true,
                        '0' => flags.zero_pad = true,
                        else => break,
                    }
                }

                const field_width = intParse(fmt, &i);

                var precision: usize = 0;
                if (fmt[i] == '.') {
                    i += 1;
                    precision = intParse(fmt, &i);
                }

                const fmt_fn = switch (fmt[i]) {
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
                    '%' => fmt_percent,
                    else => fmt_blank,
                };
                if (fmt_fn == fmt_blank) {
                    try err.print("printf: {s}: invalid directive\n", .{fmt[start..i]});
                }
            } else {
                try out.print("{c}", .{fmt[i]});
            }
        }
        arg = args.nextPosix();
    }
}
