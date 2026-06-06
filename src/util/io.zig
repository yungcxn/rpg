// io.zig
const std = @import("std");

// "bad" wrapper to get io globally.

var _io: std.Io = undefined;

pub fn init(io: std.Io) void {
    _io = io;
}

pub inline fn get() std.Io {
    return _io;
}
