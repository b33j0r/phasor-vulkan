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
    const phasor_phases_mod = phasor_ecs_dep.module("phasor-phases");

    // stb_truetype for font rendering
    const stb_dep = b.dependency("stb", .{
        .target = target,
        .optimize = optimize,
    });

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

    //
    // ─── BUILD STB_TRUETYPE C LIB ──────────────────────────────────────
    //
    const stb_include = stb_dep.path("");

    const stb_lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });
    stb_lib_mod.addIncludePath(stb_include);

    const stb_lib = b.addLibrary(.{
        .name = "stb_truetype",
        .linkage = .static,
        .root_module = stb_lib_mod,
    });

    stb_lib.addCSourceFile(.{
        .file = b.path("lib/stb_truetype/stb_truetype.c"),
        .flags = &.{},
    });

    // Expose stb_truetype module
    const stb_truetype_mod = b.addModule("stb_truetype", .{
        .root_source_file = b.path("lib/stb_truetype/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    stb_truetype_mod.addIncludePath(stb_include);

    // stb_image for image loading
    const stb_image_lib = b.addLibrary(.{
        .name = "stb_image",
        .linkage = .static,
        .root_module = stb_lib_mod,
    });
    stb_image_lib.addCSourceFile(.{
        .file = b.path("lib/stb_image/stb_image.c"),
        .flags = &.{},
    });

    const stb_image_mod = b.addModule("stb_image", .{
        .root_source_file = b.path("lib/stb_image/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    stb_image_mod.addIncludePath(stb_include);

    // Vulkan
    const vulkan_headers_dep = b.dependency("vulkan_headers", .{});

    const vulkan = b.dependency("vulkan", .{
        .registry = vulkan_headers_dep.path("registry/vk.xml"),
    }).module("vulkan-zig");

    //
    // ─── SHADER COMPILATION ────────────────────────────────────────
    //
    // Compile all shaders in shaders/ directory to SPIR-V
    const compile_shaders = b.step("shaders", "Compile GLSL shaders to SPIR-V");

    const shader_files = [_]ShaderFile{
        .{ .src = "shaders/triangle.vert", .dst = "shaders/triangle.vert.spv" },
        .{ .src = "shaders/triangle.frag", .dst = "shaders/triangle.frag.spv" },
        .{ .src = "shaders/sprite.vert", .dst = "shaders/sprite.vert.spv" },
        .{ .src = "shaders/sprite.frag", .dst = "shaders/sprite.frag.spv" },
        .{ .src = "shaders/circle.vert", .dst = "shaders/circle.vert.spv" },
        .{ .src = "shaders/circle.frag", .dst = "shaders/circle.frag.spv" },
        .{ .src = "shaders/rectangle.vert", .dst = "shaders/rectangle.vert.spv" },
        .{ .src = "shaders/rectangle.frag", .dst = "shaders/rectangle.frag.spv" },
        .{ .src = "shaders/mesh.vert", .dst = "shaders/mesh.vert.spv" },
        .{ .src = "shaders/mesh.frag", .dst = "shaders/mesh.frag.spv" },
    };

    // Compile shaders and collect their outputs
    var shader_outputs: [shader_files.len]std.Build.LazyPath = undefined;
    inline for (shader_files, 0..) |shader, i| {
        const compile_cmd = b.addSystemCommand(&.{"glslc"});
        compile_cmd.addFileArg(b.path(shader.src));
        compile_cmd.addArg("-o");
        const output = compile_cmd.addOutputFileArg(std.fs.path.basename(shader.dst));
        compile_shaders.dependOn(&compile_cmd.step);
        shader_outputs[i] = output;
    }

    // Generate shader imports module and add compiled shaders to it
    const write_shader_imports = b.addWriteFiles();
    const shader_imports_path = write_shader_imports.add("shaders.zig", generateShaderImports());

    // Copy compiled shaders into the writeFiles directory
    inline for (shader_files, 0..) |shader, i| {
        _ = write_shader_imports.addCopyFile(shader_outputs[i], std.fs.path.basename(shader.dst));
    }

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

    // Optional configuration for Assimp include/lib directories
    const assimp_include_dir = b.option([]const u8, "assimp-include-dir", "Path to Assimp headers (if not discoverable)");
    // const assimp_lib_dir = b.option([]const u8, "assimp-lib-dir", "Path to Assimp library directory (if not on default search paths)");

    // Assimp thin wrapper module (C headers only)
    const assimp_mod = b.addModule("assimp", .{
        .root_source_file = b.path("lib/assimp/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (assimp_include_dir) |inc| {
        assimp_mod.addIncludePath(.{ .cwd_relative = inc });
    } else {
        // Try to find Assimp via pkg-config
        var code: u8 = undefined;
        const pkg_config_result = b.runAllowFail(&.{ "pkg-config", "--cflags", "assimp" }, &code, .Ignore) catch null;
        if (pkg_config_result) |output| {
            const trimmed = std.mem.trim(u8, output, " \n\r\t");
            if (std.mem.startsWith(u8, trimmed, "-I")) {
                const include_path = trimmed[2..];
                assimp_mod.addIncludePath(.{ .cwd_relative = include_path });
            }
        }
    }

    // Common neutral model types shared between importer and engine
    const phasor_vulkan_common_mod = b.addModule("phasor-vulkan-common", .{
        .root_source_file = b.path("lib/common/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-common", .module = phasor_common_mod },
        },
    });

    // High-level Assimp importer producing ModelData
    const phasor_assimp_mod = b.addModule("phasor-assimp", .{
        .root_source_file = b.path("lib/phasor-assimp/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "assimp", .module = assimp_mod },
            .{ .name = "phasor-vulkan-common", .module = phasor_vulkan_common_mod },
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
            .{ .name = "stb_truetype", .module = stb_truetype_mod },
            .{ .name = "stb_image", .module = stb_image_mod },
            // Import the common model types and the assimp importer for engine conversions
            .{ .name = "phasor-vulkan-common", .module = phasor_vulkan_common_mod },
            .{ .name = "phasor-assimp", .module = phasor_assimp_mod },
        },
    });

    // Add generated shader imports to the render module
    phasor_vulkan_mod.addImport("shader_imports", b.createModule(.{
        .root_source_file = shader_imports_path,
    }));
    phasor_vulkan_mod.linkLibrary(stb_image_lib);

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

    //
    // ─── SPRITES EXAMPLE ───────────────────────────────────────────
    //
    const examples_sprites_mod = b.addModule("examples-sprites", .{
        .root_source_file = b.path("examples/sprites/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-vulkan", .module = phasor_vulkan_mod },
            .{ .name = "phasor-glfw", .module = phasor_glfw_mod },
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
            .{ .name = "phasor-common", .module = phasor_common_mod },
        },
    });

    const examples_sprites = b.addExecutable(.{
        .name = "examples-sprites",
        .root_module = examples_sprites_mod,
    });

    examples_sprites.linkLibC();
    examples_sprites.linkLibrary(glfw_lib);
    examples_sprites.linkLibrary(stb_lib);
    examples_sprites.linkSystemLibrary("vulkan");

    if (target.result.os.tag.isDarwin()) {
        examples_sprites.linkFramework("Cocoa");
        examples_sprites.linkFramework("IOKit");
        examples_sprites.linkFramework("CoreVideo");
        examples_sprites.linkSystemLibrary("objc");
    }

    const run_examples_sprites = b.addRunArtifact(examples_sprites);
    const sprites_step = b.step("sprites", "Run sprites example");
    sprites_step.dependOn(&run_examples_sprites.step);

    b.installArtifact(examples_sprites);

    //
    // ─── PHARKANOID EXAMPLE ────────────────────────────────────────
    //
    const examples_pharkanoid_mod = b.addModule("examples-pharkanoid", .{
        .root_source_file = b.path("examples/pharkanoid/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-vulkan", .module = phasor_vulkan_mod },
            .{ .name = "phasor-glfw", .module = phasor_glfw_mod },
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
            .{ .name = "phasor-common", .module = phasor_common_mod },
            .{ .name = "phasor-phases", .module = phasor_phases_mod },
        },
    });

    const examples_pharkanoid = b.addExecutable(.{
        .name = "examples-pharkanoid",
        .root_module = examples_pharkanoid_mod,
    });

    examples_pharkanoid.linkLibC();
    examples_pharkanoid.linkLibrary(glfw_lib);
    examples_pharkanoid.linkLibrary(stb_lib);
    examples_pharkanoid.linkSystemLibrary("vulkan");

    if (target.result.os.tag.isDarwin()) {
        examples_pharkanoid.linkFramework("Cocoa");
        examples_pharkanoid.linkFramework("IOKit");
        examples_pharkanoid.linkFramework("CoreVideo");
        examples_pharkanoid.linkSystemLibrary("objc");
    }

    const run_examples_pharkanoid = b.addRunArtifact(examples_pharkanoid);
    const pharkanoid_step = b.step("pharkanoid", "Run pharkanoid example");
    pharkanoid_step.dependOn(&run_examples_pharkanoid.step);

    b.installArtifact(examples_pharkanoid);

    //
    // ─── CUBE EXAMPLE ──────────────────────────────────────────────
    //
    // Compile cube-specific shaders
    const cube_shader_files = [_]ShaderFile{
        .{ .src = "examples/cube/shaders/cube.vert", .dst = "cube.vert.spv" },
        .{ .src = "examples/cube/shaders/cube.frag", .dst = "cube.frag.spv" },
    };

    var cube_shader_outputs: [cube_shader_files.len]std.Build.LazyPath = undefined;
    inline for (cube_shader_files, 0..) |shader, i| {
        const compile_cmd = b.addSystemCommand(&.{"glslc"});
        compile_cmd.addFileArg(b.path(shader.src));
        compile_cmd.addArg("-o");
        const output = compile_cmd.addOutputFileArg(std.fs.path.basename(shader.dst));
        compile_shaders.dependOn(&compile_cmd.step);
        cube_shader_outputs[i] = output;
    }

    // Generate cube shader imports module
    const write_cube_shaders = b.addWriteFiles();
    const cube_shader_imports_path = write_cube_shaders.add("cube_shaders.zig",
        \\// Auto-generated cube shader imports
        \\pub const cube_vert align(@alignOf(u32)) = @embedFile("cube.vert.spv").*;
        \\pub const cube_frag align(@alignOf(u32)) = @embedFile("cube.frag.spv").*;
        \\
    );

    inline for (cube_shader_files, 0..) |shader, i| {
        _ = write_cube_shaders.addCopyFile(cube_shader_outputs[i], std.fs.path.basename(shader.dst));
    }

    const examples_cube_mod = b.addModule("examples-cube", .{
        .root_source_file = b.path("examples/cube/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-vulkan", .module = phasor_vulkan_mod },
            .{ .name = "phasor-glfw", .module = phasor_glfw_mod },
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
            .{ .name = "phasor-common", .module = phasor_common_mod },
        },
    });

    // Add cube shaders import to the cube example
    examples_cube_mod.addImport("cube_shaders", b.createModule(.{
        .root_source_file = cube_shader_imports_path,
    }));

    const examples_cube = b.addExecutable(.{
        .name = "examples-cube",
        .root_module = examples_cube_mod,
    });

    examples_cube.linkLibC();
    examples_cube.linkLibrary(glfw_lib);
    examples_cube.linkSystemLibrary("vulkan");

    if (target.result.os.tag.isDarwin()) {
        examples_cube.linkFramework("Cocoa");
        examples_cube.linkFramework("IOKit");
        examples_cube.linkFramework("CoreVideo");
        examples_cube.linkSystemLibrary("objc");
    }

    const run_examples_cube = b.addRunArtifact(examples_cube);
    const cube_step = b.step("cube", "Run cube example");
    cube_step.dependOn(&run_examples_cube.step);

    b.installArtifact(examples_cube);

    //
    // ─── WAREHOUSE EXAMPLE ─────────────────────────────────────────
    //
    const examples_warehouse_mod = b.addModule("examples-warehouse", .{
        .root_source_file = b.path("examples/warehouse/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-vulkan", .module = phasor_vulkan_mod },
            .{ .name = "phasor-glfw", .module = phasor_glfw_mod },
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
            .{ .name = "phasor-common", .module = phasor_common_mod },
        },
    });

    const examples_warehouse = b.addExecutable(.{
        .name = "examples-warehouse",
        .root_module = examples_warehouse_mod,
    });

    examples_warehouse.linkLibC();
    examples_warehouse.linkLibrary(glfw_lib);
    examples_warehouse.linkSystemLibrary("vulkan");

    if (target.result.os.tag.isDarwin()) {
        examples_warehouse.linkFramework("Cocoa");
        examples_warehouse.linkFramework("IOKit");
        examples_warehouse.linkFramework("CoreVideo");
        examples_warehouse.linkSystemLibrary("objc");
    }

    const run_examples_warehouse = b.addRunArtifact(examples_warehouse);
    const warehouse_step = b.step("warehouse", "Run warehouse example");
    warehouse_step.dependOn(&run_examples_warehouse.step);

    b.installArtifact(examples_warehouse);

    //
    // ─── MODEL IMPORT EXAMPLE (GLB/GLTF via Assimp) ────────────────
    //
    // Compile model_import-specific shaders
    const model_import_shader_files = [_]ShaderFile{
        .{ .src = "examples/model_import/shaders/debug_uv.vert", .dst = "debug_uv.vert.spv" },
        .{ .src = "examples/model_import/shaders/debug_uv.frag", .dst = "debug_uv.frag.spv" },
    };

    var model_import_shader_outputs: [model_import_shader_files.len]std.Build.LazyPath = undefined;
    inline for (model_import_shader_files, 0..) |shader, i| {
        const compile_cmd = b.addSystemCommand(&.{"glslc"});
        compile_cmd.addFileArg(b.path(shader.src));
        compile_cmd.addArg("-o");
        const output = compile_cmd.addOutputFileArg(std.fs.path.basename(shader.dst));
        compile_shaders.dependOn(&compile_cmd.step);
        model_import_shader_outputs[i] = output;
    }

    // Generate model_import shader imports module
    const write_model_import_shaders = b.addWriteFiles();
    const model_import_shader_imports_path = write_model_import_shaders.add("model_import_shaders.zig",
        \\// Auto-generated model_import shader imports
        \\pub const debug_uv_vert align(@alignOf(u32)) = @embedFile("debug_uv.vert.spv").*;
        \\pub const debug_uv_frag align(@alignOf(u32)) = @embedFile("debug_uv.frag.spv").*;
        \\
    );

    inline for (model_import_shader_files, 0..) |shader, i| {
        _ = write_model_import_shaders.addCopyFile(model_import_shader_outputs[i], std.fs.path.basename(shader.dst));
    }

    const examples_model_import_mod = b.addModule("examples-model-import", .{
        .root_source_file = b.path("examples/model_import/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor-vulkan", .module = phasor_vulkan_mod },
            .{ .name = "phasor-glfw", .module = phasor_glfw_mod },
            .{ .name = "phasor-ecs", .module = phasor_ecs_mod },
            .{ .name = "phasor-common", .module = phasor_common_mod },
        },
    });

    // Add model_import shaders import to the model_import example
    examples_model_import_mod.addImport("model_import_shaders", b.createModule(.{
        .root_source_file = model_import_shader_imports_path,
    }));

    const examples_model_import = b.addExecutable(.{
        .name = "examples-model-import",
        .root_module = examples_model_import_mod,
    });

    examples_model_import.linkLibC();
    examples_model_import.linkLibrary(glfw_lib);
    examples_model_import.linkSystemLibrary("vulkan");
    // Link Assimp and C++ stdlib (Assimp is a C++ library)
    examples_model_import.linkSystemLibrary("assimp");
    if (target.result.os.tag.isDarwin()) {
        examples_model_import.linkFramework("Cocoa");
        examples_model_import.linkFramework("IOKit");
        examples_model_import.linkFramework("CoreVideo");
        examples_model_import.linkSystemLibrary("objc");
        examples_model_import.linkSystemLibrary("c++");
    } else if (target.result.os.tag == .linux) {
        examples_model_import.linkSystemLibrary("stdc++");
    } else if (target.result.os.tag == .windows) {
        // On Windows, assuming shared assimp is available as "assimp"
        // The MSVC C++ runtime is linked automatically by Zig
    }

    const run_examples_model_import = b.addRunArtifact(examples_model_import);
    const model_import_step = b.step("model_import", "Run model import example");
    model_import_step.dependOn(&run_examples_model_import.step);

    b.installArtifact(examples_model_import);
}

const ShaderFile = struct { src: []const u8, dst: []const u8 };

fn generateShaderImports() []const u8 {
    // Simple static generation - shaders are embedded by filename only (in same dir as this file)
    return 
    \\// Auto-generated shader imports
    \\// DO NOT EDIT - generated by build.zig
    \\
    \\pub const triangle_vert align(@alignOf(u32)) = @embedFile("triangle.vert.spv").*;
    \\pub const triangle_frag align(@alignOf(u32)) = @embedFile("triangle.frag.spv").*;
    \\pub const sprite_vert align(@alignOf(u32)) = @embedFile("sprite.vert.spv").*;
    \\pub const sprite_frag align(@alignOf(u32)) = @embedFile("sprite.frag.spv").*;
    \\pub const circle_vert align(@alignOf(u32)) = @embedFile("circle.vert.spv").*;
    \\pub const circle_frag align(@alignOf(u32)) = @embedFile("circle.frag.spv").*;
    \\pub const rectangle_vert align(@alignOf(u32)) = @embedFile("rectangle.vert.spv").*;
    \\pub const rectangle_frag align(@alignOf(u32)) = @embedFile("rectangle.frag.spv").*;
    \\pub const mesh_vert align(@alignOf(u32)) = @embedFile("mesh.vert.spv").*;
    \\pub const mesh_frag align(@alignOf(u32)) = @embedFile("mesh.frag.spv").*;
    \\
    ;
}
