const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_glfw = @import("phasor-glfw");
const phasor_vulkan = @import("phasor-vulkan");
const phasor_common = @import("phasor-common");
const model_import_shaders = @import("model_import_shaders");

const App = phasor_ecs.App;
const Commands = phasor_ecs.Commands;

// Define assets for the model_import example
const ModelImportAssets = struct {
    debug_uv_shader: phasor_vulkan.Shader = .{
        .vert_spv = &model_import_shaders.debug_uv_vert,
        .frag_spv = &model_import_shaders.debug_uv_frag,
    },
};

fn setup_scene(mut_commands: *phasor_ecs.Commands, assets: phasor_ecs.Res(ModelImportAssets), r_allocator: phasor_ecs.Res(phasor_vulkan.Allocator)) !void {
    const allocator = r_allocator.ptr.allocator;

    // Camera with orbit controller (same as cube example)
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

    // Load simple textured box (GLTF with embedded texture) for verification
    const model_path: [:0]const u8 = "examples/model_import/BoxTextured.gltf";
    const model = try phasor_vulkan.loadGltf(allocator, model_path);
    std.debug.print("Loaded model with {d} meshes\n", .{model.meshes.len});

    // Spawn entities for each mesh
    for (model.meshes) |mesh_data| {
        std.debug.print("Mesh: {d} vertices, {d} indices\n", .{ mesh_data.mesh.vertices.len, mesh_data.mesh.indices.len });
        std.debug.print("First 3 verts: [{d:.2},{d:.2},{d:.2}] [{d:.2},{d:.2},{d:.2}] [{d:.2},{d:.2},{d:.2}]\n", .{
            mesh_data.mesh.vertices[0].pos.x, mesh_data.mesh.vertices[0].pos.y, mesh_data.mesh.vertices[0].pos.z,
            mesh_data.mesh.vertices[1].pos.x, mesh_data.mesh.vertices[1].pos.y, mesh_data.mesh.vertices[1].pos.z,
            mesh_data.mesh.vertices[2].pos.x, mesh_data.mesh.vertices[2].pos.y, mesh_data.mesh.vertices[2].pos.z,
        });
        std.debug.print("First tri indices: [{d}, {d}, {d}]\n", .{
            mesh_data.mesh.indices[0], mesh_data.mesh.indices[1], mesh_data.mesh.indices[2],
        });

        _ = try mut_commands.createEntity(.{
            mesh_data.mesh,
            mesh_data.material,
            phasor_vulkan.CustomShader{
                .shader = &assets.ptr.debug_uv_shader,
            },
            phasor_vulkan.Transform3d{
                .translation = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
                .rotation = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
                .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
            },
        });
    }
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

        // Update orbit angle based on rotation speed
        orbit.angle += orbit.rotation_speed * dt;

        // Update camera position along the orbit path (around target on XZ plane)
        transform.translation.x = orbit.target.x + orbit.distance * @cos(orbit.angle);
        transform.translation.z = orbit.target.z + orbit.distance * @sin(orbit.angle);
        transform.translation.y = orbit.target.y;

        // Compute look-at rotation so camera faces the target
        const dx = orbit.target.x - transform.translation.x;
        const dz = orbit.target.z - transform.translation.z;
        const dy = orbit.target.y - transform.translation.y;

        // Yaw (around Y axis)
        transform.rotation.y = std.math.atan2(dx, dz);

        // Pitch (around X axis)
        const horizontal_distance = @sqrt(dx * dx + dz * dz);
        transform.rotation.x = std.math.atan2(dy, horizontal_distance);

        // No roll for orbit camera
        transform.rotation.z = 0.0;
    }
}

pub fn main() !u8 {
    const allocator = std.heap.c_allocator;

    var app = try App.default(allocator);
    defer app.deinit();

    const allocator_plugin = phasor_vulkan.AllocatorPlugin{ .allocator = allocator };
    try app.addPlugin(&allocator_plugin);

    try app.insertResource(phasor_common.ClearColor{ .color = phasor_common.Color.BLACK });

    const window_plugin = phasor_glfw.WindowPlugin.init(.{
        .title = "Model Import - GLB/GLTF",
        .width = 1280,
        .height = 720,
    });
    try app.addPlugin(&window_plugin);

    var input_plugin = phasor_glfw.InputPlugin{};
    try app.addPlugin(&input_plugin);

    const vk_plugin = phasor_vulkan.VulkanPlugin.init(.{});
    try app.addPlugin(&vk_plugin);

    var time_plugin = phasor_vulkan.TimePlugin{};
    try app.addPlugin(&time_plugin);

    // Add model_import assets plugin
    const model_import_assets_plugin = phasor_vulkan.AssetPlugin(ModelImportAssets){};
    try app.addPlugin(&model_import_assets_plugin);

    const parent_plugin = phasor_vulkan.ParentPlugin{};
    try app.addPlugin(&parent_plugin);

    const fps_controller_plugin = phasor_vulkan.FpsControllerPlugin{};
    try app.addPlugin(&fps_controller_plugin);

    try app.addSystem("Startup", setup_scene);
    try app.addSystem("Update", orbit_camera_system);

    return try app.run();
}
