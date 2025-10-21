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
};

pub fn build(self: *DevicePlugin, app: *App) !void {
    _ = self;
    // VulkanPlugin creates precise schedules; we only register systems to them.
    try app.addSystem("VkDeviceInit", init_system);
    try app.addSystem("VkDeviceDeinit", deinit_system);
}

fn init_system(commands: *Commands, r_instance: ResOpt(InstanceResource)) !void {
    const inst_res = r_instance.ptr orelse return error.MissingInstanceResource;
    const vki = inst_res.instance_wrapper orelse return error.MissingInstanceWrapper;
    const instance = inst_res.instance orelse return error.MissingInstance;
    const surface = inst_res.surface orelse return error.MissingSurface;

    // Pick a suitable physical device with graphics + present and swapchain support
    const candidate = try pickPhysicalDevice(instance, surface);

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

    const required_device_extensions = [_][*:0]const u8{ vk.extensions.khr_swapchain.name };

    const device_handle = try instance.createDevice(candidate.pdev, &.{
        .queue_create_info_count = qci_count,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
    }, null);

    // Load device wrapper/proxy
    const vkd = try std.heap.page_allocator.create(vk.DeviceWrapper);
    vkd.* = vk.DeviceWrapper.load(device_handle, vki.dispatch.vkGetDeviceProcAddr.?);
    const device_proxy = vk.DeviceProxy.init(device_handle, vkd);

    // Fetch queues
    const graphics_queue = device_proxy.getDeviceQueue(candidate.graphics_family, 0);
    const present_queue = device_proxy.getDeviceQueue(candidate.present_family, 0);

    const res: DeviceResource = .{
        .physical_device = candidate.pdev,
        .device = device_handle,
        .device_wrapper = vkd,
        .device_proxy = device_proxy,
        .graphics_queue = graphics_queue,
        .present_queue = present_queue,
        .graphics_family_index = candidate.graphics_family,
        .present_family_index = candidate.present_family,
    };

    try commands.insertResource(res);
    std.log.info("Vulkan DevicePlugin: created device and queues", .{});
}

const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    graphics_family: u32,
    present_family: u32,
};

fn pickPhysicalDevice(instance: vk.InstanceProxy, surface: vk.SurfaceKHR) !DeviceCandidate {
    const pdevs = try instance.enumeratePhysicalDevicesAlloc(std.heap.page_allocator);
    defer std.heap.page_allocator.free(pdevs);

    for (pdevs) |pdev| {
        if (try isSuitable(instance, pdev, surface)) |alloc| {
            return .{ .pdev = pdev, .graphics_family = alloc.graphics_family, .present_family = alloc.present_family };
        }
    }
    return error.NoSuitableDevice;
}

const QueueAlloc = struct { graphics_family: u32, present_family: u32 };

fn isSuitable(instance: vk.InstanceProxy, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !?QueueAlloc {
    if (!try checkDeviceExtensions(instance, pdev)) return null;
    if (!try checkSurfaceSupport(instance, pdev, surface)) return null;
    if (try findQueueFamilies(instance, pdev, surface)) |qa| return qa;
    return null;
}

fn checkDeviceExtensions(instance: vk.InstanceProxy, pdev: vk.PhysicalDevice) !bool {
    const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, std.heap.page_allocator);
    defer std.heap.page_allocator.free(propsv);
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

fn findQueueFamilies(instance: vk.InstanceProxy, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !?QueueAlloc {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, std.heap.page_allocator);
    defer std.heap.page_allocator.free(families);
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

fn deinit_system(r_dev: ResOpt(DeviceResource)) !void {
    if (r_dev.ptr) |res| {
        if (res.device_proxy) |devp| devp.destroyDevice(null);
        if (res.device_wrapper) |vkd| std.heap.page_allocator.destroy(vkd);
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

const InstanceResource = @import("../instance/InstancePlugin.zig").InstanceResource;
