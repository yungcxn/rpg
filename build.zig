const std = @import("std");
const builtin = @import("builtin");

const EnvVars = struct {
    GLFW_INCLUDE: ?[]const u8,
    VULKAN_INCLUDE: ?[]const u8,
};

fn panic(msg: []const u8) noreturn {
    std.log.err("{s}", .{msg});
    return std.process.exit(1);
}

fn get_env_vars(b: *std.Build) EnvVars {
    // first look into the environment variables, then into a .env file if it exists.
    var env = std.c.environ;
    var env_vars: EnvVars = undefined;
    // null out
    inline for (@typeInfo(EnvVars).@"struct".fields) |field| {
        @field(env_vars, field.name) = null;
    }

    while (env[0] != null) : (env += 1) {
        const entry = env[0].?; // C string: "KEY=VALUE"
        const kv = std.mem.span(entry);
        const eq_idx = std.mem.indexOf(u8, kv, "=") orelse continue;
        const key = kv[0..eq_idx];
        const value = kv[eq_idx + 1 ..];
        inline for (@typeInfo(EnvVars).@"struct".fields) |field| {
            const name = field.name;
            if (std.mem.eql(u8, key, name)) {
                @field(env_vars, field.name) = value;
            }
        }
    }

    // check if there is one null value, if not return
    var finished = true;
    inline for (@typeInfo(EnvVars).@"struct".fields) |field| {
        if (@field(env_vars, field.name) == null) finished = false;
    }

    if (finished) return env_vars;

    // try to read from .env file
    const f = std.Io.Dir.openFile(b.build_root.handle, b.graph.io, ".env", .{}) catch {
        std.log.info("No .env file found; relying on environment variables only.", .{});
        return env_vars;
    };
    defer f.close(b.graph.io);
    const buf = b.allocator.alloc(u8, 4096) catch panic("OOM allocating .env buffer");
    var file_reader = f.reader(b.graph.io, buf);
    const reader = &file_reader.interface;
    const bytes_read = reader.readSliceShort(buf) catch |err| {
        std.log.err("Failed to read .env file: {s}", .{@errorName(err)});
        return env_vars;
    };
    var cursor: []const u8 = buf[0..bytes_read];

    while (cursor.len > 0) {
        const line_end = std.mem.indexOf(u8, cursor, "\n") orelse cursor.len;
        var line = cursor[0..line_end];
        cursor = if (line_end < cursor.len) cursor[line_end + 1 ..] else &.{};

        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }
        // skip empty lines / comments
        if (line.len == 0 or line[0] == '#') continue;

        const eq_idx = std.mem.indexOf(u8, line, "=") orelse continue;

        const key = std.mem.trim(u8, line[0..eq_idx], " \t");
        const value = std.mem.trim(u8, line[eq_idx + 1 ..], " \t");

        inline for (@typeInfo(EnvVars).@"struct".fields) |field| {
            if (std.mem.eql(u8, key, field.name)) {
                @field(env_vars, field.name) = value;
            }
        }
    }

    return env_vars;
}

fn init_c_vk_glfw(
    b: *std.Build,
    env_vars: EnvVars,
    target: anytype,
    optimize: anytype,
) *std.Build.Module {
    const glfw_include = env_vars.GLFW_INCLUDE orelse
        panic("GLFW_INCLUDE environment variable not set");
    const vulkan_include = env_vars.VULKAN_INCLUDE orelse
        panic("VULKAN_INCLUDE environment variable not set");

    const glfw_fullpath = std.mem.concat(
        b.allocator,
        u8,
        &.{ glfw_include, "/GLFW/glfw3.h" },
    ) catch panic("Failed to concatenate GLFW full path");

    const glfw_containing_fullpath = std.mem.concat(
        b.allocator,
        u8,
        &.{ glfw_include, "/GLFW/" },
    ) catch panic("Failed to concatenate GLFW containing full path");

    std.log.info("Using GLFW header: {s}", .{glfw_fullpath});
    std.log.info("Using Vulkan headers from: {s}", .{vulkan_include});

    const c_vk_glfw = b.addTranslateC(.{
        .root_source_file = std.Build.LazyPath{ .cwd_relative = glfw_fullpath },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    c_vk_glfw.addIncludePath(std.Build.LazyPath{ .cwd_relative = glfw_containing_fullpath });
    c_vk_glfw.addIncludePath(std.Build.LazyPath{ .cwd_relative = vulkan_include });
    c_vk_glfw.defineCMacro("GLFW_INCLUDE_VULKAN", null);
    c_vk_glfw.defineCMacro("GLFW_EXPOSE_NATIVE_X11", null);

    return c_vk_glfw.createModule();
}

pub fn build(b: *std.Build) void {
    if (builtin.os.tag == .windows) {
        std.log.err("For windows support need to add support for it in here.", .{});
        return;
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const env_vars = get_env_vars(b);

    const exe = b.addExecutable(.{
        .name = "rpg",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("c_vk_glfw", init_c_vk_glfw(b, env_vars, target, optimize));

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
