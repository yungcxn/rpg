const std = @import("std");

pub const CDependency = struct {
    import_name: []const u8,
    path: []const u8,
    libs_to_link: []const []const u8,
    link_libc: bool = true,
};

pub fn add_cdep(
    b: *std.Build,
    root_mod: *std.Build.Module,
    cdep: CDependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const mod = b.addTranslateC(.{
        .root_source_file = b.path(cdep.path),
        .target = target,
        .optimize = optimize,
        .link_libc = cdep.link_libc,
    });

    for (cdep.libs_to_link) |lib| {
        mod.linkSystemLibrary(lib, .{ .needed = true });
    }

    root_mod.addImport(cdep.import_name, mod.createModule());
}
