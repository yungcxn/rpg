const std = @import("std");
const gpu = std.gpu;

const Vec2 = @Vector(2, f32);
const Vec4 = @Vector(4, f32);

const frag_color = @extern(*addrspace(.output) Vec4, .{ .name = "frag_color", .decoration = .{ .location = 0 } });

export fn main() callconv(.spirv_vertex) void {
    const idx = gpu.vertex_index;

    const px: f32, const py: f32 = switch (idx) {
        0 => .{ 0.0, -0.5 },
        1 => .{ 0.5, 0.5 },
        else => .{ -0.5, 0.5 },
    };

    const color: Vec4 = switch (idx) {
        0 => .{ 1.0, 0.0, 0.0, 1.0 },
        1 => .{ 0.0, 1.0, 0.0, 1.0 },
        else => .{ 0.0, 0.0, 1.0, 1.0 },
    };

    gpu.position_out.* = Vec4{ px, py, 0.0, 1.0 };
    frag_color.* = color;
}
