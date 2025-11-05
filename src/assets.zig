const std = @import("std");
const zigimg = @import("zigimg");
const vk = @import("vulkan");
const phasor_ecs = @import("phasor-ecs");
const ResMut = phasor_ecs.ResMut;
const ResOpt = phasor_ecs.ResOpt;
const Commands = phasor_ecs.Commands;
const DeviceResource = @import("device/DevicePlugin.zig").DeviceResource;
const RenderResource = @import("render/RenderPlugin.zig").RenderResource;
const stb_truetype = @import("stb_truetype");
const utils = @import("render/utils.zig");
const ShaderPipeline = @import("render/ShaderPipeline.zig");

const App = phasor_ecs.App;
const Res = phasor_ecs.Res;

const Allocator = @import("AllocatorPlugin.zig").Allocator;

pub fn AssetPlugin(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn build(_: *Self, app: *App) !void {
            try app.insertResource(T{});

            // Load assets after Vulkan is initialized
            try app.addSystem("VkInitEnd", Self.load);
            try app.addSystem("VkDeinitBegin", Self.unload);
        }

        pub fn load(r_assets: ResMut(T), r_device: ResOpt(DeviceResource), r_render: ResOpt(RenderResource), r_allocator: Res(Allocator)) !void {
            const assets = r_assets.ptr;
            const dev_res = r_device.ptr orelse return error.MissingDeviceResource;
            const render_res = r_render.ptr orelse return error.MissingRenderResource;
            const vkd = dev_res.device_proxy orelse return error.MissingDevice;
            const allocator = r_allocator.ptr.allocator;

            const fields = std.meta.fields(T);
            inline for (fields) |field| {
                const field_name = field.name;
                var field_ptr = &@field(assets, field_name);
                try field_ptr.load(vkd, dev_res, render_res, allocator);
            }
        }

        pub fn unload(r_assets: ResMut(T), r_device: ResOpt(DeviceResource), r_allocator: Res(Allocator)) !void {
            const assets = r_assets.ptr;
            const dev_res = r_device.ptr orelse return error.MissingDeviceResource;
            const vkd = dev_res.device_proxy orelse return error.MissingDevice;
            const allocator = r_allocator.ptr.allocator;

            const fields = std.meta.fields(T);
            inline for (fields) |field| {
                const field_name = field.name;
                var field_ptr = &@field(assets, field_name);
                try field_ptr.unload(vkd, allocator);
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

    pub fn load(self: *Texture, vkd: anytype, dev_res: *const DeviceResource, _: *const RenderResource, allocator: std.mem.Allocator) !void {
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
        const staging_memory = try utils.allocateMemory(vkd, dev_res, mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
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
        const image_memory = try utils.allocateMemory(vkd, dev_res, img_mem_reqs, .{ .device_local_bit = true });
        errdefer vkd.freeMemory(image_memory, null);

        try vkd.bindImageMemory(image, image_memory, 0);

        // Transition image layout and copy from staging buffer
        try utils.transitionImageLayout(vkd, dev_res, image, .undefined, .transfer_dst_optimal);
        try utils.copyBufferToImage(vkd, dev_res, staging_buffer, image, self.width, self.height);
        try utils.transitionImageLayout(vkd, dev_res, image, .transfer_dst_optimal, .shader_read_only_optimal);

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

    pub fn unload(self: *Texture, vkd: anytype, _: std.mem.Allocator) !void {
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

    pub fn load(self: *Font, vkd: anytype, dev_res: *const DeviceResource, _: *const RenderResource, allocator: std.mem.Allocator) !void {
        // Load font file
        const font_data = try std.fs.cwd().readFileAlloc(allocator, self.path, 10 * 1024 * 1024);
        defer allocator.free(font_data);

        // Create font atlas
        var atlas = try stb_truetype.FontAtlas.init(allocator, font_data, self.font_height, self.atlas_width, self.atlas_height);
        defer atlas.deinit(allocator);

        // Bake ASCII characters
        const char_data = try atlas.bakeASCII(self.first_char, 95, allocator); // ASCII 32-126
        self.char_data = char_data;

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
        const staging_memory = try utils.allocateMemory(vkd, dev_res, mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
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
        const image_memory = try utils.allocateMemory(vkd, dev_res, img_mem_reqs, .{ .device_local_bit = true });
        errdefer vkd.freeMemory(image_memory, null);

        try vkd.bindImageMemory(image, image_memory, 0);

        // Transition and copy
        try utils.transitionImageLayout(vkd, dev_res, image, .undefined, .transfer_dst_optimal);
        try utils.copyBufferToImage(vkd, dev_res, staging_buffer, image, self.atlas_width, self.atlas_height);
        try utils.transitionImageLayout(vkd, dev_res, image, .transfer_dst_optimal, .shader_read_only_optimal);

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

    pub fn unload(self: *Font, vkd: anytype, allocator: std.mem.Allocator) !void {
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
        if (self.char_data.len > 0) {
            allocator.free(self.char_data);
            self.char_data = &.{};
        }
        std.log.info("Unloaded font from path: {s}", .{self.path});
    }
};

/// Shader asset for custom shaders
pub const Shader = struct {
    vert_spv: []const u8,
    frag_spv: []const u8,

    // Vulkan resources (created during load)
    pipeline_layout: ?vk.PipelineLayout = null,
    pipeline: ?vk.Pipeline = null,

    pub fn load(self: *Shader, vkd: anytype, _: *const DeviceResource, render_res: *const RenderResource, _: std.mem.Allocator) !void {
        // Create push constant range for MVP matrix
        const push_constant_range = vk.PushConstantRange{
            .stage_flags = .{ .vertex_bit = true },
            .offset = 0,
            .size = @sizeOf([16]f32),
        };

        // Create pipeline layout (no descriptor sets for vertex color shaders)
        const pipeline_layout = try vkd.createPipelineLayout(&.{
            .flags = .{},
            .set_layout_count = 0,
            .p_set_layouts = undefined,
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast(&push_constant_range),
        }, null);
        errdefer vkd.destroyPipelineLayout(pipeline_layout, null);

        // Create pipeline using the provided shader SPIR-V
        const pipeline = try ShaderPipeline.createMeshPipeline(vkd, pipeline_layout, render_res.render_pass, render_res.swapchain_extent, self.vert_spv, self.frag_spv);
        errdefer vkd.destroyPipeline(pipeline, null);

        self.pipeline_layout = pipeline_layout;
        self.pipeline = pipeline;

        std.log.info("Loaded custom shader", .{});
    }

    pub fn unload(self: *Shader, vkd: anytype, _: std.mem.Allocator) !void {
        if (self.pipeline) |pipeline| {
            vkd.destroyPipeline(pipeline, null);
            self.pipeline = null;
        }
        if (self.pipeline_layout) |layout| {
            vkd.destroyPipelineLayout(layout, null);
            self.pipeline_layout = null;
        }
        std.log.info("Unloaded custom shader", .{});
    }
};
