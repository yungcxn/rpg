const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_vk_glfw = b.addTranslateC(.{
        .root_source_file = std.Build.LazyPath{ .cwd_relative = "/usr/include/GLFW/glfw3.h" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    c_vk_glfw.addIncludePath(std.Build.LazyPath{ .cwd_relative = "/usr/include/GLFW" });
    c_vk_glfw.defineCMacro("GLFW_INCLUDE_VULKAN", null);
    c_vk_glfw.defineCMacro("GLFW_EXPOSE_NATIVE_X11", null);

    const exe = b.addExecutable(.{
        .name = "rpg",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("c_vk_glfw", c_vk_glfw.createModule());

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
