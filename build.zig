const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xlsxio_read_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    xlsxio_read_module.addIncludePath(b.path("lib"));
    xlsxio_read_module.addCSourceFiles(.{
        .files = &.{
            "lib/xlsxio_read.c",
            "lib/xlsxio_read_sharedstrings.c",
        },
        .flags = &.{
            "-DBUILD_XLSXIO_STATIC",
            "-DUSE_LIBZIP",
        },
    });

    // Add dependencies for xlsxio_read
    const expat_dep = b.dependency("expat", .{
        .target = target,
        .optimize = optimize,
    });
    xlsxio_read_module.linkLibrary(expat_dep.artifact("expat"));

    const libzip_dep = b.dependency("libzip", .{
        .target = target,
        .optimize = optimize,
    });
    xlsxio_read_module.linkLibrary(libzip_dep.artifact("zip"));

    const xlsxio_read_lib = b.addLibrary(.{
        .name = "xlsxio_read",
        .linkage = .static,
        .root_module = xlsxio_read_module,
    });

    const xlsxio_module = b.addModule("xlsxio", .{
        .root_source_file = b.path("src/xlsxio.zig"),
        .link_libc = true,
    });
    xlsxio_module.addIncludePath(b.path("lib"));
    xlsxio_module.addIncludePath(b.path("."));
    xlsxio_module.linkLibrary(xlsxio_read_lib);

    b.installArtifact(xlsxio_read_lib);
}
