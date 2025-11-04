const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_glfw = @import("phasor-glfw");
const phasor_vulkan = @import("phasor-vulkan");

fn setup_triangle(mut_commands: *phasor_ecs.Commands) !void {
    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Triangle{
            .vertices = [3]phasor_vulkan.Vertex{
                .{ .pos = .{ 0.0, -0.5 }, .color = .{ 1.0, 0.0, 0.0 } }, // Top vertex (red)
                .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0.0, 1.0, 0.0 } },  // Bottom-right (green)
                .{ .pos = .{ -0.5, 0.5 }, .color = .{ 0.0, 0.0, 1.0 } }, // Bottom-left (blue)
            },
        },
    });
}

pub fn main() !u8 {
    const allocator = std.heap.c_allocator;
    var app = try phasor_ecs.App.default(allocator);
    defer app.deinit();

    const allocator_plugin = phasor_vulkan.AllocatorPlugin{ .allocator = allocator };
    try app.addPlugin(&allocator_plugin);

    const window_plugin = phasor_glfw.WindowPlugin.init(.{
        .title = "Phasor ECS Triangle Example",
        .width = 800,
        .height = 600,
    });
    try app.addPlugin(&window_plugin);

    const vk_plugin = phasor_vulkan.VulkanPlugin.init(.{});
    try app.addPlugin(&vk_plugin);

    // Add system to setup the triangle
    try app.addSystem("Startup", setup_triangle);

    return try app.run();
}
