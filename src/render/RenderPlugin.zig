const RenderPlugin = @This();

pub fn build(self: *RenderPlugin, app: *App) !void {
    _ = self;
    // VulkanPlugin creates precise schedules; we only register systems to them.
    try app.addSystem("VkRenderInit", init_system);
    try app.addSystem("VkRender", render_system);
    try app.addSystem("VkRenderDeinit", deinit_system);
}

fn init_system(_: *Commands, _: ResOpt(DeviceResource), _: ResOpt(SwapchainResource)) !void {
    std.log.info("Vulkan RenderPlugin: initialized (scaffold)", .{});
}

fn render_system(_: *Commands, _: ResOpt(DeviceResource), _: ResOpt(SwapchainResource), _: ResOpt(RenderBounds)) !void {
    // Placeholder: will submit a command buffer to clear to blue once swapchain is implemented.
}

fn deinit_system() !void {}

// ─────────────────────────────────────────────
// Imports
// ─────────────────────────────────────────────
const std = @import("std");

const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
const Commands = phasor_ecs.Commands;
const ResOpt = phasor_ecs.ResOpt;

const phasor_common = @import("phasor-common");
const RenderBounds = phasor_common.RenderBounds;

const DeviceResource = @import("../device/DevicePlugin.zig").DeviceResource;
const SwapchainResource = @import("../swapchain/SwapchainPlugin.zig").SwapchainResource;
