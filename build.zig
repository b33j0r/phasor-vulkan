const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // ─── DEPENDENCIES ──────────────────────────────────────────────
    //
    // GLFW tarball (C sources only)
    const glfw_dep = b.dependency("glfw", .{
        .target = target,
        .optimize = optimize,
    });

    // Phasor ECS
    const phasor_ecs_dep = b.dependency("phasor_ecs", .{
        .target = target,
        .optimize = optimize,
    });
    const phasor_ecs_mod = phasor_ecs_dep.module("phasor-ecs");
    const phasor_common_mod = phasor_ecs_dep.module("phasor-common");

    //
    // ─── BUILD GLFW C LIB ──────────────────────────────────────────
    //
    // Build the GLFW C library from the tarball and expose a Zig module that cImports it.
    const glfw_include = glfw_dep.path("include");

    const glfw_lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });
    glfw_lib_mod.addIncludePath(glfw_include);
    glfw_lib_mod.addCMacro("_GLFW_COCOA", "1");

    const glfw_lib = b.addLibrary(.{
        .name = "glfw",
        .linkage = .static,
        .root_module = glfw_lib_mod,
    });

    // Common sources
    glfw_lib.addCSourceFiles(.{
        .root = glfw_dep.path(""),
        .files = &.{
            // Core
            "src/context.c",
            "src/init.c",
            "src/input.c",
            "src/monitor.c",
            "src/platform.c",
            "src/vulkan.c",
            "src/window.c",
            // POSIX helpers
            "src/posix_thread.c",
            "src/posix_module.c",
            // Null platform (required by platform.c references)
            "src/null_init.c",
            "src/null_joystick.c",
            "src/null_monitor.c",
            "src/null_window.c",
            // macOS platform
            "src/cocoa_init.m",
            "src/cocoa_joystick.m",
            "src/cocoa_monitor.m",
            "src/cocoa_window.m",
            "src/cocoa_time.c",
            "src/nsgl_context.m",
            // Optional GL contexts (not actually used with Vulkan but required for link on some platforms)
            "src/egl_context.c",
            "src/osmesa_context.c",
        },
        .flags = &.{
            // Silence some warnings to match upstream CMake defaults; ARC must be disabled for GLFW's ObjC files
            "-D_GLFW_COCOA",
            "-Wno-deprecated-declarations",
        },
    });

    // On macOS we must link against these frameworks
    if (target.result.os.tag.isDarwin()) {
        glfw_lib.linkFramework("Cocoa");
        glfw_lib.linkFramework("IOKit");
        glfw_lib.linkFramework("CoreVideo");
    }

    // Expose a Zig module for our thin cImport wrapper and make sure it sees GLFW headers
    const glfw_mod = b.addModule("glfw", .{
        .root_source_file = b.path("lib/glfw/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    glfw_mod.addIncludePath(glfw_include);

    // Vulkan
    const vulkan_headers_dep = b.dependency("vulkan_headers", .{});

    const vulkan = b.dependency("vulkan", .{
        .registry = vulkan_headers_dep.path("registry/vk.xml"),
    }).module("vulkan-zig");

    //
    // ─── MODULES ───────────────────────────────────────────────────
    //
    const phasor_glfw_mod = b.addModule("phasor-glfw", .{
        .root_source_file = b.path("lib/phasor-glfw/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "glfw", .module = glfw_mod },
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
            .{ .name = "phasor-common", .module = phasor_common_mod },
        },
    });

    const phasor_vulkan_mod = b.addModule("phasor-vulkan", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "vulkan", .module = vulkan },
            .{ .name = "phasor-glfw", .module = phasor_glfw_mod },
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
            .{ .name = "phasor-common", .module = phasor_common_mod },
            .{ .name = "glfw", .module = glfw_mod },
        },
    });


    //
    // ─── EXAMPLES ──────────────────────────────────────────────────
    //
    const examples_triangle_mod = b.addModule("examples-triangle", .{
        .root_source_file = b.path("examples/triangle/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-vulkan", .module = phasor_vulkan_mod },
            .{ .name = "phasor-glfw", .module = phasor_glfw_mod },
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
            .{ .name = "phasor-common", .module = phasor_common_mod },
        },
    });

    const examples_triangle = b.addExecutable(.{
        .name = "examples-triangle",
        .root_module = examples_triangle_mod,
    });

    examples_triangle.linkLibC();
    examples_triangle.linkLibrary(glfw_lib);
    examples_triangle.linkSystemLibrary("vulkan");

    if (target.result.os.tag.isDarwin()) {
        examples_triangle.linkFramework("Cocoa");
        examples_triangle.linkFramework("IOKit");
        examples_triangle.linkFramework("CoreVideo");
        examples_triangle.linkSystemLibrary("objc");
    }

    const run_examples_triangle = b.addRunArtifact(examples_triangle);
    const run_step = b.step("triangle", "Run triangle example");
    run_step.dependOn(&run_examples_triangle.step);

    b.installArtifact(examples_triangle);
}
