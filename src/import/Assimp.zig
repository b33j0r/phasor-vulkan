const std = @import("std");
const vk = @import("vulkan");
const phasor_assimp = @import("phasor-assimp");
const common = @import("phasor-vulkan-common");
const components = @import("../components.zig");
const DeviceResource = @import("../device/DevicePlugin.zig").DeviceResource;
const RenderResource = @import("../render/RenderPlugin.zig").RenderResource;
const Texture = @import("../assets.zig").Texture;
const stb_image = @import("stb_image");
const texture_utils = @import("../texture_utils.zig");

pub const MeshData = struct {
    mesh: components.Mesh,
    material: components.Material,
    transform: components.Transform3d,
    name: ?[]const u8 = null,
};

pub const LoadedModel = struct {
    meshes: []MeshData,
    textures: []Texture,
    texture_paths: [][:0]const u8,

    pub fn deinit(self: *LoadedModel, allocator: std.mem.Allocator, vkd: anytype) void {
        // Unload textures
        for (self.textures) |*tex| {
            if (tex.sampler) |sampler| vkd.destroySampler(sampler, null);
            if (tex.image_view) |view| vkd.destroyImageView(view, null);
            if (tex.image) |image| vkd.destroyImage(image, null);
            if (tex.memory) |mem| vkd.freeMemory(mem, null);
        }
        if (self.textures.len > 0) allocator.free(self.textures);

        // Free texture paths
        for (self.texture_paths) |path| allocator.free(path);
        if (self.texture_paths.len > 0) allocator.free(self.texture_paths);

        // Free mesh data
        for (self.meshes) |*m| {
            allocator.free(@constCast(m.mesh.vertices));
            allocator.free(@constCast(m.mesh.indices));
            if (m.name) |n| allocator.free(n);
        }
        if (self.meshes.len > 0) allocator.free(self.meshes);
    }
};

pub fn loadGltfWithTextures(
    allocator: std.mem.Allocator,
    vkd: anytype,
    dev_res: *const DeviceResource,
    render_res: *const RenderResource,
    path: [:0]const u8,
) !LoadedModel {
    var data = try phasor_assimp.loadGltfData(allocator, path);
    defer data.deinit(allocator);
    return try convertToEngineWithTextures(allocator, vkd, dev_res, render_res, data, path);
}

pub fn loadGlbWithTextures(
    allocator: std.mem.Allocator,
    vkd: anytype,
    dev_res: *const DeviceResource,
    render_res: *const RenderResource,
    path: [:0]const u8,
) !LoadedModel {
    var data = try phasor_assimp.loadGlbData(allocator, path);
    defer data.deinit(allocator);
    return try convertToEngineWithTextures(allocator, vkd, dev_res, render_res, data, path);
}

