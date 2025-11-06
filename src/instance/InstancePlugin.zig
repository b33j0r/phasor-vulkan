const InstancePlugin = @This();

pub const InstanceResource = struct {
    vkb: ?vk.BaseWrapper = null,
    instance: ?vk.InstanceProxy = null,
    surface: ?vk.SurfaceKHR = null,
    instance_wrapper: ?*vk.InstanceWrapper = null,
    debug_messenger: ?vk.DebugUtilsMessengerEXT = null,
};

enable_validation: bool = false,

pub fn build(self: *InstancePlugin, app: *App) !void {
    _ = self;
    // Insert resource
    const res = InstanceResource{};
    try app.insertResource(res);

    // VulkanPlugin creates precise schedules; we only register systems to them.
    try app.addSystem("VkInstanceInit", init_system);
    try app.addSystem("VkInstanceDeinit", deinit_system);
}

fn init_system(r_window: ResOpt(Window), r_res: ResMut(InstanceResource), r_allocator: Res(Allocator)) !void {
    // Ensure window exists
    const win = r_window.ptr orelse return error.MissingWindowResource;
    const window_handle = win.handle orelse return error.MissingWindowHandle;

    // Load base wrapper using GLFW loader
    var res: *InstanceResource = r_res.ptr;
    const allocator = r_allocator.ptr.allocator;
    res.vkb = vk.BaseWrapper.load(glfwGetInstanceProcAddress);

    // Build extension list: GLFW required + debug utils + macOS portability
    var ext_count: u32 = 0;
    const ext_ptr = glfw.glfwGetRequiredInstanceExtensions(&ext_count) orelse return error.MissingVulkanExtensions;

    const extra_count: u32 = 3;
    const total: usize = @intCast(ext_count + extra_count);
    var ext_list = try allocator.alloc([*:0]const u8, total);
    defer allocator.free(ext_list);

    // Copy GLFW required extensions
    var i: usize = 0;
    while (i < ext_count) : (i += 1) ext_list[i] = ext_ptr[i];

    // Additional extensions for debug/macOS portability
    ext_list[i] = vk.extensions.ext_debug_utils.name;
    i += 1;
    ext_list[i] = vk.extensions.khr_portability_enumeration.name;
    i += 1;
    ext_list[i] = vk.extensions.khr_get_physical_device_properties_2.name;
    i += 1;

    // Create instance via vulkan-zig wrapper
    const app_name: [*:0]const u8 = "Phasor Vulkan";
    const instance_handle = try res.vkb.?.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = app_name,
            .application_version = @bitCast(vk.makeApiVersion(0, 0, 1, 0)),
            .p_engine_name = app_name,
            .engine_version = @bitCast(vk.makeApiVersion(0, 0, 1, 0)),
            .api_version = @bitCast(vk.API_VERSION_1_3),
        },
        .enabled_extension_count = @intCast(total),
        .pp_enabled_extension_names = ext_list.ptr,
        .flags = .{ .enumerate_portability_bit_khr = true },
    }, null);

    // Load instance wrapper and proxy
    const vki = try allocator.create(vk.InstanceWrapper);
    vki.* = vk.InstanceWrapper.load(instance_handle, res.vkb.?.dispatch.vkGetInstanceProcAddr.?);
    res.instance_wrapper = vki;
    res.instance = vk.InstanceProxy.init(instance_handle, vki);

    // Create surface via GLFW using instance handle
    var surface: vk.SurfaceKHR = undefined;
    if (glfwCreateWindowSurface(res.instance.?.handle, window_handle, null, &surface) != .success) {
        // cleanup
        res.instance.?.destroyInstance(null);
        allocator.destroy(vki);
        return error.VulkanCreateSurfaceFailed;
    }
    res.surface = surface;

    std.log.info("Vulkan InstancePlugin: instance+surface created via vulkan-zig", .{});
}

fn deinit_system(r_inst: ResOpt(InstanceResource), r_allocator: Res(Allocator)) !void {
    if (r_inst.ptr) |res| {
        if (res.instance) |inst| {
            if (res.surface) |surf| inst.destroySurfaceKHR(surf, null);
            inst.destroyInstance(null);
        }
        if (res.instance_wrapper) |vki| r_allocator.ptr.allocator.destroy(vki);
        // BaseWrapper contains no heap allocations; no action needed.
    }
    std.log.info("Vulkan InstancePlugin: deinitialized", .{});
}

// ─────────────────────────────────────────────
// Imports
// ─────────────────────────────────────────────
const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw").c;

extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *glfw.GLFWwindow, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;

const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
const Commands = phasor_ecs.Commands;
const ResOpt = phasor_ecs.ResOpt;
const ResMut = phasor_ecs.ResMut;
const Res = phasor_ecs.Res;

const phasor_glfw = @import("phasor-glfw");
const Window = phasor_glfw.WindowPlugin.Window;

const Allocator = @import("../AllocatorPlugin.zig").Allocator;
