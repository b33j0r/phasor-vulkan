const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_glfw = @import("phasor-glfw");
const phasor_vulkan = @import("phasor-vulkan");
const phasor_common = @import("phasor-common");

// ============================================================================
// Cube Mesh Data
// ============================================================================

fn createCubeMesh(allocator: std.mem.Allocator) !phasor_vulkan.Mesh {
    // Cube vertices with normals and colors
    const vertices = try allocator.alloc(phasor_vulkan.MeshVertex, 24); // 6 faces * 4 vertices

    // Front face (red)
    vertices[0] = .{ .pos = .{ .x = -0.5, .y = -0.5, .z = 0.5 }, .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .color = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 } };
    vertices[1] = .{ .pos = .{ .x = 0.5, .y = -0.5, .z = 0.5 }, .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .color = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 } };
    vertices[2] = .{ .pos = .{ .x = 0.5, .y = 0.5, .z = 0.5 }, .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .color = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 } };
    vertices[3] = .{ .pos = .{ .x = -0.5, .y = 0.5, .z = 0.5 }, .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .color = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 } };

    // Back face (green)
    vertices[4] = .{ .pos = .{ .x = 0.5, .y = -0.5, .z = -0.5 }, .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .color = .{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 } };
    vertices[5] = .{ .pos = .{ .x = -0.5, .y = -0.5, .z = -0.5 }, .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .color = .{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 } };
    vertices[6] = .{ .pos = .{ .x = -0.5, .y = 0.5, .z = -0.5 }, .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .color = .{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 } };
    vertices[7] = .{ .pos = .{ .x = 0.5, .y = 0.5, .z = -0.5 }, .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .color = .{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 } };

    // Top face (blue)
    vertices[8] = .{ .pos = .{ .x = -0.5, .y = 0.5, .z = 0.5 }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .color = .{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 } };
    vertices[9] = .{ .pos = .{ .x = 0.5, .y = 0.5, .z = 0.5 }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .color = .{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 } };
    vertices[10] = .{ .pos = .{ .x = 0.5, .y = 0.5, .z = -0.5 }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .color = .{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 } };
    vertices[11] = .{ .pos = .{ .x = -0.5, .y = 0.5, .z = -0.5 }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .color = .{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 } };

    // Bottom face (yellow)
    vertices[12] = .{ .pos = .{ .x = -0.5, .y = -0.5, .z = -0.5 }, .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 } };
    vertices[13] = .{ .pos = .{ .x = 0.5, .y = -0.5, .z = -0.5 }, .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 } };
    vertices[14] = .{ .pos = .{ .x = 0.5, .y = -0.5, .z = 0.5 }, .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 } };
    vertices[15] = .{ .pos = .{ .x = -0.5, .y = -0.5, .z = 0.5 }, .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 } };

    // Right face (cyan)
    vertices[16] = .{ .pos = .{ .x = 0.5, .y = -0.5, .z = 0.5 }, .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .color = .{ .r = 0.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[17] = .{ .pos = .{ .x = 0.5, .y = -0.5, .z = -0.5 }, .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .color = .{ .r = 0.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[18] = .{ .pos = .{ .x = 0.5, .y = 0.5, .z = -0.5 }, .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .color = .{ .r = 0.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[19] = .{ .pos = .{ .x = 0.5, .y = 0.5, .z = 0.5 }, .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .color = .{ .r = 0.0, .g = 1.0, .b = 1.0, .a = 1.0 } };

    // Left face (magenta)
    vertices[20] = .{ .pos = .{ .x = -0.5, .y = -0.5, .z = -0.5 }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 0.0, .b = 1.0, .a = 1.0 } };
    vertices[21] = .{ .pos = .{ .x = -0.5, .y = -0.5, .z = 0.5 }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 0.0, .b = 1.0, .a = 1.0 } };
    vertices[22] = .{ .pos = .{ .x = -0.5, .y = 0.5, .z = 0.5 }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 0.0, .b = 1.0, .a = 1.0 } };
    vertices[23] = .{ .pos = .{ .x = -0.5, .y = 0.5, .z = -0.5 }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 0.0, .b = 1.0, .a = 1.0 } };

    // Cube indices (2 triangles per face)
    const indices = try allocator.alloc(u32, 36); // 6 faces * 2 triangles * 3 indices

    // Front face
    indices[0] = 0;
    indices[1] = 1;
    indices[2] = 2;
    indices[3] = 2;
    indices[4] = 3;
    indices[5] = 0;

    // Back face
    indices[6] = 4;
    indices[7] = 5;
    indices[8] = 6;
    indices[9] = 6;
    indices[10] = 7;
    indices[11] = 4;

    // Top face
    indices[12] = 8;
    indices[13] = 9;
    indices[14] = 10;
    indices[15] = 10;
    indices[16] = 11;
    indices[17] = 8;

    // Bottom face
    indices[18] = 12;
    indices[19] = 13;
    indices[20] = 14;
    indices[21] = 14;
    indices[22] = 15;
    indices[23] = 12;

    // Right face
    indices[24] = 16;
    indices[25] = 17;
    indices[26] = 18;
    indices[27] = 18;
    indices[28] = 19;
    indices[29] = 16;

    // Left face
    indices[30] = 20;
    indices[31] = 21;
    indices[32] = 22;
    indices[33] = 22;
    indices[34] = 23;
    indices[35] = 20;

    return phasor_vulkan.Mesh{
        .vertices = vertices,
        .indices = indices,
    };
}

// ============================================================================
// Systems
// ============================================================================

fn setup_scene(mut_commands: *phasor_ecs.Commands) !void {
    const allocator = std.heap.c_allocator;

    // Create camera with perspective projection
    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Camera3d{
            .Perspective = .{
                .fov = std.math.pi / 4.0,
                .near = 0.1,
                .far = 100.0,
            },
        },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = 0.0, .z = 5.0 },
        },
        phasor_vulkan.OrbitCamera{
            .distance = 5.0,
            .rotation_speed = 1.0,
        },
    });

    // Create colored cube
    const mesh = try createCubeMesh(allocator);
    _ = try mut_commands.createEntity(.{
        mesh,
        phasor_vulkan.Material{
            .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        },
        phasor_vulkan.Transform3d{},
    });
}

