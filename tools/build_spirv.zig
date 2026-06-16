const std = @import("std");

// to be used by main `build.zig`
// use before installing artifact.
pub fn build(
    b: *std.Build,
    root_mod: *std.Build.Module,
    optimize: std.builtin.OptimizeMode,
) void {
    const spirv_target = b.resolveTargetQuery(.{
        .cpu_arch = .spirv32,
        .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
        .os_tag = .vulkan,
        .ofmt = .spirv,
    });

    const vert_obj = b.addObject(.{
        .name = "vertex",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/renderers/vk/spirv/vertex.zig"),
            .target = spirv_target,
            .optimize = optimize,
        }),
        .use_llvm = false, // spir v backend does not support llvm currently
        .use_lld = false,
    });

    const frag_obj = b.addObject(.{
        .name = "fragment",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/renderers/vk/spirv/fragment.zig"),
            .target = spirv_target,
            .optimize = optimize,
        }),
        .use_llvm = false,
        .use_lld = false,
    });

    root_mod.addAnonymousImport("vertex_shader", .{
        .root_source_file = vert_obj.getEmittedBin(),
    });
    root_mod.addAnonymousImport("fragment_shader", .{
        .root_source_file = frag_obj.getEmittedBin(),
    });
}
