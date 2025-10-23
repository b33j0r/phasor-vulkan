const std = @import("std");
const zigimg = @import("zigimg");
const vk = @import("vulkan");
const phasor_ecs = @import("phasor-ecs");
const ResMut = phasor_ecs.ResMut;
const ResOpt = phasor_ecs.ResOpt;
const Commands = phasor_ecs.Commands;
const DeviceResource = @import("device/DevicePlugin.zig").DeviceResource;
const stb_truetype = @import("stb_truetype");

const App = phasor_ecs.App;

pub fn AssetPlugin(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn build(_: *Self, app: *App) !void {
            try app.insertResource(T{});

            // Load assets after Vulkan is initialized
            try app.addSystem("VkInitEnd", Self.load);
            try app.addSystem("VkDeinitBegin", Self.unload);
        }

        pub fn load(r_assets: ResMut(T), r_device: ResOpt(DeviceResource)) !void {
            const assets = r_assets.ptr;
            const dev_res = r_device.ptr orelse return error.MissingDeviceResource;
            const vkd = dev_res.device_proxy orelse return error.MissingDevice;

            const fields = std.meta.fields(T);
            inline for (fields) |field| {
                const field_name = field.name;
                var field_ptr = &@field(assets, field_name);
                try field_ptr.load(vkd, dev_res);
            }
        }

        pub fn unload(r_assets: ResMut(T), r_device: ResOpt(DeviceResource)) !void {
            const assets = r_assets.ptr;
            const dev_res = r_device.ptr orelse return error.MissingDeviceResource;
            const vkd = dev_res.device_proxy orelse return error.MissingDevice;

            const fields = std.meta.fields(T);
            inline for (fields) |field| {
                const field_name = field.name;
                var field_ptr = &@field(assets, field_name);
                try field_ptr.unload(vkd);
            }
        }
    };
}

