const VulkanPlugin = @This();

pub const Settings = struct {
    enable_validation: bool = false,
};

settings: Settings = .{},

// Sub-plugins live as fields to keep a stable address
instance_plugin: InstancePlugin = .{},
device_plugin: DevicePlugin = .{},
swapchain_plugin: SwapchainPlugin = .{},
render_plugin: RenderPlugin = .{},

pub fn init(settings: Settings) VulkanPlugin {
    return .{ .settings = settings };
}

pub fn build(self: *VulkanPlugin, app: *App) !void {
    // Create precise schedules before sub-plugins register systems
    _ = try app.addSchedule("VkInitBegin");
    _ = try app.addSchedule("VkInstanceInit");
    _ = try app.addSchedule("VkDeviceInit");
    _ = try app.addSchedule("VkSwapchainInit");
    _ = try app.addSchedule("VkRenderInit");
    _ = try app.addSchedule("VkInitEnd");

    _ = try app.addSchedule("VkSwapchainUpdate");
    _ = try app.addSchedule("VkRenderUpdate");
    _ = try app.addSchedule("VkUpdate");
    _ = try app.addSchedule("VkRender");

    _ = try app.addSchedule("VkDeinitBegin");
    _ = try app.addSchedule("VkRenderDeinit");
    _ = try app.addSchedule("VkSwapchainDeinit");
    _ = try app.addSchedule("VkDeviceDeinit");
    _ = try app.addSchedule("VkInstanceDeinit");
    _ = try app.addSchedule("VkDeinitEnd");

    // Set up the graph for VkInitBegin -> VkInstanceInit -> VkDeviceInit -> VkSwapchainInit -> VkRenderInit -> VkInitEnd
    _ = try app.scheduleBetween("VkInitBegin", "PreStartup", "VkInstanceInit");
    _ = try app.scheduleBetween("VkInstanceInit", "VkInitBegin", "VkDeviceInit");
    _ = try app.scheduleBetween("VkDeviceInit", "VkInstanceInit", "VkSwapchainInit");
    _ = try app.scheduleBetween("VkSwapchainInit", "VkDeviceInit", "VkRenderInit");
    _ = try app.scheduleBetween("VkRenderInit", "VkSwapchainInit", "VkInitEnd");

    // Set up the graph for VkDeinitBegin -> VkRenderDeinit -> VkSwapchainDeinit -> VkDeviceDeinit -> VkInstanceDeinit -> VkDeinitEnd
    _ = try app.scheduleBetween("VkDeinitBegin", "PostShutdown", "VkRenderDeinit");
    _ = try app.scheduleBetween("VkRenderDeinit", "VkDeinitBegin", "VkSwapchainDeinit");
    _ = try app.scheduleBetween("VkSwapchainDeinit", "VkRenderDeinit", "VkDeviceDeinit");
    _ = try app.scheduleBetween("VkDeviceDeinit", "VkSwapchainDeinit", "VkInstanceDeinit");
    _ = try app.scheduleBetween("VkInstanceDeinit", "VkDeviceDeinit", "VkDeinitEnd");

    // Schedule VkSwapchainUpdate -> VkRenderUpdate -> VkUpdate between Update and Render
    _ = try app.scheduleBetween("VkSwapchainUpdate", "Update", "VkRenderUpdate");
    _ = try app.scheduleBetween("VkRenderUpdate", "VkSwapchainUpdate", "VkUpdate");
    _ = try app.scheduleBetween("VkUpdate", "VkRenderUpdate", "Render");

    // Schedule VkRender between Render and EndFrame
    _ = try app.scheduleBetween("VkRender", "Render", "EndFrame");

    // Pass settings to sub-plugins where relevant
    self.instance_plugin = .{ .enable_validation = self.settings.enable_validation };
    self.device_plugin = .{};
    self.swapchain_plugin = .{};
    self.render_plugin = .{};

    // Register sub-plugins (they will only add systems to the above schedules)
    try app.addPlugin(&self.instance_plugin);
    try app.addPlugin(&self.device_plugin);
    try app.addPlugin(&self.swapchain_plugin);
    try app.addPlugin(&self.render_plugin);
}

// ─────────────────────────────────────────────
// Imports
// ─────────────────────────────────────────────
const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;

const InstancePlugin = @import("instance/InstancePlugin.zig");
const DevicePlugin = @import("device/DevicePlugin.zig");
const SwapchainPlugin = @import("swapchain/SwapchainPlugin.zig");
const RenderPlugin = @import("render/RenderPlugin.zig");
