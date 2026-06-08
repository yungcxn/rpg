const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "rpg",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const c_vk_glfw = b.addTranslateC(.{
        .root_source_file = b.path("cdeps/vk_glfw.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    c_vk_glfw.linkSystemLibrary("vulkan", .{ .needed = true });
    c_vk_glfw.linkSystemLibrary("glfw", .{ .needed = true });

    exe.root_module.addImport("c_vk_glfw", c_vk_glfw.createModule());

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
