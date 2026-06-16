const std = @import("std");
const gpu = std.gpu;

const Vec4 = @Vector(4, f32);

const frag_color = @extern(*addrspace(.input) Vec4, .{ .name = "frag_color", .decoration = .{ .location = 0 } });
const out_color = @extern(*addrspace(.output) Vec4, .{ .name = "out_color", .decoration = .{ .location = 0 } });

export fn main() callconv(.spirv_fragment) void {
    out_color.* = frag_color.*;
}
