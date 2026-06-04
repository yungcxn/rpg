const std = @import("std");
const util = @import("util");
const hack = @import("hack");

fn validateScreenDI(comptime DI: type, comptime funcs: []hack.FnInfo) void {
    inline for (funcs) |func| {
        hack.assert_hasfunc_bysig(DI, func);
    }
}

pub fn Screen(comptime DI: type) type {
    validateScreenDI(DI, &.{
        .{ .name = "clear", .sig = fn () void },
        .{ .name = "draw", .sig = fn (frame: anytype) void },
    });
}
