const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_glfw = @import("phasor-glfw");
const phasor_vulkan = @import("phasor-vulkan");
const phasor_common = @import("phasor-common");

// ============================================================================
// Assets
// ============================================================================

pub const assets = struct {
    // Placeholder for Sponza GLTF asset
    // sponza: phasor_vulkan.GltfAsset = .{ .path = "assets/sponza.glb" },
};

// ============================================================================
// Systems
// ============================================================================

fn setup_scene(mut_commands: *phasor_ecs.Commands) !void {
    // Create FPS controller camera
    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Camera3d{
            .Perspective = .{
                .fov = std.math.pi / 4.0,
                .near = 0.1,
                .far = 1000.0,
            },
        },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = 2.0, .z = 5.0 },
        },
        phasor_vulkan.FpsController{
            .move_speed = 5.0,
            .mouse_sensitivity = 0.002,
        },
    });

    // TODO: Load and spawn Sponza scene
    // Once you have the sponza.glb file, you would do:
    // const asset = &assets.sponza;
    // try asset.spawn(mut_commands, std.heap.page_allocator);

    // For now, create a simple cube as a placeholder
    const vertices = try std.heap.page_allocator.alloc(phasor_vulkan.MeshVertex, 8);
    vertices[0] = .{ .pos = .{ .x = -1.0, .y = -1.0, .z = -1.0 }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[1] = .{ .pos = .{ .x = 1.0, .y = -1.0, .z = -1.0 }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[2] = .{ .pos = .{ .x = 1.0, .y = -1.0, .z = 1.0 }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[3] = .{ .pos = .{ .x = -1.0, .y = -1.0, .z = 1.0 }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[4] = .{ .pos = .{ .x = -1.0, .y = 1.0, .z = -1.0 }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[5] = .{ .pos = .{ .x = 1.0, .y = 1.0, .z = -1.0 }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[6] = .{ .pos = .{ .x = 1.0, .y = 1.0, .z = 1.0 }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[7] = .{ .pos = .{ .x = -1.0, .y = 1.0, .z = 1.0 }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 } };

    const indices = try std.heap.page_allocator.alloc(u32, 36);
    // Front
    indices[0] = 0;
    indices[1] = 1;
    indices[2] = 2;
    indices[3] = 2;
    indices[4] = 3;
    indices[5] = 0;
    // Back
    indices[6] = 5;
    indices[7] = 4;
    indices[8] = 7;
    indices[9] = 7;
    indices[10] = 6;
    indices[11] = 5;
    // Top
    indices[12] = 4;
    indices[13] = 5;
    indices[14] = 6;
    indices[15] = 6;
    indices[16] = 7;
    indices[17] = 4;
    // Bottom
    indices[18] = 1;
    indices[19] = 0;
    indices[20] = 3;
    indices[21] = 3;
    indices[22] = 2;
    indices[23] = 1;
    // Left
    indices[24] = 4;
    indices[25] = 7;
    indices[26] = 3;
    indices[27] = 3;
    indices[28] = 0;
    indices[29] = 4;
    // Right
    indices[30] = 1;
    indices[31] = 2;
    indices[32] = 6;
    indices[33] = 6;
    indices[34] = 5;
    indices[35] = 1;

    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Mesh{
            .vertices = vertices,
            .indices = indices,
        },
        phasor_vulkan.Material{
            .color = .{ .r = 0.8, .g = 0.8, .b = 0.8, .a = 1.0 },
        },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        },
    });
}

// ============================================================================
// Main Entry Point
// ============================================================================

pub fn main() !u8 {
    var app = try phasor_ecs.App.default(std.heap.page_allocator);
    defer app.deinit();

    try app.insertResource(phasor_common.ClearColor{ .color = phasor_common.Color.BLACK });

    const window_plugin = phasor_glfw.WindowPlugin.init(.{
        .title = "Sponza Demo - GLTF Scene Loading",
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

    var fps_controller_plugin = phasor_vulkan.FpsControllerPlugin{};
    try app.addPlugin(&fps_controller_plugin);

    var parent_plugin = phasor_vulkan.ParentPlugin{};
    try app.addPlugin(&parent_plugin);

    // TODO: Add AssetPlugin once Sponza asset is ready
    // const asset_plugin = phasor_vulkan.AssetPlugin(assets).init();
    // try app.addPlugin(&asset_plugin);

    try app.addSystem("Startup", setup_scene);

    return try app.run();
}
