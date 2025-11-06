const std = @import("std");
const stb_image = @import("stb_image");
const vk = @import("vulkan");
const DeviceResource = @import("device/DevicePlugin.zig").DeviceResource;
const RenderResource = @import("render/RenderPlugin.zig").RenderResource;
const stb_truetype = @import("stb_truetype");
const ShaderPipeline = @import("render/ShaderPipeline.zig");
const texture_utils = @import("texture_utils.zig");

// Re-export AssetPlugin
pub const AssetPlugin = @import("assets_plugin.zig").AssetPlugin;

pub const Texture = struct {
    path: [:0]const u8,
    image: ?vk.Image = null,
    image_view: ?vk.ImageView = null,
    memory: ?vk.DeviceMemory = null,
    sampler: ?vk.Sampler = null,
    width: u32 = 0,
    height: u32 = 0,

    pub fn load(self: *Texture, vkd: anytype, dev_res: *const DeviceResource, _: *const RenderResource, allocator: std.mem.Allocator) !void {
        // Load image using stb_image
        var width: c_int = undefined;
        var height: c_int = undefined;
        var channels: c_int = undefined;

        // Load image as RGBA (4 channels)
        const data_ptr = stb_image.c.stbi_load(
            self.path.ptr,
            &width,
            &height,
            &channels,
            4, // Force RGBA
        );

        if (data_ptr == null) {
            return error.ImageLoadFailed;
        }
        defer stb_image.c.stbi_image_free(data_ptr);

        self.width = @intCast(width);
        self.height = @intCast(height);

        // Copy pixel data to Zig-managed memory
        const pixel_count: usize = @intCast(width * height);
        const rgba_data = try allocator.alloc(u8, pixel_count * 4);
        defer allocator.free(rgba_data);

        const src_data: [*]const u8 = @ptrCast(data_ptr);
        @memcpy(rgba_data, src_data[0 .. pixel_count * 4]);

        // Create staging buffer and upload data
        const staging = try texture_utils.createStagingBuffer(vkd, dev_res, rgba_data);
        defer texture_utils.destroyStagingBuffer(vkd, staging);

        // Create image and image view
        const img_resources = try texture_utils.createTextureImage(vkd, dev_res, self.width, self.height, .rgba8_srgb);
        errdefer texture_utils.destroyImageResources(vkd, img_resources);

        // Upload from staging buffer to image
        try texture_utils.uploadTextureFromStaging(vkd, dev_res, staging.buffer, img_resources.image, self.width, self.height);

        // Create sampler
        const sampler = try texture_utils.createTextureSampler(vkd, .repeat);

        self.image = img_resources.image;
        self.image_view = img_resources.image_view;
        self.memory = img_resources.memory;
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

        // Create staging buffer and upload atlas bitmap
        const staging = try texture_utils.createStagingBuffer(vkd, dev_res, atlas.bitmap);
        defer texture_utils.destroyStagingBuffer(vkd, staging);

        // Create image and image view (grayscale R8)
        const img_resources = try texture_utils.createTextureImage(vkd, dev_res, self.atlas_width, self.atlas_height, .r8_unorm);
        errdefer texture_utils.destroyImageResources(vkd, img_resources);

        // Upload from staging buffer to image
        try texture_utils.uploadTextureFromStaging(vkd, dev_res, staging.buffer, img_resources.image, self.atlas_width, self.atlas_height);

        // Create sampler with clamp_to_edge for font atlases
        const sampler = try texture_utils.createTextureSampler(vkd, .clamp_to_edge);

        self.image = img_resources.image;
        self.image_view = img_resources.image_view;
        self.memory = img_resources.memory;
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

/// Model asset for GLTF/GLB models
pub const Model = struct {
    path: [:0]const u8,

    // Loaded data (owned by this struct)
    // Exposed as public fields for backward compatibility
    mesh_data: []@import("import/Assimp.zig").MeshData = &.{},
    textures: []Texture = &.{},
    texture_paths: [][:0]const u8 = &.{},

    pub fn load(self: *Model, vkd: anytype, dev_res: *const DeviceResource, render_res: *const RenderResource, allocator: std.mem.Allocator) !void {
        const Assimp = @import("import/Assimp.zig");

        // Use Assimp.zig to load model with textures
        const loaded = try Assimp.loadGltfWithTextures(allocator, vkd, dev_res, render_res, self.path);

        // Store in public fields for backward compatibility
        self.mesh_data = loaded.meshes;
        self.textures = loaded.textures;
        self.texture_paths = loaded.texture_paths;

        std.log.info("Loaded model from path: {s} ({d} meshes, {d} textures)", .{ self.path, self.mesh_data.len, self.textures.len });
    }

    pub fn unload(self: *Model, vkd: anytype, allocator: std.mem.Allocator) !void {
        // Unload textures
        for (self.textures) |*tex| {
            if (tex.sampler) |sampler| vkd.destroySampler(sampler, null);
            if (tex.image_view) |view| vkd.destroyImageView(view, null);
            if (tex.image) |image| vkd.destroyImage(image, null);
            if (tex.memory) |mem| vkd.freeMemory(mem, null);
        }
        if (self.textures.len > 0) {
            allocator.free(self.textures);
            self.textures = &.{};
        }

        // Free texture paths
        for (self.texture_paths) |path| {
            allocator.free(path);
        }
        if (self.texture_paths.len > 0) {
            allocator.free(self.texture_paths);
            self.texture_paths = &.{};
        }

        // Free mesh data
        for (self.mesh_data) |*m| {
            allocator.free(@constCast(m.mesh.vertices));
            allocator.free(@constCast(m.mesh.indices));
            if (m.name) |n| allocator.free(n);
        }
        if (self.mesh_data.len > 0) {
            allocator.free(self.mesh_data);
            self.mesh_data = &.{};
        }

        std.log.info("Unloaded model from path: {s}", .{self.path});
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
        const pipeline = try ShaderPipeline.createMeshPipeline(vkd, pipeline_layout, render_res.color_format, render_res.depth_format, render_res.swapchain_extent, self.vert_spv, self.frag_spv);
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
