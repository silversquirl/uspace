const std = @import("std");

pub fn lineIterator(allocator: *std.mem.Allocator, reader: anytype) LineIterator(@TypeOf(reader)) {
    return LineIterator(@TypeOf(reader)){
        .r = reader,
        .buf = std.ArrayList(u8).init(allocator),
    };
}
pub fn LineIterator(comptime Reader: type) type {
    return struct {
        r: Reader,
        buf: ?std.ArrayList(u8),

        const Self = @This();

        pub fn deinit(self: Self) void {
            if (self.buf) |buf| buf.deinit();
        }

        pub fn next(self: *Self) !?[]const u8 {
            if (self.buf) |*buf| {
                if (try self.nextArrayList(buf)) {
                    return buf.items;
                } else {
                    buf.deinit();
                    self.buf = null;
                }
            }
            return null;
        }

        pub fn nextOwned(self: *Self) !?[]const u8 {
            if (try self.next()) |_| {
                return self.buf.?.toOwnedSlice();
            } else {
                return null;
            }
        }

        pub fn nextArrayList(self: *Self, buf: *std.ArrayList(u8)) !bool {
            self.r.readUntilDelimiterArrayList(buf, '\n', std.math.maxInt(usize)) catch |err| switch (err) {
                error.EndOfStream => {
                    if (buf.items.len == 0) return false;
                },
                else => |e| return e,
            };
            return true;
        }
    };
}
