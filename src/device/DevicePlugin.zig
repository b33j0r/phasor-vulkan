const DevicePlugin = @This();

pub const DeviceResource = struct {
    physical_device: ?vk.PhysicalDevice = null,
    device: ?vk.Device = null,
    graphics_queue: ?vk.Queue = null,
    present_queue: ?vk.Queue = null,
    graphics_family_index: ?u32 = null,
    present_family_index: ?u32 = null,
};

pub fn build(self: *DevicePlugin, app: *App) !void {
    _ = self;
    // VulkanPlugin creates precise schedules; we only register systems to them.
    try app.addSystem("VkDeviceInit", init_system);
    try app.addSystem("VkDeviceDeinit", deinit_system);
}

fn init_system(commands: *Commands, r_instance: ResOpt(InstanceResource)) !void {
    _ = r_instance;
    const res: DeviceResource = .{};
    try commands.insertResource(res);
    std.log.info("Vulkan DevicePlugin: initialized (scaffold)", .{});
}

fn deinit_system(r_dev: ResOpt(DeviceResource)) !void {
    _ = r_dev;
    std.log.info("Vulkan DevicePlugin: deinitialized (scaffold)", .{});
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

const InstanceResource = @import("../instance/InstancePlugin.zig").InstanceResource;
