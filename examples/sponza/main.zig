const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_glfw = @import("phasor-glfw");
const phasor_vulkan = @import("phasor-vulkan");
const phasor_common = @import("phasor-common");

// ============================================================================
// Assets
// ============================================================================

pub const Assets = struct {
    sponza: phasor_vulkan.GltfAsset = .{ .path = "examples/sponza/sponza-gltf-pbr/sponza.glb" },
};

// ============================================================================
// Systems
// ============================================================================

fn setup_scene(mut_commands: *phasor_ecs.Commands) !void {
    // Create FPS controller camera
    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Camera3d{
            .Perspective = .{
                .fov = std.math.pi / 3.0,
                .near = 0.1,
                .far = 1000.0,
            },
        },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = 2.0, .z = 10.0 },  // Back to normal scale
        },
        phasor_vulkan.FpsController{
            .move_speed = 5.0,
            .mouse_sensitivity = 0.002,
        },
    });

    // Load and spawn Sponza scene
    const assets_res = mut_commands.getResource(Assets) orelse return error.MissingAssets;
    try assets_res.sponza.spawn(mut_commands, std.heap.page_allocator);

    std.debug.print("Sponza scene loaded successfully!\n", .{});
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

    // Add AssetPlugin for Sponza loading
    var asset_plugin = phasor_vulkan.AssetPlugin(Assets){};
    try app.addPlugin(&asset_plugin);

    // Ensure Startup runs after VkInitEnd so assets are loaded
    try app.scheduleAfter("Startup", "VkInitEnd");

    try app.addSystem("Startup", setup_scene);

    return try app.run();
}