pub const Texture = struct {
    path: [:0]const u8,
    image: ?vk.Image = null,
    image_view: ?vk.ImageView = null,
    memory: ?vk.DeviceMemory = null,
    sampler: ?vk.Sampler = null,
    width: u32 = 0,
    height: u32 = 0,

    pub fn load(self: *Texture, vkd: anytype, dev_res: *const DeviceResource) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        // Load PNG using zigimg
        var file = try std.fs.cwd().openFile(self.path, .{});
        defer file.close();

        // Allocate a read buffer for zigimg
        const read_buffer = try allocator.alloc(u8, 1024 * 1024); // 1MB buffer
        defer allocator.free(read_buffer);

        var img = try zigimg.Image.fromFile(allocator, file, read_buffer);
        defer img.deinit(allocator);

        self.width = @intCast(img.width);
        self.height = @intCast(img.height);

        // Get pixel data as RGBA8
        const pixel_count = img.width * img.height;
        const rgba_data = try allocator.alloc(u8, pixel_count * 4);
        defer allocator.free(rgba_data);

        // Convert pixels to RGBA8
        var i: usize = 0;
        var pixels = img.iterator();
        while (pixels.next()) |pixel| : (i += 4) {
            // Convert float color to u8
            rgba_data[i] = @intFromFloat(pixel.r * 255.0);
            rgba_data[i + 1] = @intFromFloat(pixel.g * 255.0);
            rgba_data[i + 2] = @intFromFloat(pixel.b * 255.0);
            rgba_data[i + 3] = @intFromFloat(pixel.a * 255.0);
        }

        const image_size: vk.DeviceSize = @intCast(rgba_data.len);

        // Create staging buffer
        const staging_buffer = try vkd.createBuffer(&.{
            .size = image_size,
            .usage = .{ .transfer_src_bit = true },
            .sharing_mode = .exclusive,
        }, null);
        defer vkd.destroyBuffer(staging_buffer, null);

        const mem_reqs = vkd.getBufferMemoryRequirements(staging_buffer);
        const staging_memory = try allocateMemory(vkd, dev_res, mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
        defer vkd.freeMemory(staging_memory, null);

        try vkd.bindBufferMemory(staging_buffer, staging_memory, 0);

        // Copy pixel data to staging buffer
        {
            const data = try vkd.mapMemory(staging_memory, 0, image_size, .{});
            defer vkd.unmapMemory(staging_memory);

            const dst: [*]u8 = @ptrCast(@alignCast(data));
            @memcpy(dst[0..rgba_data.len], rgba_data);
        }

        // Create image
        const image = try vkd.createImage(&.{
            .image_type = .@"2d",
            .format = .r8g8b8a8_srgb,
            .extent = .{
                .width = self.width,
                .height = self.height,
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
        const image_memory = try allocateMemory(vkd, dev_res, img_mem_reqs, .{ .device_local_bit = true });
        errdefer vkd.freeMemory(image_memory, null);

        try vkd.bindImageMemory(image, image_memory, 0);

        // Transition image layout and copy from staging buffer
        try transitionImageLayout(vkd, dev_res, image, .undefined, .transfer_dst_optimal);
        try copyBufferToImage(vkd, dev_res, staging_buffer, image, self.width, self.height);
        try transitionImageLayout(vkd, dev_res, image, .transfer_dst_optimal, .shader_read_only_optimal);

        // Create image view
        const image_view = try vkd.createImageView(&.{
            .image = image,
            .view_type = .@"2d",
            .format = .r8g8b8a8_srgb,
            .components = .{
                .r = .identity,
                .g = .identity,
                .b = .identity,
                .a = .identity,
            },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer vkd.destroyImageView(image_view, null);

        // Create sampler
        const sampler = try vkd.createSampler(&.{
            .mag_filter = .linear,
            .min_filter = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
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

        self.image = image;
        self.image_view = image_view;
        self.memory = image_memory;
        self.sampler = sampler;

        std.log.info("Loaded texture from path: {s} ({}x{})", .{ self.path, self.width, self.height });
    }

    pub fn unload(self: *Texture, vkd: anytype) !void {
        if (self.sampler) |sampler| {
            vkd.destroySampler(sampler, null);
            self.sampler = null;
        }
        if (self.image_view) |view| {
            vkd.destroyImageView(view, null);
            self.image_view = null;
        }
        if (self.image) |image| {
            vkd.destroyImage(image, null);
            self.image = null;
        }
        if (self.memory) |mem| {
            vkd.freeMemory(mem, null);
            self.memory = null;
        }
        std.log.info("Unloaded texture from path: {s}", .{self.path});
    }
};

fn allocateMemory(vkd: anytype, dev_res: *const DeviceResource, requirements: vk.MemoryRequirements, properties: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    const mem_props = dev_res.memory_properties;

    var i: u32 = 0;
    while (i < mem_props.memory_type_count) : (i += 1) {
        if ((requirements.memory_type_bits & (@as(u32, 1) << @intCast(i))) != 0) {
            const type_props = mem_props.memory_types[i].property_flags;

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

fn transitionImageLayout(vkd: anytype, dev_res: *const DeviceResource, image: vk.Image, old_layout: vk.ImageLayout, new_layout: vk.ImageLayout) !void {
    const cmd_pool = try vkd.createCommandPool(&.{
        .queue_family_index = dev_res.graphics_family_index.?,
        .flags = .{ .transient_bit = true },
    }, null);
    defer vkd.destroyCommandPool(cmd_pool, null);

    var cmdbuf: vk.CommandBuffer = undefined;
    try vkd.allocateCommandBuffers(&.{
        .command_pool = cmd_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf));

    try vkd.beginCommandBuffer(cmdbuf, &.{ .flags = .{ .one_time_submit_bit = true } });

    var barrier = vk.ImageMemoryBarrier{
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .src_access_mask = .{},
        .dst_access_mask = .{},
    };

    var src_stage: vk.PipelineStageFlags = undefined;
    var dst_stage: vk.PipelineStageFlags = undefined;

    if (old_layout == .undefined and new_layout == .transfer_dst_optimal) {
        barrier.src_access_mask = .{};
        barrier.dst_access_mask = .{ .transfer_write_bit = true };
        src_stage = .{ .top_of_pipe_bit = true };
        dst_stage = .{ .transfer_bit = true };
    } else if (old_layout == .transfer_dst_optimal and new_layout == .shader_read_only_optimal) {
        barrier.src_access_mask = .{ .transfer_write_bit = true };
        barrier.dst_access_mask = .{ .shader_read_bit = true };
        src_stage = .{ .transfer_bit = true };
        dst_stage = .{ .fragment_shader_bit = true };
    } else {
        return error.UnsupportedLayoutTransition;
    }

    vkd.cmdPipelineBarrier(cmdbuf, src_stage, dst_stage, .{}, 0, undefined, 0, undefined, 1, @ptrCast(&barrier));

    try vkd.endCommandBuffer(cmdbuf);

    const submit = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmdbuf),
        .p_wait_dst_stage_mask = undefined,
    };

    const gfx_q = dev_res.graphics_queue.?;
    try vkd.queueSubmit(gfx_q, 1, @ptrCast(&submit), .null_handle);
    try vkd.queueWaitIdle(gfx_q);
}

fn copyBufferToImage(vkd: anytype, dev_res: *const DeviceResource, buffer: vk.Buffer, image: vk.Image, width: u32, height: u32) !void {
    const cmd_pool = try vkd.createCommandPool(&.{
        .queue_family_index = dev_res.graphics_family_index.?,
        .flags = .{ .transient_bit = true },
    }, null);
    defer vkd.destroyCommandPool(cmd_pool, null);

    var cmdbuf: vk.CommandBuffer = undefined;
    try vkd.allocateCommandBuffers(&.{
        .command_pool = cmd_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf));

    try vkd.beginCommandBuffer(cmdbuf, &.{ .flags = .{ .one_time_submit_bit = true } });

    const region = vk.BufferImageCopy{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_extent = .{ .width = width, .height = height, .depth = 1 },
    };

    vkd.cmdCopyBufferToImage(cmdbuf, buffer, image, .transfer_dst_optimal, 1, @ptrCast(&region));

    try vkd.endCommandBuffer(cmdbuf);

    const submit = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmdbuf),
        .p_wait_dst_stage_mask = undefined,
    };

    const gfx_q = dev_res.graphics_queue.?;
    try vkd.queueSubmit(gfx_q, 1, @ptrCast(&submit), .null_handle);
    try vkd.queueWaitIdle(gfx_q);
}

pub const Font = struct {
    path: [:0]const u8,
    font_height: f32 = 48.0,
    atlas_width: u32 = 512,
    atlas_height: u32 = 512,

    image: ?vk.Image = null,
    image_view: ?vk.ImageView = null,
    memory: ?vk.DeviceMemory = null,
    sampler: ?vk.Sampler = null,

    char_data: []stb_truetype.CharData = &.{},
    first_char: u8 = 32,
    allocator: ?std.mem.Allocator = null,

    pub fn load(self: *Font, vkd: anytype, dev_res: *const DeviceResource) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        // Load font file
        const font_data = try std.fs.cwd().readFileAlloc(allocator, self.path, 10 * 1024 * 1024);
        defer allocator.free(font_data);

        // Create font atlas
        var atlas = try stb_truetype.FontAtlas.init(allocator, font_data, self.font_height, self.atlas_width, self.atlas_height);
        defer atlas.deinit(allocator);

        // Bake ASCII characters
        const char_data = try atlas.bakeASCII(self.first_char, 95); // ASCII 32-126
        self.char_data = char_data;
        self.allocator = std.heap.page_allocator; // Store allocator for cleanup

        // Upload atlas texture to GPU (grayscale R8)
        const image_size: vk.DeviceSize = @intCast(atlas.bitmap.len);

        // Create staging buffer
        const staging_buffer = try vkd.createBuffer(&.{
            .size = image_size,
            .usage = .{ .transfer_src_bit = true },
            .sharing_mode = .exclusive,
        }, null);
        defer vkd.destroyBuffer(staging_buffer, null);

        const mem_reqs = vkd.getBufferMemoryRequirements(staging_buffer);
        const staging_memory = try allocateMemory(vkd, dev_res, mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
        defer vkd.freeMemory(staging_memory, null);

        try vkd.bindBufferMemory(staging_buffer, staging_memory, 0);

        // Copy bitmap to staging buffer
        {
            const data = try vkd.mapMemory(staging_memory, 0, image_size, .{});
            defer vkd.unmapMemory(staging_memory);

            const dst: [*]u8 = @ptrCast(@alignCast(data));
            @memcpy(dst[0..atlas.bitmap.len], atlas.bitmap);
        }

        // Create image
        const image = try vkd.createImage(&.{
            .image_type = .@"2d",
            .format = .r8_unorm,
            .extent = .{
                .width = self.atlas_width,
                .height = self.atlas_height,
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
        const image_memory = try allocateMemory(vkd, dev_res, img_mem_reqs, .{ .device_local_bit = true });
        errdefer vkd.freeMemory(image_memory, null);

        try vkd.bindImageMemory(image, image_memory, 0);

        // Transition and copy
        try transitionImageLayout(vkd, dev_res, image, .undefined, .transfer_dst_optimal);
        try copyBufferToImage(vkd, dev_res, staging_buffer, image, self.atlas_width, self.atlas_height);
        try transitionImageLayout(vkd, dev_res, image, .transfer_dst_optimal, .shader_read_only_optimal);

        // Create image view
        const image_view = try vkd.createImageView(&.{
            .image = image,
            .view_type = .@"2d",
            .format = .r8_unorm,
            .components = .{
                .r = .one,
                .g = .one,
                .b = .one,
                .a = .r,
            },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer vkd.destroyImageView(image_view, null);

        // Create sampler
        const sampler = try vkd.createSampler(&.{
            .mag_filter = .linear,
            .min_filter = .linear,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
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

        self.image = image;
        self.image_view = image_view;
        self.memory = image_memory;
        self.sampler = sampler;

        std.log.info("Loaded font from path: {s} ({}x{} atlas)", .{ self.path, self.atlas_width, self.atlas_height });
    }

    pub fn unload(self: *Font, vkd: anytype) !void {
        if (self.sampler) |sampler| {
            vkd.destroySampler(sampler, null);
            self.sampler = null;
        }
        if (self.image_view) |view| {
            vkd.destroyImageView(view, null);
            self.image_view = null;
        }
        if (self.image) |image| {
            vkd.destroyImage(image, null);
            self.image = null;
        }
        if (self.memory) |mem| {
            vkd.freeMemory(mem, null);
            self.memory = null;
        }
        if (self.char_data.len > 0 and self.allocator != null) {
            self.allocator.?.free(self.char_data);
            self.char_data = &.{};
        }
        std.log.info("Unloaded font from path: {s}", .{self.path});
    }
};
