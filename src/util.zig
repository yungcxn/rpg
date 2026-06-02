const std = @import("std");

pub fn comptime_assert(comptime cond: bool, comptime msg: []const u8) void {
    if (!cond) @compileError(msg);
}

pub fn dprint(value: anytype) void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .int, .comptime_int => std.debug.print("{x}\n", .{value}),
        else => std.debug.print("{s}\n", .{value}),
    }
}

pub fn errprint(err: anytype) void {
    std.debug.print("error: {s}\n", .{@errorName(err)});
}

pub fn str_eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
