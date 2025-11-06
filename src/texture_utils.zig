const std = @import("std");
const vk = @import("vulkan");
const DeviceResource = @import("device/DevicePlugin.zig").DeviceResource;
const utils = @import("render/utils.zig");

pub const AddressMode = enum {
    repeat,
    clamp_to_edge,
};

pub const ImageFormat = enum {
    rgba8_srgb,
    r8_unorm,
};

pub const StagingBuffer = struct {
    buffer: vk.Buffer,
    memory: vk.DeviceMemory,
};

pub const ImageResources = struct {
    image: vk.Image,
    image_view: vk.ImageView,
    memory: vk.DeviceMemory,
};

/// Create a staging buffer and copy data into it
pub fn createStagingBuffer(
    vkd: anytype,
    dev_res: *const DeviceResource,
    data: []const u8,
) !StagingBuffer {
    const image_size: vk.DeviceSize = @intCast(data.len);

    const staging_buffer = try vkd.createBuffer(&.{
        .size = image_size,
        .usage = .{ .transfer_src_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    errdefer vkd.destroyBuffer(staging_buffer, null);

    const mem_reqs = vkd.getBufferMemoryRequirements(staging_buffer);
    const staging_memory = try utils.allocateMemory(vkd, dev_res, mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    errdefer vkd.freeMemory(staging_memory, null);

    try vkd.bindBufferMemory(staging_buffer, staging_memory, 0);

    // Copy data to staging buffer
    {
        const mapped = try vkd.mapMemory(staging_memory, 0, image_size, .{});
        defer vkd.unmapMemory(staging_memory);

        const dst: [*]u8 = @ptrCast(@alignCast(mapped));
        @memcpy(dst[0..data.len], data);
    }

    return .{
        .buffer = staging_buffer,
        .memory = staging_memory,
    };
}

/// Destroy a staging buffer and free its memory
pub fn destroyStagingBuffer(vkd: anytype, staging: StagingBuffer) void {
    vkd.destroyBuffer(staging.buffer, null);
    vkd.freeMemory(staging.memory, null);
}

/// Create a texture image with the specified format and dimensions
pub fn createTextureImage(
    vkd: anytype,
    dev_res: *const DeviceResource,
    width: u32,
    height: u32,
    format: ImageFormat,
) !ImageResources {
    const vk_format: vk.Format = switch (format) {
        .rgba8_srgb => .r8g8b8a8_srgb,
        .r8_unorm => .r8_unorm,
    };

    const image = try vkd.createImage(&.{
        .image_type = .@"2d",
        .format = vk_format,
        .extent = .{
            .width = width,
            .height = height,
            .depth = 1,
        },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{ .transfer_dst_bit = true, .sampled_bit = true },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, null);
    errdefer vkd.destroyImage(image, null);

    const img_mem_reqs = vkd.getImageMemoryRequirements(image);
    const image_memory = try utils.allocateMemory(vkd, dev_res, img_mem_reqs, .{ .device_local_bit = true });
    errdefer vkd.freeMemory(image_memory, null);

    try vkd.bindImageMemory(image, image_memory, 0);

    // Determine swizzle based on format
    const components: vk.ComponentMapping = switch (format) {
        .rgba8_srgb => .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity,
        },
        .r8_unorm => .{
            .r = .one,
            .g = .one,
            .b = .one,
            .a = .r,
        },
    };

    const image_view = try vkd.createImageView(&.{
        .image = image,
        .view_type = .@"2d",
        .format = vk_format,
        .components = components,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);
    errdefer vkd.destroyImageView(image_view, null);

    return .{
        .image = image,
        .image_view = image_view,
        .memory = image_memory,
    };
}

/// Destroy texture image resources
pub fn destroyImageResources(vkd: anytype, resources: ImageResources) void {
    vkd.destroyImageView(resources.image_view, null);
    vkd.destroyImage(resources.image, null);
    vkd.freeMemory(resources.memory, null);
}

/// Create a texture sampler with the specified address mode
pub fn createTextureSampler(vkd: anytype, address_mode: AddressMode) !vk.Sampler {
    const vk_address_mode: vk.SamplerAddressMode = switch (address_mode) {
        .repeat => .repeat,
        .clamp_to_edge => .clamp_to_edge,
    };

    return try vkd.createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,
        .address_mode_u = vk_address_mode,
        .address_mode_v = vk_address_mode,
        .address_mode_w = vk_address_mode,
        .anisotropy_enable = .false,
        .max_anisotropy = 1.0,
        .border_color = .int_opaque_black,
        .unnormalized_coordinates = .false,
        .compare_enable = .false,
        .compare_op = .always,
        .mipmap_mode = .linear,
        .mip_lod_bias = 0.0,
        .min_lod = 0.0,
        .max_lod = 0.0,
    }, null);
}

/// Upload texture data from staging buffer to GPU image
pub fn uploadTextureFromStaging(
    vkd: anytype,
    dev_res: *const DeviceResource,
    staging_buffer: vk.Buffer,
    image: vk.Image,
    width: u32,
    height: u32,
) !void {
    try utils.transitionImageLayout(vkd, dev_res, image, .undefined, .transfer_dst_optimal);
    try utils.copyBufferToImage(vkd, dev_res, staging_buffer, image, width, height);
    try utils.transitionImageLayout(vkd, dev_res, image, .transfer_dst_optimal, .shader_read_only_optimal);
}
