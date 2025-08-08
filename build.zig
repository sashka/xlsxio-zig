const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build options
    const build_static = b.option(bool, "build_static", "Build static libraries") orelse true;
    const build_shared = b.option(bool, "build_shared", "Build shared libraries") orelse false;

    // Check conditions
    if (!build_static and !build_shared) {
        @panic("Cannot build with both build_static and build_shared disabled");
    }

    // Dependencies
    const expat_dep = b.dependency("expat", .{
        .target = target,
        .optimize = optimize,
    });

    const libzip_dep = b.dependency("libzip", .{
        .target = target,
        .optimize = optimize,
    });

    // UTF-8 version (default)
    var xlsxio_read_static: ?*std.Build.Step.Compile = null;
    var xlsxio_read_shared: ?*std.Build.Step.Compile = null;

    if (build_static) {
        xlsxio_read_static = b.addStaticLibrary(.{
            .name = "xlsxio_read",
            .target = target,
            .optimize = optimize,
        });

        xlsxio_read_static.?.addIncludePath(.{ .cwd_relative = "lib" });
        xlsxio_read_static.?.addCSourceFiles(.{
            .files = &.{
                "lib/xlsxio_read.c",
                "lib/xlsxio_read_sharedstrings.c",
            },
            .flags = &.{
                "-DBUILD_XLSXIO_STATIC",
                "-DUSE_LIBZIP",
            },
        });
        xlsxio_read_static.?.linkLibrary(expat_dep.artifact("expat"));
        xlsxio_read_static.?.linkLibrary(libzip_dep.artifact("zip"));
        b.installArtifact(xlsxio_read_static.?);
    }

    if (build_shared) {
        xlsxio_read_shared = b.addSharedLibrary(.{
            .name = "xlsxio_read",
            .target = target,
            .optimize = optimize,
        });

        xlsxio_read_shared.?.addIncludePath(.{ .cwd_relative = "lib" });
        xlsxio_read_shared.?.addCSourceFiles(.{
            .files = &.{
                "lib/xlsxio_read.c",
                "lib/xlsxio_read_sharedstrings.c",
            },
            .flags = &.{
                "-DBUILD_XLSXIO_SHARED",
                "-DUSE_LIBZIP",
            },
        });
        xlsxio_read_shared.?.linkLibrary(expat_dep.artifact("expat"));
        xlsxio_read_shared.?.linkLibrary(libzip_dep.artifact("zip"));
        b.installArtifact(xlsxio_read_shared.?);
    }

    // Create and expose the xlsxio library
    const xlsxio_lib = b.addStaticLibrary(.{
        .name = "xlsxio",
        .root_source_file = .{ .cwd_relative = "src/xlsxio.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add include paths to the library
    xlsxio_lib.addIncludePath(.{ .cwd_relative = "lib" });

    // Link the library with the xlsxio C library
    if (xlsxio_read_static) |lib| {
        xlsxio_lib.linkLibrary(lib);
    } else if (xlsxio_read_shared) |lib| {
        xlsxio_lib.linkLibrary(lib);
    }

    // Link with dependencies
    xlsxio_lib.linkLibrary(expat_dep.artifact("expat"));
    xlsxio_lib.linkLibrary(libzip_dep.artifact("zip"));

    // Install the library
    b.installArtifact(xlsxio_lib);
}
