// GLTF data structures for scene loading
const std = @import("std");
const components = @import("../components.zig");
const assets = @import("../assets.zig");
const phasor_common = @import("phasor-common");

/// Represents a loaded GLTF scene with hierarchy
pub const GltfScene = struct {
    name: ?[]const u8 = null,
    nodes: []GltfNode,
    meshes: []GltfMesh,
    materials: []GltfMaterial,
    textures: []?*const assets.Texture,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *GltfScene) void {
        // Free node names
        for (self.nodes) |*node| {
            if (node.name) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(node.children);
        }
        self.allocator.free(self.nodes);

        // Free mesh data
        for (self.meshes) |*mesh| {
            if (mesh.name) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(mesh.vertices);
            self.allocator.free(mesh.indices);
        }
        self.allocator.free(self.meshes);

        // Free materials
        self.allocator.free(self.materials);

        // Free textures array (textures themselves are managed by asset system)
        self.allocator.free(self.textures);

        // Free scene name
        if (self.name) |name| {
            self.allocator.free(name);
        }
    }
};

/// Single node in the GLTF hierarchy
pub const GltfNode = struct {
    name: ?[]const u8 = null,
    transform: components.Transform3d = .{},
    mesh_index: ?u32 = null,
    material_index: ?u32 = null,
    children: []u32 = &.{},
    parent: ?u32 = null,
};

/// GLTF mesh with vertex/index data
pub const GltfMesh = struct {
    vertices: []const components.MeshVertex,
    indices: []const u32,
    name: ?[]const u8 = null,
};

/// Material properties from GLTF
pub const GltfMaterial = struct {
    base_color: components.Color4 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    base_color_texture: ?u32 = null, // index into textures array
    metallic: f32 = 1.0,
    roughness: f32 = 1.0,
    normal_texture: ?u32 = null,
};
