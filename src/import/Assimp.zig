const std = @import("std");
const phasor_assimp = @import("phasor-assimp");
const common = @import("phasor-vulkan-common");
const components = @import("../components.zig");

pub const MeshData = struct {
    mesh: components.Mesh,
    material: components.Material,
    transform: components.Transform3d,
    name: ?[]const u8 = null,
};

pub const Model = struct {
    meshes: []MeshData,

    pub fn deinit(self: *Model, allocator: std.mem.Allocator) void {
        for (self.meshes) |*m| {
            // Free owned vertex/index memory
            allocator.free(@constCast(m.mesh.vertices));
            allocator.free(@constCast(m.mesh.indices));
            if (m.name) |n| allocator.free(n);
        }
        allocator.free(self.meshes);
        self.meshes = &[_]MeshData{};
    }
};

pub fn loadGlb(allocator: std.mem.Allocator, path: [:0]const u8) !Model {
    var data = try phasor_assimp.loadGlbData(allocator, path);
    defer data.deinit(allocator);
    return try convertToEngine(allocator, data);
}

pub fn loadGltf(allocator: std.mem.Allocator, path: [:0]const u8) !Model {
    var data = try phasor_assimp.loadGltfData(allocator, path);
    defer data.deinit(allocator);
    return try convertToEngine(allocator, data);
}

fn convertToEngine(allocator: std.mem.Allocator, data: common.ModelData) !Model {
    var out: std.ArrayList(MeshData) = .{};
    defer out.deinit(allocator);

    for (data.meshes) |mi| {
        // Convert vertices
        const vlen = mi.mesh.vertices.len;
        var verts = try allocator.alloc(components.MeshVertex, vlen);
        errdefer allocator.free(verts);
        var i: usize = 0;
        while (i < vlen) : (i += 1) {
            const v = mi.mesh.vertices[i];
            verts[i] = .{
                .pos = v.pos,
                .normal = v.normal,
                .uv = v.uv,
                .color = v.color,
            };
        }

        // Convert indices
        const ilen = mi.mesh.indices.len;
        const inds = try allocator.alloc(u32, ilen);
        errdefer allocator.free(inds);
        @memcpy(inds, mi.mesh.indices);

        // Material mapping (texture not handled yet)
        const mat: components.Material = .{
            .color = mi.material.base_color,
            .texture = null, // TODO: integrate with AssetPlugin and Texture loading
        };

        // Transform mapping
        const t: components.Transform3d = .{
            .translation = mi.transform.translation,
            .rotation = mi.transform.rotation,
            .scale = mi.transform.scale,
        };

        const name = if (mi.name) |n| try allocator.dupe(u8, n) else null;

        try out.append(allocator, .{
            .mesh = .{ .vertices = verts, .indices = inds },
            .material = mat,
            .transform = t,
            .name = name,
        });
    }

    return .{ .meshes = try out.toOwnedSlice(allocator) };
}
