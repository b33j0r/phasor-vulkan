const DevicePlugin = @This();

pub const DeviceResource = struct {
    physical_device: ?vk.PhysicalDevice = null,
    device: ?vk.Device = null,
    device_wrapper: ?*vk.DeviceWrapper = null,
    device_proxy: ?vk.DeviceProxy = null,
    graphics_queue: ?vk.Queue = null,
    present_queue: ?vk.Queue = null,
    graphics_family_index: ?u32 = null,
    present_family_index: ?u32 = null,
    memory_properties: vk.PhysicalDeviceMemoryProperties = undefined,
};

pub fn build(self: *DevicePlugin, app: *App) !void {
    _ = self;
    // VulkanPlugin creates precise schedules; we only register systems to them.
    try app.addSystem("VkDeviceInit", init_system);
    try app.addSystem("VkDeviceDeinit", deinit_system);
}

fn init_system(commands: *Commands, r_instance: ResOpt(InstanceResource), r_allocator: Res(Allocator)) !void {
    const inst_res = r_instance.ptr orelse return error.MissingInstanceResource;
    const allocator = r_allocator.ptr.allocator;
    const vki = inst_res.instance_wrapper orelse return error.MissingInstanceWrapper;
    const instance = inst_res.instance orelse return error.MissingInstance;
    const surface = inst_res.surface orelse return error.MissingSurface;

    // Pick a suitable physical device with graphics + present and swapchain support
    const candidate = try pickPhysicalDevice(instance, surface, allocator);

    // Create logical device with required queues and swapchain extension
    var qci: [2]vk.DeviceQueueCreateInfo = undefined; // may use 1 or 2 queues
    const priority = [_]f32{1.0};
    var qci_count: u32 = 0;
    qci[0] = .{
        .queue_family_index = candidate.graphics_family,
        .queue_count = 1,
        .p_queue_priorities = &priority,
    };
    qci_count = 1;
    if (candidate.present_family != candidate.graphics_family) {
        qci[1] = .{
            .queue_family_index = candidate.present_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        };
        qci_count = 2;
    }

    // Query Vulkan 1.3 features; enable if supported (but do not require)
    var supported_vk13 = vk.PhysicalDeviceVulkan13Features{};
    // PhysicalDeviceFeatures2 requires the nested `features` field; zero-init so Vulkan fills it in
    var features2 = vk.PhysicalDeviceFeatures2{ .p_next = &supported_vk13, .features = .{} };
    instance.getPhysicalDeviceFeatures2(candidate.pdev, &features2);

    var requested_vk13: vk.PhysicalDeviceVulkan13Features = .{};
    var p_next_any: ?*const anyopaque = null;
    if (supported_vk13.dynamic_rendering == .true or supported_vk13.synchronization_2 == .true) {
        // Request only what is supported
        requested_vk13.dynamic_rendering = supported_vk13.dynamic_rendering;
        requested_vk13.synchronization_2 = supported_vk13.synchronization_2;
        p_next_any = &requested_vk13;
    }

    const required_device_extensions = [_][*:0]const u8{ vk.extensions.khr_swapchain.name };

    const device_handle = try instance.createDevice(candidate.pdev, &.{
        .p_next = p_next_any,
        .queue_create_info_count = qci_count,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
    }, null);

    // Load device wrapper/proxy
    const vkd = try allocator.create(vk.DeviceWrapper);
    vkd.* = vk.DeviceWrapper.load(device_handle, vki.dispatch.vkGetDeviceProcAddr.?);
    const device_proxy = vk.DeviceProxy.init(device_handle, vkd);

    // Fetch queues
    const graphics_queue = device_proxy.getDeviceQueue(candidate.graphics_family, 0);
    const present_queue = device_proxy.getDeviceQueue(candidate.present_family, 0);

    // Get memory properties
    const mem_props = instance.getPhysicalDeviceMemoryProperties(candidate.pdev);

    const res: DeviceResource = .{
        .physical_device = candidate.pdev,
        .device = device_handle,
        .device_wrapper = vkd,
        .device_proxy = device_proxy,
        .graphics_queue = graphics_queue,
        .present_queue = present_queue,
        .graphics_family_index = candidate.graphics_family,
        .present_family_index = candidate.present_family,
        .memory_properties = mem_props,
    };

    try commands.insertResource(res);
    std.log.info("Vulkan DevicePlugin: created device and queues", .{});
}

const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    graphics_family: u32,
    present_family: u32,
};

fn pickPhysicalDevice(instance: vk.InstanceProxy, surface: vk.SurfaceKHR, allocator: std.mem.Allocator) !DeviceCandidate {
    const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(pdevs);

    for (pdevs) |pdev| {
        if (try isSuitable(instance, pdev, surface, allocator)) |alloc| {
            return .{ .pdev = pdev, .graphics_family = alloc.graphics_family, .present_family = alloc.present_family };
        }
    }
    return error.NoSuitableDevice;
}

const QueueAlloc = struct { graphics_family: u32, present_family: u32 };

fn isSuitable(instance: vk.InstanceProxy, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR, allocator: std.mem.Allocator) !?QueueAlloc {
    if (!try checkDeviceExtensions(instance, pdev, allocator)) return null;
    if (!try checkSurfaceSupport(instance, pdev, surface)) return null;
    if (try findQueueFamilies(instance, pdev, surface, allocator)) |qa| return qa;
    return null;
}

fn checkDeviceExtensions(instance: vk.InstanceProxy, pdev: vk.PhysicalDevice, allocator: std.mem.Allocator) !bool {
    const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
    defer allocator.free(propsv);
    const required = [_][*:0]const u8{ vk.extensions.khr_swapchain.name };
    for (required) |ext| {
        var found = false;
        for (propsv) |props| {
            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) { found = true; break; }
        }
        if (!found) return false;
    }
    return true;
}

fn checkSurfaceSupport(instance: vk.InstanceProxy, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !bool {
    var fmt_count: u32 = 0;
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &fmt_count, null);
    var pm_count: u32 = 0;
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &pm_count, null);
    return fmt_count > 0 and pm_count > 0;
}

fn findQueueFamilies(instance: vk.InstanceProxy, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR, allocator: std.mem.Allocator) !?QueueAlloc {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);
    var graphics: ?u32 = null;
    var present: ?u32 = null;
    for (families, 0..) |props, i| {
        const idx: u32 = @intCast(i);
        if (graphics == null and props.queue_flags.graphics_bit) graphics = idx;
        if (present == null and (try instance.getPhysicalDeviceSurfaceSupportKHR(pdev, idx, surface)) == .true) present = idx;
    }
    if (graphics) |g| if (present) |p| return .{ .graphics_family = g, .present_family = p };
    return null;
}

fn deinit_system(r_dev: ResOpt(DeviceResource), r_allocator: Res(Allocator)) !void {
    if (r_dev.ptr) |res| {
        if (res.device_proxy) |devp| devp.destroyDevice(null);
        if (res.device_wrapper) |vkd| r_allocator.ptr.allocator.destroy(vkd);
    }
    std.log.info("Vulkan DevicePlugin: deinitialized", .{});
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
const Res = phasor_ecs.Res;

const InstanceResource = @import("../instance/InstancePlugin.zig").InstanceResource;
const Allocator = @import("../AllocatorPlugin.zig").Allocator;