fn convertToEngineWithTextures(
    allocator: std.mem.Allocator,
    vkd: anytype,
    dev_res: *const DeviceResource,
    render_res: *const RenderResource,
    data: common.ModelData,
    model_path: [:0]const u8,
) !LoadedModel {
    // Get model directory for resolving texture paths
    const model_dir = std.fs.path.dirname(model_path) orelse ".";

    // Collect unique textures
    var texture_list: std.ArrayList(Texture) = .empty;
    defer texture_list.deinit(allocator);

    var texture_path_list: std.ArrayList([:0]const u8) = .empty;
    defer texture_path_list.deinit(allocator);

    var texture_map = std.StringHashMap(usize).init(allocator);
    defer texture_map.deinit();

    for (data.meshes) |*mi| {
        if (mi.material.base_color_texture) |tex_data| {
            if (tex_data.embedded_bytes) |bytes| {
                // Load embedded texture
                var texture = Texture{
                    .path = "",
                    .width = tex_data.width,
                    .height = tex_data.height,
                };
                try loadTextureFromBytes(&texture, bytes, tex_data.width, tex_data.height, vkd, dev_res, allocator);
                try texture_list.append(allocator, texture);
            } else if (tex_data.path) |path| {
                // External texture - check if already loaded
                if (!texture_map.contains(path)) {
                    const tex_index = texture_list.items.len;
                    const texture_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ model_dir, path });
                    errdefer allocator.free(texture_path);
                    var texture = Texture{ .path = texture_path };
                    try texture.load(vkd, dev_res, render_res, allocator);
                    try texture_list.append(allocator, texture);
                    try texture_path_list.append(allocator, texture_path);
                    try texture_map.put(path, tex_index);
                }
            }
        }
    }

    // Convert meshes
    var mesh_list: std.ArrayList(MeshData) = .empty;
    defer mesh_list.deinit(allocator);

    for (data.meshes) |mi| {
        // Convert vertices
        const verts = try allocator.alloc(components.MeshVertex, mi.mesh.vertices.len);
        errdefer allocator.free(verts);
        for (mi.mesh.vertices, 0..) |v, i| {
            verts[i] = .{
                .pos = v.pos,
                .normal = v.normal,
                .uv = v.uv,
                .color = v.color,
            };
        }

        // Convert indices
        const inds = try allocator.alloc(u32, mi.mesh.indices.len);
        errdefer allocator.free(inds);
        @memcpy(inds, mi.mesh.indices);

        // Find texture for this material
        var texture_ptr: ?*Texture = null;
        if (mi.material.base_color_texture) |tex_data| {
            if (tex_data.path) |path| {
                if (texture_map.get(path)) |tex_idx| {
                    texture_ptr = &texture_list.items[tex_idx];
                }
            } else if (tex_data.embedded_bytes != null) {
                if (texture_list.items.len > 0) {
                    texture_ptr = &texture_list.items[texture_list.items.len - 1];
                }
            }
        }

        const mat = components.Material{
            .color = mi.material.base_color,
            .texture = texture_ptr,
        };

        const transform = components.Transform3d{
            .translation = mi.transform.translation,
            .rotation = mi.transform.rotation,
            .scale = mi.transform.scale,
        };

        const name = if (mi.name) |n| try allocator.dupe(u8, n) else null;

        try mesh_list.append(allocator, .{
            .mesh = .{ .vertices = verts, .indices = inds },
            .material = mat,
            .transform = transform,
            .name = name,
        });
    }

    return .{
        .meshes = try mesh_list.toOwnedSlice(allocator),
        .textures = try texture_list.toOwnedSlice(allocator),
        .texture_paths = try texture_path_list.toOwnedSlice(allocator),
    };
}

fn loadTextureFromBytes(
    texture: *Texture,
    bytes: []const u8,
    width: u32,
    height: u32,
    vkd: anytype,
    dev_res: *const DeviceResource,
    allocator: std.mem.Allocator,
) !void {
    if (width == 0) {
        // Compressed embedded texture - decode using stb_image
        var img_width: c_int = undefined;
        var img_height: c_int = undefined;
        var channels: c_int = undefined;

        const data_ptr = stb_image.c.stbi_load_from_memory(
            bytes.ptr,
            @intCast(bytes.len),
            &img_width,
            &img_height,
            &channels,
            4, // Force RGBA
        );

        if (data_ptr == null) return error.ImageLoadFailed;
        defer stb_image.c.stbi_image_free(data_ptr);

        texture.width = @intCast(img_width);
        texture.height = @intCast(img_height);

        const pixel_count: usize = @intCast(img_width * img_height);
        const rgba_data = try allocator.alloc(u8, pixel_count * 4);
        defer allocator.free(rgba_data);

        const src_data: [*]const u8 = @ptrCast(data_ptr);
        @memcpy(rgba_data, src_data[0 .. pixel_count * 4]);

        try uploadTextureData(texture, rgba_data, vkd, dev_res);
    } else {
        // Raw RGBA8 pixels
        texture.width = width;
        texture.height = height;
        try uploadTextureData(texture, bytes, vkd, dev_res);
    }
}

fn uploadTextureData(texture: *Texture, rgba_data: []const u8, vkd: anytype, dev_res: *const DeviceResource) !void {
    const staging = try texture_utils.createStagingBuffer(vkd, dev_res, rgba_data);
    defer texture_utils.destroyStagingBuffer(vkd, staging);

    const img_resources = try texture_utils.createTextureImage(vkd, dev_res, texture.width, texture.height, .rgba8_srgb);
    errdefer texture_utils.destroyImageResources(vkd, img_resources);

    try texture_utils.uploadTextureFromStaging(vkd, dev_res, staging.buffer, img_resources.image, texture.width, texture.height);

    const sampler = try texture_utils.createTextureSampler(vkd, .repeat);

    texture.image = img_resources.image;
    texture.image_view = img_resources.image_view;
    texture.memory = img_resources.memory;
    texture.sampler = sampler;
}
