const std = @import("std");
const env = @import("util/env.zig");
const io = @import("util/io.zig");

const Renderer = @import("Renderer.zig");

fn crash(err: anyerror) noreturn {
    std.log.err("Crashed: {s}", .{@errorName(err)});
    return std.process.exit(1);
}

pub fn main(init: std.process.Init) void {
    env.init(init.environ_map);
    io.init(init.io);

    var renderer = Renderer.init() catch |err| crash(err);
    defer renderer.deinit();

    while (true) {
        _ = renderer.render();
        std.debug.print("Frame rendered\n", .{});
    }
}
