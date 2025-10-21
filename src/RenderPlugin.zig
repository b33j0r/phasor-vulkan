const RenderPlugin = @This();

// Minimal Vulkan render plugin scaffold
// Goal: establish lifecycle schedules and resources to prepare for Vulkan init, swapchain, and clearing to blue.

// Settings (placeholder for future options)
pub const RenderSettings = struct {
    enable_validation: bool = false,
};

// Resources for sharing between systems
pub const VulkanHandles = struct {
    // Instance/device/swapchain handles will be filled in later steps
    instance: ?vk.Instance = null,
    surface: ?vk.SurfaceKHR = null,
    physical_device: ?vk.PhysicalDevice = null,
    device: ?vk.Device = null,
    graphics_queue: ?vk.Queue = null,
    present_queue: ?vk.Queue = null,

    swapchain: ?vk.SwapchainKHR = null,
    swapchain_format: vk.Format = .undefined,
    swapchain_extent: vk.Extent2D = .{ .width = 0, .height = 0 },

    // Synchronization and command data (to be filled in upcoming steps)
};

settings: RenderSettings = .{},

pub fn init(settings: RenderSettings) RenderPlugin {
    return .{ .settings = settings };
}

pub fn build(self: *RenderPlugin, app: *App) !void {
    _ = self;

    // Insert render-specific schedules around the existing lifecycle
    _ = try app.addScheduleBetween("RenderInit", "WindowInit", "Startup");
    _ = try app.addScheduleBetween("RenderDeinit", "Shutdown", "PostShutdown");
    _ = try app.addScheduleBetween("RenderUpdate", "Update", "LateUpdate");

    try app.addSystem("RenderInit", render_init_system);
    try app.addSystem("RenderUpdate", render_update_system);
    try app.addSystem("RenderDeinit", render_deinit_system);
}

fn render_init_system(commands: *Commands, r_window: ResOpt(Window), r_bounds: ResOpt(WindowBounds)) !void {
    _ = r_bounds;
    // Ensure window exists
    const win = r_window.ptr orelse return error.MissingWindowResource;
    if (win.handle == null) return error.MissingWindowHandle;

    // For now, only insert empty VulkanHandles resource; Vulkan initialization is added next iteration
    var vk_handles: VulkanHandles = .{};
    try commands.insertResource(vk_handles);

    std.log.info("RenderPlugin: initialized (scaffold)", .{});
}

fn render_update_system(_: *Commands, _: ResOpt(Window), _: ResOpt(VulkanHandles), _: ResOpt(RenderBounds)) !void {
    // Placeholder: will clear to blue in subsequent step
    // Keep polling/render cadence aligned with window
    // No-op for now
}

fn render_deinit_system(r_vk: ResOpt(VulkanHandles)) !void {
    _ = r_vk;
    // Placeholder: destroy Vulkan resources in reverse order in subsequent step
    std.log.info("RenderPlugin: deinitialized (scaffold)", .{});
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
const RenderBounds = phasor_common.RenderBounds;
const WindowBounds = phasor_common.WindowBounds;

const phasor_glfw = @import("phasor-glfw");
const Window = phasor_glfw.WindowPlugin.Window;
