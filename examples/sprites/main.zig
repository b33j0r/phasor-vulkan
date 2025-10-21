const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_glfw = @import("phasor-glfw");
const phasor_vulkan = @import("phasor-vulkan");

// Define our assets resource type
const GameAssets = struct {
    planet_texture: phasor_vulkan.Texture = .{
        .path = "examples/sprites/assets/planet05.png",
    },
};

fn setup_sprite(mut_commands: *phasor_ecs.Commands, r_assets: phasor_ecs.Res(GameAssets)) !void {
    // Create a camera entity with Viewport.Center mode for pixel-perfect rendering
    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Camera3d{
            .Viewport = .{
                .mode = .Center,
            },
        },
    });

    // Create a sprite entity with the loaded texture (following raylib pattern)
    // Using Auto size mode for pixel-perfect sizing
    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Transform3d{
            .translation = .{ 0.0, 0.0, 0.0 },
            .scale = .{ 1.0, 1.0, 1.0 },
        },
        phasor_vulkan.Sprite3D{
            .texture = &r_assets.ptr.planet_texture,
            .size_mode = .Auto, // Sprite will be sized to match texture dimensions
        },
    });
}

pub fn main() !u8 {
    var app = try phasor_ecs.App.default(std.heap.page_allocator);
    defer app.deinit();

    const window_plugin = phasor_glfw.WindowPlugin.init(.{
        .title = "Phasor Vulkan - PNG Texture Loading Demo",
        .width = 800,
        .height = 600,
    });
    try app.addPlugin(&window_plugin);

    const vk_plugin = phasor_vulkan.VulkanPlugin.init(.{});
    try app.addPlugin(&vk_plugin);

    // Add asset plugin - loads PNG textures using zigimg
    var asset_plugin = phasor_vulkan.AssetPlugin(GameAssets){};
    try app.addPlugin(&asset_plugin);

    // Add system to setup the sprite (must run after assets are loaded)
    try app.addSystem("Startup", setup_sprite);

    return try app.run();
}
