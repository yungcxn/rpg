const std = @import("std");
const builtin = @import("builtin");

// this module "globafies" the proc env

comptime {
    switch (builtin.os.tag) {
        // maybe wasi is supported with libc?
        .windows, .wasi => @compileError("env.zig requires a POSIX target"),
        else => {},
    }
}

var _map: *std.process.Environ.Map = undefined;

pub fn init(environ_map: *std.process.Environ.Map) void {
    _map = environ_map;
}

pub fn get(key: []const u8) ?[]const u8 {
    return _map.get(key);
}
