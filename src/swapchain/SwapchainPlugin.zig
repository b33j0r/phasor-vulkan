const SwapchainPlugin = @This();

pub const SwapchainResource = struct {
    swapchain: ?vk.SwapchainKHR = null,
    format: vk.Format = .undefined,
    extent: vk.Extent2D = .{ .width = 0, .height = 0 },
};

pub fn build(self: *SwapchainPlugin, app: *App) !void {
    _ = self;
    // VulkanPlugin creates precise schedules; we only register systems to them.
    try app.addSystem("VkSwapchainInit", init_system);
    try app.addSystem("VkSwapchainDeinit", deinit_system);
}

fn init_system(commands: *Commands, r_device: ResOpt(DeviceResource), r_bounds: ResOpt(WindowBounds)) !void {
    _ = r_device;
    _ = r_bounds;
    const res: SwapchainResource = .{};
    try commands.insertResource(res);
    std.log.info("Vulkan SwapchainPlugin: initialized (scaffold)", .{});
}

fn deinit_system(r_sc: ResOpt(SwapchainResource)) !void {
    _ = r_sc;
    std.log.info("Vulkan SwapchainPlugin: deinitialized (scaffold)", .{});
}

// ─────────────────────────────────────────────
// Imports
// ─────────────────────────────────────────────
const std = @import("std");
const vk = @import("vulkan");

const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
const Commands = phasor_ecs.Commands;
const ResOpt = phasor_ecs.ResOpt;

const phasor_common = @import("phasor-common");
const WindowBounds = phasor_common.WindowBounds;

const DeviceResource = @import("../device/DevicePlugin.zig").DeviceResource;
