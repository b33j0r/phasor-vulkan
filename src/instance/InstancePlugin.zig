const InstancePlugin = @This();

pub const InstanceResource = struct {
    instance: ?vk.Instance = null,
    debug_messenger: ?vk.DebugUtilsMessengerEXT = null,
};

pub const Settings = struct {
    enable_validation: bool = false,
};

enable_validation: bool = false,

pub fn build(self: *InstancePlugin, app: *App) !void {
    _ = self;
    // VulkanPlugin creates precise schedules; we only register systems to them.
    try app.addSystem("VkInstanceInit", init_system);
    try app.addSystem("VkInstanceDeinit", deinit_system);
}

fn init_system(commands: *Commands, r_window: ResOpt(Window)) !void {
    // Ensure window exists
    const win = r_window.ptr orelse return error.MissingWindowResource;
    if (win.handle == null) return error.MissingWindowHandle;

    // For now, only create an empty instance resource; real instance creation comes in follow-up
    const res: InstanceResource = .{};
    try commands.insertResource(res);

    std.log.info("Vulkan InstancePlugin: initialized (scaffold)", .{});
}

fn deinit_system(r_inst: ResOpt(InstanceResource)) !void {
    _ = r_inst;
    std.log.info("Vulkan InstancePlugin: deinitialized (scaffold)", .{});
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

const phasor_glfw = @import("phasor-glfw");
const Window = phasor_glfw.WindowPlugin.Window;
