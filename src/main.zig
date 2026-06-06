const std = @import("std");
const Window = @import("platform.zig").Window;
const X11Window = @import("platforms/X11Window.zig");
const env = @import("util/env.zig");
const io = @import("util/io.zig");

fn crash(err: anyerror) noreturn {
    std.log.err("Crashed: {s}", .{@errorName(err)});
    return std.process.exit(1);
}

pub fn main(init: std.process.Init) void {
    env.init(init.environ_map);
    io.init(init.io);

    var window = Window(X11Window, X11Window.Error).init() catch |err| crash(err);
    defer window.deinit();

    while (true) {
        if (!window.proc_event()) break;
    }
}
