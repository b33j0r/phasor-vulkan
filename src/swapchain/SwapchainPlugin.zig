const SwapchainPlugin = @This();

pub const SwapchainResource = struct {
    swapchain: ?vk.SwapchainKHR = null,
    surface_format: vk.SurfaceFormatKHR = .{ .format = .undefined, .color_space = .srgb_nonlinear_khr },
    extent: vk.Extent2D = .{ .width = 0, .height = 0 },
    images: []vk.Image = &[_]vk.Image{},
    views: []vk.ImageView = &[_]vk.ImageView{},
    depth_image: ?vk.Image = null,
    depth_image_view: ?vk.ImageView = null,
    depth_image_memory: ?vk.DeviceMemory = null,
};

pub fn build(self: *SwapchainPlugin, app: *App) !void {
    _ = self;
    // VulkanPlugin creates precise schedules; we only register systems to them.
    try app.addSystem("VkSwapchainInit", init_system);
    try app.addSystem("VkSwapchainUpdate", handle_resize_system);
    try app.addSystem("VkSwapchainDeinit", deinit_system);
}

fn init_system(commands: *Commands, r_instance: ResOpt(InstanceResource), r_device: ResOpt(DeviceResource), r_render_bounds: ResOpt(phasor_common.RenderBounds)) !void {
    const inst = r_instance.ptr orelse return error.MissingInstanceResource;
    const instance = inst.instance orelse return error.MissingInstance;
    const surface = inst.surface orelse return error.MissingSurface;
    const dev = r_device.ptr orelse return error.MissingDeviceResource;
    const device = dev.device_proxy orelse return error.MissingDevice;
    const phys = dev.physical_device orelse return error.MissingPhysicalDevice;
    const bounds = r_render_bounds.ptr orelse return error.MissingRenderBounds;

    // Choose surface format (prefer SRGB) and present mode (FIFO for portability)
    var fmt_count: u32 = 0;
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(phys, surface, &fmt_count, null);
    const formats = try std.heap.page_allocator.alloc(vk.SurfaceFormatKHR, fmt_count);
    defer std.heap.page_allocator.free(formats);
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(phys, surface, &fmt_count, formats.ptr);

    var chosen_format: vk.SurfaceFormatKHR = formats[0];
    for (formats) |f| {
        if (f.format == .b8g8r8a8_srgb and f.color_space == .srgb_nonlinear_khr) { chosen_format = f; break; }
    }

    const caps = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(phys, surface);

    var present_mode_count: u32 = 0;
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(phys, surface, &present_mode_count, null);
    const pmodes = try std.heap.page_allocator.alloc(vk.PresentModeKHR, present_mode_count);
    defer std.heap.page_allocator.free(pmodes);
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(phys, surface, &present_mode_count, pmodes.ptr);

    // Always use FIFO for maximum compatibility
    const present_mode: vk.PresentModeKHR = .fifo_khr;

    // Use RenderBounds (physical pixels) for swapchain extent
    const extent = vk.Extent2D{
        .width = @intCast(@max(@min(@as(u32, @intFromFloat(bounds.width)), caps.max_image_extent.width), caps.min_image_extent.width)),
        .height = @intCast(@max(@min(@as(u32, @intFromFloat(bounds.height)), caps.max_image_extent.height), caps.min_image_extent.height)),
    };

    var image_count: u32 = caps.min_image_count + 1;
    if (caps.max_image_count != 0 and image_count > caps.max_image_count) image_count = caps.max_image_count;

    const sc_info = vk.SwapchainCreateInfoKHR{
        .surface = surface,
        .min_image_count = image_count,
        .image_format = chosen_format.format,
        .image_color_space = chosen_format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = undefined,
        .pre_transform = caps.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = present_mode,
        .clipped = .true,
        .old_swapchain = .null_handle,
    };

    const swapchain = try device.createSwapchainKHR(&sc_info, null);

    // Retrieve images
    var sc_image_count: u32 = 0;
    _ = try device.getSwapchainImagesKHR(swapchain, &sc_image_count, null);
    const images = try std.heap.page_allocator.alloc(vk.Image, sc_image_count);
    errdefer std.heap.page_allocator.free(images);
    _ = try device.getSwapchainImagesKHR(swapchain, &sc_image_count, images.ptr);

    // Create image views
    var views = try std.heap.page_allocator.alloc(vk.ImageView, sc_image_count);
    errdefer std.heap.page_allocator.free(views);
    var i: usize = 0;
    errdefer for (views[0..i]) |v| device.destroyImageView(v, null);
    while (i < views.len) : (i += 1) {
        views[i] = try device.createImageView(&.{
            .image = images[i],
            .view_type = .@"2d",
            .format = chosen_format.format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
    }

    // Create depth image
    const depth_format = vk.Format.d32_sfloat;
    const depth_image = try device.createImage(&.{
        .image_type = .@"2d",
        .format = depth_format,
        .extent = .{ .width = extent.width, .height = extent.height, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{ .depth_stencil_attachment_bit = true },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, null);
    errdefer device.destroyImage(depth_image, null);

    // Allocate memory for depth image
    const depth_mem_reqs = device.getImageMemoryRequirements(depth_image);
    const depth_memory = try allocateMemory(device, dev, depth_mem_reqs, .{ .device_local_bit = true });
    errdefer device.freeMemory(depth_memory, null);

    try device.bindImageMemory(depth_image, depth_memory, 0);

    // Create depth image view
    const depth_image_view = try device.createImageView(&.{
        .image = depth_image,
        .view_type = .@"2d",
        .format = depth_format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = .{ .depth_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);
    errdefer device.destroyImageView(depth_image_view, null);

    const res: SwapchainResource = .{
        .swapchain = swapchain,
        .surface_format = chosen_format,
        .extent = extent,
        .images = images,
        .views = views,
        .depth_image = depth_image,
        .depth_image_view = depth_image_view,
        .depth_image_memory = depth_memory,
    };

    try commands.insertResource(res);
    std.log.info("Vulkan SwapchainPlugin: swapchain created ({d} images)", .{views.len});
}

fn handle_resize_system(
    commands: *Commands,
    r_instance: ResOpt(InstanceResource),
    r_device: ResOpt(DeviceResource),
    r_sc: ResOpt(SwapchainResource),
    event_reader: EventReader(phasor_common.WindowResized),
) !void {
    // Check if there's a resize event
    const resize_event = event_reader.tryRecv() orelse return;

    std.log.info("Vulkan SwapchainPlugin: handling window resize to {d}x{d}", .{ resize_event.width, resize_event.height });

    const inst = r_instance.ptr orelse return;
    const instance = inst.instance orelse return;
    const surface = inst.surface orelse return;
    const dev = r_device.ptr orelse return;
    const device = dev.device_proxy orelse return;
    const phys = dev.physical_device orelse return;
    const old_sc = r_sc.ptr orelse return;

    // Wait for device to be idle before recreating swapchain
    try device.deviceWaitIdle();

    // Destroy old image views
    for (old_sc.views) |v| device.destroyImageView(v, null);
    if (old_sc.views.len > 0) std.heap.page_allocator.free(old_sc.views);
    if (old_sc.images.len > 0) std.heap.page_allocator.free(old_sc.images);

    // Get new surface capabilities
    const caps = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(phys, surface);

    const extent = vk.Extent2D{
        .width = @intCast(@max(@min(@as(u32, @intCast(resize_event.width)), caps.max_image_extent.width), caps.min_image_extent.width)),
        .height = @intCast(@max(@min(@as(u32, @intCast(resize_event.height)), caps.max_image_extent.height), caps.min_image_extent.height)),
    };

    var image_count: u32 = caps.min_image_count + 1;
    if (caps.max_image_count != 0 and image_count > caps.max_image_count) image_count = caps.max_image_count;

    // Create new swapchain with old one as reference
    const sc_info = vk.SwapchainCreateInfoKHR{
        .surface = surface,
        .min_image_count = image_count,
        .image_format = old_sc.surface_format.format,
        .image_color_space = old_sc.surface_format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = undefined,
        .pre_transform = caps.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = .fifo_khr,
        .clipped = .true,
        .old_swapchain = old_sc.swapchain.?,
    };

    const new_swapchain = try device.createSwapchainKHR(&sc_info, null);

    // Destroy old swapchain
    device.destroySwapchainKHR(old_sc.swapchain.?, null);

    // Get new images
    var sc_image_count: u32 = 0;
    _ = try device.getSwapchainImagesKHR(new_swapchain, &sc_image_count, null);
    const images = try std.heap.page_allocator.alloc(vk.Image, sc_image_count);
    errdefer std.heap.page_allocator.free(images);
    _ = try device.getSwapchainImagesKHR(new_swapchain, &sc_image_count, images.ptr);

    // Create new image views
    var views = try std.heap.page_allocator.alloc(vk.ImageView, sc_image_count);
    errdefer std.heap.page_allocator.free(views);
    var i: usize = 0;
    errdefer for (views[0..i]) |v| device.destroyImageView(v, null);
    while (i < views.len) : (i += 1) {
        views[i] = try device.createImageView(&.{
            .image = images[i],
            .view_type = .@"2d",
            .format = old_sc.surface_format.format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
    }

    // Destroy old depth resources
    if (old_sc.depth_image_view) |dv| device.destroyImageView(dv, null);
    if (old_sc.depth_image) |di| device.destroyImage(di, null);
    if (old_sc.depth_image_memory) |dm| device.freeMemory(dm, null);

    // Create new depth image
    const depth_format = vk.Format.d32_sfloat;
    const depth_image = try device.createImage(&.{
        .image_type = .@"2d",
        .format = depth_format,
        .extent = .{ .width = extent.width, .height = extent.height, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{ .depth_stencil_attachment_bit = true },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, null);
    errdefer device.destroyImage(depth_image, null);

    const depth_mem_reqs = device.getImageMemoryRequirements(depth_image);
    const depth_memory = try allocateMemory(device, dev, depth_mem_reqs, .{ .device_local_bit = true });
    errdefer device.freeMemory(depth_memory, null);

    try device.bindImageMemory(depth_image, depth_memory, 0);

    const depth_image_view = try device.createImageView(&.{
        .image = depth_image,
        .view_type = .@"2d",
        .format = depth_format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = .{ .depth_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);
    errdefer device.destroyImageView(depth_image_view, null);

    // Update resource with new swapchain data
    try commands.insertResource(SwapchainResource{
        .swapchain = new_swapchain,
        .surface_format = old_sc.surface_format,
        .extent = extent,
        .images = images,
        .views = views,
        .depth_image = depth_image,
        .depth_image_view = depth_image_view,
        .depth_image_memory = depth_memory,
    });

    std.log.info("Vulkan SwapchainPlugin: swapchain recreated ({d} images)", .{views.len});
}

fn deinit_system(r_device: ResOpt(DeviceResource), r_sc: ResOpt(SwapchainResource)) !void {
    if (r_sc.ptr) |sc| {
        if (r_device.ptr) |dev| {
            if (dev.device_proxy) |device| {
                for (sc.views) |v| device.destroyImageView(v, null);
                if (sc.depth_image_view) |dv| device.destroyImageView(dv, null);
                if (sc.depth_image) |di| device.destroyImage(di, null);
                if (sc.depth_image_memory) |dm| device.freeMemory(dm, null);
                if (sc.swapchain) |sc_handle| device.destroySwapchainKHR(sc_handle, null);
            }
        }
        // Free arrays allocated with page allocator
        if (sc.views.len > 0) std.heap.page_allocator.free(sc.views);
        if (sc.images.len > 0) std.heap.page_allocator.free(sc.images);
    }
    std.log.info("Vulkan SwapchainPlugin: deinitialized", .{});
}

fn allocateMemory(vkd: anytype, dev_res: *const DeviceResource, requirements: vk.MemoryRequirements, properties: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    const mem_props = dev_res.memory_properties;

    var i: u32 = 0;
    while (i < mem_props.memory_type_count) : (i += 1) {
        if ((requirements.memory_type_bits & (@as(u32, 1) << @intCast(i))) != 0) {
            const type_props = mem_props.memory_types[i].property_flags;

            // Check if all required properties are present
            const has_host_visible = type_props.host_visible_bit or !properties.host_visible_bit;
            const has_host_coherent = type_props.host_coherent_bit or !properties.host_coherent_bit;
            const has_device_local = type_props.device_local_bit or !properties.device_local_bit;

            if (has_host_visible and has_host_coherent and has_device_local) {
                return try vkd.allocateMemory(&.{
                    .allocation_size = requirements.size,
                    .memory_type_index = i,
                }, null);
            }
        }
    }
    return error.NoSuitableMemoryType;
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
const EventReader = phasor_ecs.EventReader;

const phasor_common = @import("phasor-common");

const DeviceResource = @import("../device/DevicePlugin.zig").DeviceResource;
const InstanceResource = @import("../instance/InstancePlugin.zig").InstanceResource;
