const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_glfw = @import("phasor-glfw");
const phasor_vulkan = @import("phasor-vulkan");

pub fn main() !u8 {
    var app = try phasor_ecs.App.default(std.heap.page_allocator);
    defer app.deinit();

    const window_plugin = phasor_glfw.WindowPlugin.init(.{
        .title = "Phasor ECS Triangle Example",
        .width = 800,
        .height = 600,
    });
    try app.addPlugin(&window_plugin);

    const vk_plugin = phasor_vulkan.VulkanPlugin.init(.{});
    try app.addPlugin(&vk_plugin);

    return try app.run();
}
