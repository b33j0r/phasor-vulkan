// Common neutral model structures shared between importer and engine.
// This module defines data-only types without engine/runtime dependencies,
// used to ferry data from importers (e.g., Assimp) to engine conversion.
const std = @import("std");
const phasor_common = @import("phasor-common");

// Reuse shared math/color types from phasor-common
pub const Vec2 = phasor_common.Vec2;
pub const Vec3 = phasor_common.Vec3;
/// Floating-point RGBA color (0..1), same as phasor-vulkan components use
pub const Color = phasor_common.Color.F32;

pub const Transform = struct {
    translation: Vec3 = .{},
    rotation: Vec3 = .{}, // Euler XYZ in radians
    scale: Vec3 = .{ .x = 1, .y = 1, .z = 1 },
};

pub const MeshVertex = extern struct {
    pos: Vec3,
    normal: Vec3,
    uv: Vec2 = .{},
    color: Color = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
};

pub const MeshData = struct {
    vertices: []MeshVertex,
    indices: []u32,
    material_index: ?u32 = null,
};

pub const TextureData = struct {
    // If path is set, it should be used; if embedded_bytes is set and width==0, bytes are compressed (e.g. PNG/JPEG).
    // If width/height > 0, embedded_bytes contains raw RGBA8 pixels.
    path: ?[:0]const u8 = null,
    embedded_bytes: ?[]const u8 = null,
    width: u32 = 0,
    height: u32 = 0,
};

pub const MaterialData = struct {
    name: ?[]const u8 = null,
    base_color: Color = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
    base_color_texture: ?TextureData = null,
};

pub const MeshInstance = struct {
    mesh: MeshData,
    material: MaterialData,
    transform: Transform,
    name: ?[]const u8 = null,
};

pub const ModelData = struct {
    meshes: []MeshInstance,

    pub fn deinit(self: *ModelData, allocator: std.mem.Allocator) void {
        for (self.meshes) |*mi| {
            allocator.free(mi.mesh.vertices);
            allocator.free(mi.mesh.indices);
            if (mi.material.name) |n| allocator.free(n);
            if (mi.name) |n| allocator.free(n);
            if (mi.material.base_color_texture) |tex| {
                if (tex.path) |p| allocator.free(p);
                if (tex.embedded_bytes) |blob| allocator.free(blob);
            }
        }
        allocator.free(self.meshes);
        self.meshes = &[_]MeshInstance{};
    }
};