fn orbit_camera_system(
    q_camera: phasor_ecs.Query(.{ phasor_vulkan.OrbitCamera, phasor_vulkan.Transform3d }),
    delta_time: phasor_ecs.Res(phasor_vulkan.DeltaTime),
) !void {
    const dt = delta_time.ptr.seconds;

    var it = q_camera.iterator();
    while (it.next()) |entity| {
        const orbit = entity.get(phasor_vulkan.OrbitCamera).?;
        const transform = entity.get(phasor_vulkan.Transform3d).?;

        // Update angle
        orbit.angle += orbit.rotation_speed * dt;

        // Update camera position in orbit
        transform.translation.x = orbit.target.x + orbit.distance * @cos(orbit.angle);
        transform.translation.z = orbit.target.z + orbit.distance * @sin(orbit.angle);
        transform.translation.y = orbit.target.y;
    }
}

fn rotate_cube_system(
    q_mesh: phasor_ecs.Query(.{ phasor_vulkan.Mesh, phasor_vulkan.Transform3d }),
    delta_time: phasor_ecs.Res(phasor_vulkan.DeltaTime),
) !void {
    const dt = delta_time.ptr.seconds;

    var it = q_mesh.iterator();
    while (it.next()) |entity| {
        const transform = entity.get(phasor_vulkan.Transform3d).?;

        // Rotate the cube on multiple axes
        transform.rotation.x += 0.5 * dt;
        transform.rotation.y += 1.0 * dt;
        transform.rotation.z += 0.3 * dt;
    }
}

// ============================================================================
// Main Entry Point
// ============================================================================

pub fn main() !u8 {
    const allocator = std.heap.c_allocator;
    var app = try phasor_ecs.App.default(allocator);
    defer app.deinit();

    const allocator_plugin = phasor_vulkan.AllocatorPlugin{ .allocator = allocator };
    try app.addPlugin(&allocator_plugin);

    try app.insertResource(phasor_common.ClearColor{ .color = phasor_common.Color.BLACK });

    const window_plugin = phasor_glfw.WindowPlugin.init(.{
        .title = "Cube Demo - 3D Mesh Rendering",
        .width = 800,
        .height = 600,
    });
    try app.addPlugin(&window_plugin);

    var input_plugin = phasor_glfw.InputPlugin{};
    try app.addPlugin(&input_plugin);

    const vk_plugin = phasor_vulkan.VulkanPlugin.init(.{});
    try app.addPlugin(&vk_plugin);

    var time_plugin = phasor_vulkan.TimePlugin{};
    try app.addPlugin(&time_plugin);

    try app.addSystem("Startup", setup_scene);
    try app.addSystem("Update", orbit_camera_system);
    try app.addSystem("Update", rotate_cube_system);

    return try app.run();
}
