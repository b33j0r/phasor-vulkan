const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_glfw = @import("phasor-glfw");
const phasor_vulkan = @import("phasor-vulkan");
const phasor_common = @import("phasor-common");

// ============================================================================
// Assets Definition
// ============================================================================

const GameAssets = struct {
    floor_texture: phasor_vulkan.Texture = .{
        .path = "examples/warehouse/assets/kenney_prototype-textures/PNG/Light/texture_01.png",
    },
    wall_texture: phasor_vulkan.Texture = .{
        .path = "examples/warehouse/assets/kenney_prototype-textures/PNG/Light/texture_07.png",
    },
    crate_texture: phasor_vulkan.Texture = .{
        .path = "examples/warehouse/assets/kenney_prototype-textures/PNG/Orange/texture_01.png",
    },
    platform_texture: phasor_vulkan.Texture = .{
        .path = "examples/warehouse/assets/kenney_prototype-textures/PNG/Dark/texture_01.png",
    },
    red_texture: phasor_vulkan.Texture = .{
        .path = "examples/warehouse/assets/kenney_prototype-textures/PNG/Red/texture_01.png",
    },
    green_texture: phasor_vulkan.Texture = .{
        .path = "examples/warehouse/assets/kenney_prototype-textures/PNG/Green/texture_01.png",
    },
    purple_texture: phasor_vulkan.Texture = .{
        .path = "examples/warehouse/assets/kenney_prototype-textures/PNG/Purple/texture_01.png",
    },
};

// ============================================================================
// Mesh Creation Helpers
// ============================================================================

fn createFloorMesh(allocator: std.mem.Allocator, width: f32, depth: f32) !phasor_vulkan.Mesh {
    // Create a checkerboard floor with 2x2 meter tiles
    const tile_size: f32 = 2.0;
    const tiles_x = @as(usize, @intFromFloat(width / tile_size));
    const tiles_z = @as(usize, @intFromFloat(depth / tile_size));

    const vertex_count = (tiles_x + 1) * (tiles_z + 1);
    const vertices = try allocator.alloc(phasor_vulkan.MeshVertex, vertex_count);

    const half_w = width / 2.0;
    const half_d = depth / 2.0;

    // Generate vertices
    var idx: usize = 0;
    var z: usize = 0;
    while (z <= tiles_z) : (z += 1) {
        var x: usize = 0;
        while (x <= tiles_x) : (x += 1) {
            const px = -half_w + @as(f32, @floatFromInt(x)) * tile_size;
            const pz = -half_d + @as(f32, @floatFromInt(z)) * tile_size;

            // UV coordinates for tiling
            const u = @as(f32, @floatFromInt(x));
            const v = @as(f32, @floatFromInt(z));

            vertices[idx] = .{
                .pos = .{ .x = px, .y = 0.0, .z = pz },
                .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
                .uv = .{ .x = u, .y = v },
                .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
            };
            idx += 1;
        }
    }

    // Generate indices for triangles
    const indices = try allocator.alloc(u32, tiles_x * tiles_z * 6);
    idx = 0;
    z = 0;
    while (z < tiles_z) : (z += 1) {
        var x: usize = 0;
        while (x < tiles_x) : (x += 1) {
            const v0 = @as(u32, @intCast(z * (tiles_x + 1) + x));
            const v1 = v0 + 1;
            const v2 = v0 + @as(u32, @intCast(tiles_x + 1));
            const v3 = v2 + 1;

            // Triangle 1 (reversed winding for upward-facing)
            indices[idx] = v0;
            indices[idx + 1] = v2;
            indices[idx + 2] = v1;
            // Triangle 2 (reversed winding for upward-facing)
            indices[idx + 3] = v2;
            indices[idx + 4] = v3;
            indices[idx + 5] = v1;
            idx += 6;
        }
    }

    return phasor_vulkan.Mesh{ .vertices = vertices, .indices = indices };
}

fn createWallMesh(allocator: std.mem.Allocator, width: f32, height: f32) !phasor_vulkan.Mesh {
    const vertices = try allocator.alloc(phasor_vulkan.MeshVertex, 4);
    const half_w = width / 2.0;
    const half_h = height / 2.0;

    const u_scale = width / 2.0;
    const v_scale = height / 2.0;

    // Wall vertices (facing +Z direction)
    vertices[0] = .{ .pos = .{ .x = -half_w, .y = -half_h, .z = 0.0 }, .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .uv = .{ .x = 0.0, .y = v_scale }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[1] = .{ .pos = .{ .x = half_w, .y = -half_h, .z = 0.0 }, .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .uv = .{ .x = u_scale, .y = v_scale }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[2] = .{ .pos = .{ .x = half_w, .y = half_h, .z = 0.0 }, .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .uv = .{ .x = u_scale, .y = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 } };
    vertices[3] = .{ .pos = .{ .x = -half_w, .y = half_h, .z = 0.0 }, .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 } };

    const indices = try allocator.alloc(u32, 6);
    indices[0] = 0;
    indices[1] = 1;
    indices[2] = 2;
    indices[3] = 2;
    indices[4] = 3;
    indices[5] = 0;

    return phasor_vulkan.Mesh{ .vertices = vertices, .indices = indices };
}

fn createBoxMesh(allocator: std.mem.Allocator, width: f32, height: f32, depth: f32) !phasor_vulkan.Mesh {
    const vertices = try allocator.alloc(phasor_vulkan.MeshVertex, 24);
    const half_w = width / 2.0;
    const half_h = height / 2.0;
    const half_d = depth / 2.0;

    const color = phasor_vulkan.Color4{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };

    // Front face (+Z)
    vertices[0] = .{ .pos = .{ .x = -half_w, .y = -half_h, .z = half_d }, .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color };
    vertices[1] = .{ .pos = .{ .x = half_w, .y = -half_h, .z = half_d }, .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color };
    vertices[2] = .{ .pos = .{ .x = half_w, .y = half_h, .z = half_d }, .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color };
    vertices[3] = .{ .pos = .{ .x = -half_w, .y = half_h, .z = half_d }, .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };

    // Back face (-Z)
    vertices[4] = .{ .pos = .{ .x = half_w, .y = -half_h, .z = -half_d }, .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color };
    vertices[5] = .{ .pos = .{ .x = -half_w, .y = -half_h, .z = -half_d }, .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color };
    vertices[6] = .{ .pos = .{ .x = -half_w, .y = half_h, .z = -half_d }, .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color };
    vertices[7] = .{ .pos = .{ .x = half_w, .y = half_h, .z = -half_d }, .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };

    // Top face (+Y)
    vertices[8] = .{ .pos = .{ .x = -half_w, .y = half_h, .z = half_d }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };
    vertices[9] = .{ .pos = .{ .x = half_w, .y = half_h, .z = half_d }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color };
    vertices[10] = .{ .pos = .{ .x = half_w, .y = half_h, .z = -half_d }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color };
    vertices[11] = .{ .pos = .{ .x = -half_w, .y = half_h, .z = -half_d }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color };

    // Bottom face (-Y)
    vertices[12] = .{ .pos = .{ .x = -half_w, .y = -half_h, .z = -half_d }, .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color };
    vertices[13] = .{ .pos = .{ .x = half_w, .y = -half_h, .z = -half_d }, .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color };
    vertices[14] = .{ .pos = .{ .x = half_w, .y = -half_h, .z = half_d }, .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color };
    vertices[15] = .{ .pos = .{ .x = -half_w, .y = -half_h, .z = half_d }, .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };

    // Right face (+X)
    vertices[16] = .{ .pos = .{ .x = half_w, .y = -half_h, .z = half_d }, .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color };
    vertices[17] = .{ .pos = .{ .x = half_w, .y = -half_h, .z = -half_d }, .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color };
    vertices[18] = .{ .pos = .{ .x = half_w, .y = half_h, .z = -half_d }, .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color };
    vertices[19] = .{ .pos = .{ .x = half_w, .y = half_h, .z = half_d }, .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };

    // Left face (-X)
    vertices[20] = .{ .pos = .{ .x = -half_w, .y = -half_h, .z = -half_d }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color };
    vertices[21] = .{ .pos = .{ .x = -half_w, .y = -half_h, .z = half_d }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color };
    vertices[22] = .{ .pos = .{ .x = -half_w, .y = half_h, .z = half_d }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color };
    vertices[23] = .{ .pos = .{ .x = -half_w, .y = half_h, .z = -half_d }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };

    const indices = try allocator.alloc(u32, 36);
    const faces = [6][6]u32{
        .{ 0, 1, 2, 2, 3, 0 }, // Front
        .{ 4, 5, 6, 6, 7, 4 }, // Back
        .{ 8, 9, 10, 10, 11, 8 }, // Top
        .{ 12, 13, 14, 14, 15, 12 }, // Bottom
        .{ 16, 17, 18, 18, 19, 16 }, // Right
        .{ 20, 21, 22, 22, 23, 20 }, // Left
    };

    var idx: usize = 0;
    for (faces) |face| {
        for (face) |i| {
            indices[idx] = i;
            idx += 1;
        }
    }

    return phasor_vulkan.Mesh{ .vertices = vertices, .indices = indices };
}

fn createIsosphereMesh(allocator: std.mem.Allocator, radius: f32, subdivisions: u32) !phasor_vulkan.Mesh {
    // Create an icosphere by starting with an icosahedron and subdividing
    const t = (1.0 + @sqrt(5.0)) / 2.0; // Golden ratio

    // Initial 12 vertices of icosahedron
    const initial_vertices = [12]phasor_vulkan.MeshVertex{
        .{ .pos = .{ .x = -1, .y = t, .z = 0 }, .normal = .{ .x = 0, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } },
        .{ .pos = .{ .x = 1, .y = t, .z = 0 }, .normal = .{ .x = 0, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } },
        .{ .pos = .{ .x = -1, .y = -t, .z = 0 }, .normal = .{ .x = 0, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } },
        .{ .pos = .{ .x = 1, .y = -t, .z = 0 }, .normal = .{ .x = 0, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } },
        .{ .pos = .{ .x = 0, .y = -1, .z = t }, .normal = .{ .x = 0, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } },
        .{ .pos = .{ .x = 0, .y = 1, .z = t }, .normal = .{ .x = 0, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } },
        .{ .pos = .{ .x = 0, .y = -1, .z = -t }, .normal = .{ .x = 0, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } },
        .{ .pos = .{ .x = 0, .y = 1, .z = -t }, .normal = .{ .x = 0, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } },
        .{ .pos = .{ .x = t, .y = 0, .z = -1 }, .normal = .{ .x = 0, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } },
        .{ .pos = .{ .x = t, .y = 0, .z = 1 }, .normal = .{ .x = 0, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } },
        .{ .pos = .{ .x = -t, .y = 0, .z = -1 }, .normal = .{ .x = 0, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } },
        .{ .pos = .{ .x = -t, .y = 0, .z = 1 }, .normal = .{ .x = 0, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } },
    };

    // Initial 20 faces of icosahedron
    const initial_indices = [60]u32{
        0, 11, 5, 0, 5,  1,  0,  1,  7,  0,  7, 10, 0, 10, 11,
        1, 5,  9, 5, 11, 4,  11, 10, 2,  10, 7, 6,  7, 1,  8,
        3, 9,  4, 3, 4,  2,  3,  2,  6,  3,  6, 8,  3, 8,  9,
        4, 9,  5, 2, 4,  11, 6,  2,  10, 8,  6, 7,  9, 8,  1,
    };

    var vertices: std.ArrayList(phasor_vulkan.MeshVertex) = .{};
    defer vertices.deinit(allocator);
    try vertices.appendSlice(allocator, &initial_vertices);

    var indices: std.ArrayList(u32) = .{};
    defer indices.deinit(allocator);
    try indices.appendSlice(allocator, &initial_indices);

    // Subdivision is simplified for now - just normalize and scale
    // A full implementation would subdivide triangles
    _ = subdivisions; // TODO: implement subdivision

    // Normalize all vertices and apply radius
    for (vertices.items) |*v| {
        const len = @sqrt(v.pos.x * v.pos.x + v.pos.y * v.pos.y + v.pos.z * v.pos.z);
        v.pos.x = (v.pos.x / len) * radius;
        v.pos.y = (v.pos.y / len) * radius;
        v.pos.z = (v.pos.z / len) * radius;

        // Normal is the same as normalized position for a sphere
        v.normal.x = v.pos.x / radius;
        v.normal.y = v.pos.y / radius;
        v.normal.z = v.pos.z / radius;

        // Simple spherical UV mapping
        const theta = std.math.atan2(v.pos.z, v.pos.x);
        const phi = std.math.asin(v.pos.y / radius);
        v.uv.x = 0.5 + theta / (2.0 * std.math.pi);
        v.uv.y = 0.5 - phi / std.math.pi;
    }

    const final_vertices = try allocator.alloc(phasor_vulkan.MeshVertex, vertices.items.len);
    @memcpy(final_vertices, vertices.items);

    const final_indices = try allocator.alloc(u32, indices.items.len);
    @memcpy(final_indices, indices.items);

    return phasor_vulkan.Mesh{ .vertices = final_vertices, .indices = final_indices };
}

fn createCylinderMesh(allocator: std.mem.Allocator, radius: f32, height: f32, segments: u32) !phasor_vulkan.Mesh {
    const vertex_count = (segments + 1) * 2 + 2; // sides + top center + bottom center
    const vertices = try allocator.alloc(phasor_vulkan.MeshVertex, vertex_count);

    const half_h = height / 2.0;
    const color = phasor_vulkan.Color4{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };

    var idx: usize = 0;

    // Generate side vertices (two rings)
    var i: u32 = 0;
    while (i <= segments) : (i += 1) {
        const angle = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
        const x = @cos(angle) * radius;
        const z = @sin(angle) * radius;
        const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments));

        // Top ring
        vertices[idx] = .{
            .pos = .{ .x = x, .y = half_h, .z = z },
            .normal = .{ .x = x / radius, .y = 0.0, .z = z / radius },
            .uv = .{ .x = u, .y = 0.0 },
            .color = color,
        };
        idx += 1;

        // Bottom ring
        vertices[idx] = .{
            .pos = .{ .x = x, .y = -half_h, .z = z },
            .normal = .{ .x = x / radius, .y = 0.0, .z = z / radius },
            .uv = .{ .x = u, .y = 1.0 },
            .color = color,
        };
        idx += 1;
    }

    const top_center_idx = idx;
    vertices[idx] = .{
        .pos = .{ .x = 0.0, .y = half_h, .z = 0.0 },
        .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .uv = .{ .x = 0.5, .y = 0.5 },
        .color = color,
    };
    idx += 1;

    const bottom_center_idx = idx;
    vertices[idx] = .{
        .pos = .{ .x = 0.0, .y = -half_h, .z = 0.0 },
        .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 },
        .uv = .{ .x = 0.5, .y = 0.5 },
        .color = color,
    };

    // Generate indices
    const index_count = segments * 12; // 6 per segment for sides, 3 for top, 3 for bottom
    const indices = try allocator.alloc(u32, index_count);

    idx = 0;
    i = 0;
    while (i < segments) : (i += 1) {
        const base = i * 2;
        const next_base = base + 2;

        // Side quad (two triangles) - fixed winding order
        indices[idx] = @intCast(base);
        indices[idx + 1] = @intCast(next_base);
        indices[idx + 2] = @intCast(base + 1);

        indices[idx + 3] = @intCast(next_base);
        indices[idx + 4] = @intCast(next_base + 1);
        indices[idx + 5] = @intCast(base + 1);

        // Top cap - fixed winding order
        indices[idx + 6] = @intCast(top_center_idx);
        indices[idx + 7] = @intCast(next_base);
        indices[idx + 8] = @intCast(base);

        // Bottom cap - fixed winding order
        indices[idx + 9] = @intCast(bottom_center_idx);
        indices[idx + 10] = @intCast(base + 1);
        indices[idx + 11] = @intCast(next_base + 1);

        idx += 12;
    }

    return phasor_vulkan.Mesh{ .vertices = vertices, .indices = indices };
}

fn createCapsuleMesh(allocator: std.mem.Allocator, radius: f32, height: f32, segments: u32, rings: u32) !phasor_vulkan.Mesh {
    // Capsule = cylinder + two hemisphere caps
    const half_h = height / 2.0;
    const color = phasor_vulkan.Color4{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };

    // Calculate vertex count: cylinder sides + top hemisphere + bottom hemisphere
    const cylinder_vertices = (segments + 1) * 2;
    const hemisphere_vertices = (segments + 1) * (rings + 1) * 2;
    const vertex_count = cylinder_vertices + hemisphere_vertices;

    const vertices = try allocator.alloc(phasor_vulkan.MeshVertex, vertex_count);
    var idx: usize = 0;

    // Cylinder sides
    var i: u32 = 0;
    while (i <= segments) : (i += 1) {
        const angle = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
        const x = @cos(angle) * radius;
        const z = @sin(angle) * radius;
        const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments));

        vertices[idx] = .{
            .pos = .{ .x = x, .y = half_h, .z = z },
            .normal = .{ .x = x / radius, .y = 0.0, .z = z / radius },
            .uv = .{ .x = u, .y = 0.33 },
            .color = color,
        };
        idx += 1;

        vertices[idx] = .{
            .pos = .{ .x = x, .y = -half_h, .z = z },
            .normal = .{ .x = x / radius, .y = 0.0, .z = z / radius },
            .uv = .{ .x = u, .y = 0.67 },
            .color = color,
        };
        idx += 1;
    }

    // Top hemisphere
    var r: u32 = 0;
    while (r <= rings) : (r += 1) {
        const phi = @as(f32, @floatFromInt(r)) * std.math.pi / @as(f32, @floatFromInt(rings * 2));
        const y = @cos(phi) * radius + half_h;
        const ring_radius = @sin(phi) * radius;

        i = 0;
        while (i <= segments) : (i += 1) {
            const theta = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
            const x = @cos(theta) * ring_radius;
            const z = @sin(theta) * ring_radius;

            const nx = @cos(theta) * @sin(phi);
            const ny = @cos(phi);
            const nz = @sin(theta) * @sin(phi);

            vertices[idx] = .{
                .pos = .{ .x = x, .y = y, .z = z },
                .normal = .{ .x = nx, .y = ny, .z = nz },
                .uv = .{ .x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments)), .y = @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(rings * 2)) },
                .color = color,
            };
            idx += 1;
        }
    }

    // Bottom hemisphere
    r = 0;
    while (r <= rings) : (r += 1) {
        const phi = std.math.pi / 2.0 + @as(f32, @floatFromInt(r)) * std.math.pi / @as(f32, @floatFromInt(rings * 2));
        const y = @cos(phi) * radius - half_h;
        const ring_radius = @sin(phi) * radius;

        i = 0;
        while (i <= segments) : (i += 1) {
            const theta = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
            const x = @cos(theta) * ring_radius;
            const z = @sin(theta) * ring_radius;

            const nx = @cos(theta) * @sin(phi);
            const ny = @cos(phi);
            const nz = @sin(theta) * @sin(phi);

            vertices[idx] = .{
                .pos = .{ .x = x, .y = y, .z = z },
                .normal = .{ .x = nx, .y = ny, .z = nz },
                .uv = .{ .x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments)), .y = 0.5 + @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(rings * 2)) },
                .color = color,
            };
            idx += 1;
        }
    }

    // Generate indices
    const cylinder_indices = segments * 6;
    const hemisphere_indices = segments * rings * 6 * 2;
    const index_count = cylinder_indices + hemisphere_indices;
    const indices = try allocator.alloc(u32, index_count);

    idx = 0;

    // Cylinder indices - fixed winding order
    i = 0;
    while (i < segments) : (i += 1) {
        const base = i * 2;
        const next_base = base + 2;

        indices[idx] = @intCast(base);
        indices[idx + 1] = @intCast(next_base);
        indices[idx + 2] = @intCast(base + 1);

        indices[idx + 3] = @intCast(next_base);
        indices[idx + 4] = @intCast(next_base + 1);
        indices[idx + 5] = @intCast(base + 1);

        idx += 6;
    }

    const hemisphere_start = cylinder_vertices;

    // Top hemisphere indices - fixed winding order
    r = 0;
    while (r < rings) : (r += 1) {
        i = 0;
        while (i < segments) : (i += 1) {
            const current = hemisphere_start + r * (segments + 1) + i;
            const next = current + segments + 1;

            indices[idx] = @intCast(current);
            indices[idx + 1] = @intCast(current + 1);
            indices[idx + 2] = @intCast(next);

            indices[idx + 3] = @intCast(current + 1);
            indices[idx + 4] = @intCast(next + 1);
            indices[idx + 5] = @intCast(next);

            idx += 6;
        }
    }

    // Bottom hemisphere indices - fixed winding order
    const bottom_start = hemisphere_start + (segments + 1) * (rings + 1);
    r = 0;
    while (r < rings) : (r += 1) {
        i = 0;
        while (i < segments) : (i += 1) {
            const current = bottom_start + r * (segments + 1) + i;
            const next = current + segments + 1;

            indices[idx] = @intCast(current);
            indices[idx + 1] = @intCast(current + 1);
            indices[idx + 2] = @intCast(next);

            indices[idx + 3] = @intCast(current + 1);
            indices[idx + 4] = @intCast(next + 1);
            indices[idx + 5] = @intCast(next);

            idx += 6;
        }
    }

    return phasor_vulkan.Mesh{ .vertices = vertices, .indices = indices };
}

fn createRampMesh(allocator: std.mem.Allocator, width: f32, height: f32, depth: f32) !phasor_vulkan.Mesh {
    // Create a wedge ramp by modifying a box - move the front bottom edge up to the back top
    const vertices = try allocator.alloc(phasor_vulkan.MeshVertex, 24);
    const half_w = width / 2.0;
    const half_d = depth / 2.0;

    const color = phasor_vulkan.Color4{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };

    // Calculate normal for sloped surface
    const slope_len = @sqrt(depth * depth + height * height);
    const nx: f32 = 0.0;
    const ny: f32 = depth / slope_len;
    const nz: f32 = height / slope_len;

    // Front face (+Z) - this becomes the sloped ramp surface
    // Bottom edge at y=0, top edge at y=height
    vertices[0] = .{ .pos = .{ .x = -half_w, .y = 0.0, .z = half_d }, .normal = .{ .x = nx, .y = ny, .z = nz }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color };
    vertices[1] = .{ .pos = .{ .x = half_w, .y = 0.0, .z = half_d }, .normal = .{ .x = nx, .y = ny, .z = nz }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color };
    vertices[2] = .{ .pos = .{ .x = half_w, .y = height, .z = -half_d }, .normal = .{ .x = nx, .y = ny, .z = nz }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color };
    vertices[3] = .{ .pos = .{ .x = -half_w, .y = height, .z = -half_d }, .normal = .{ .x = nx, .y = ny, .z = nz }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };

    // Back face (-Z) - vertical wall at the high end
    vertices[4] = .{ .pos = .{ .x = half_w, .y = 0.0, .z = -half_d }, .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color };
    vertices[5] = .{ .pos = .{ .x = -half_w, .y = 0.0, .z = -half_d }, .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color };
    vertices[6] = .{ .pos = .{ .x = -half_w, .y = height, .z = -half_d }, .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color };
    vertices[7] = .{ .pos = .{ .x = half_w, .y = height, .z = -half_d }, .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };

    // Top face - this is eliminated in a wedge, vertices unused
    vertices[8] = .{ .pos = .{ .x = -half_w, .y = height, .z = half_d }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };
    vertices[9] = .{ .pos = .{ .x = half_w, .y = height, .z = half_d }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color };
    vertices[10] = .{ .pos = .{ .x = half_w, .y = height, .z = -half_d }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color };
    vertices[11] = .{ .pos = .{ .x = -half_w, .y = height, .z = -half_d }, .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color };

    // Bottom face (-Y)
    vertices[12] = .{ .pos = .{ .x = -half_w, .y = 0.0, .z = -half_d }, .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color };
    vertices[13] = .{ .pos = .{ .x = half_w, .y = 0.0, .z = -half_d }, .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color };
    vertices[14] = .{ .pos = .{ .x = half_w, .y = 0.0, .z = half_d }, .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color };
    vertices[15] = .{ .pos = .{ .x = -half_w, .y = 0.0, .z = half_d }, .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };

    // Right face (+X) - triangular side
    vertices[16] = .{ .pos = .{ .x = half_w, .y = 0.0, .z = half_d }, .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color };
    vertices[17] = .{ .pos = .{ .x = half_w, .y = 0.0, .z = -half_d }, .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color };
    vertices[18] = .{ .pos = .{ .x = half_w, .y = height, .z = -half_d }, .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color };
    vertices[19] = .{ .pos = .{ .x = half_w, .y = height, .z = half_d }, .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };

    // Left face (-X) - triangular side
    vertices[20] = .{ .pos = .{ .x = -half_w, .y = 0.0, .z = -half_d }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color };
    vertices[21] = .{ .pos = .{ .x = -half_w, .y = 0.0, .z = half_d }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color };
    vertices[22] = .{ .pos = .{ .x = -half_w, .y = height, .z = -half_d }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };
    vertices[23] = .{ .pos = .{ .x = -half_w, .y = height, .z = -half_d }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };

    const indices = try allocator.alloc(u32, 24);
    const faces = [_]u32{
        // Sloped surface (front -> ramp)
        0,  1,  2,  2,  3,  0,
        // Back face
        4,  5,  6,  6,  7,  4,
        // Bottom
        12, 13, 14, 14, 15, 12,
        // Right side (triangle)
        16, 17, 18,
        // Left side (triangle)
        20, 21, 22,
    };

    for (faces, 0..) |face_idx, i| {
        indices[i] = face_idx;
    }

    return phasor_vulkan.Mesh{ .vertices = vertices, .indices = indices };
}

// ============================================================================
// Setup System
// ============================================================================

fn setup_scene(mut_commands: *phasor_ecs.Commands) !void {
    const allocator = std.heap.page_allocator;

    // Create FPS camera with perspective projection
    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Camera3d{
            .Perspective = .{
                .fov = std.math.pi / 3.0,
                .near = 0.1,
                .far = 1000.0,
            },
        },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = 3.0, .z = 5.0 },
            .rotation = .{ .x = 0.0, .y = std.math.pi, .z = 0.0 },
        },
        phasor_vulkan.FpsController{
            .mouse_sensitivity = 0.002,
            .move_speed = 5.0,
            .yaw = std.math.pi,
        },
        phasor_vulkan.CapsuleCollider{
            .radius = 0.4,
            .height = 3.6,
        },
        phasor_vulkan.RigidBody{
            .gravity_scale = 1.0,
            .kinematic = false,
        },
    });

    // Arena dimensions
    const arena_width: f32 = 20.0;
    const arena_depth: f32 = 20.0;
    const arena_height: f32 = 5.0;
    const wall_thickness: f32 = 0.5;

    // Get assets
    const assets = mut_commands.getResource(GameAssets) orelse return error.MissingAssets;

    // Create floor
    const floor_mesh = try createFloorMesh(allocator, arena_width, arena_depth);
    _ = try mut_commands.createEntity(.{
        floor_mesh,
        phasor_vulkan.Material{ .texture = &assets.floor_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        },
        phasor_vulkan.BoxCollider{
            .half_extents = .{ .x = arena_width / 2.0, .y = 0.1, .z = arena_depth / 2.0 },
        },
    });

    // Create walls (4 sides)
    const wall_mesh = try createWallMesh(allocator, arena_width, arena_height);

    // North wall (-Z)
    _ = try mut_commands.createEntity(.{
        wall_mesh,
        phasor_vulkan.Material{ .texture = &assets.wall_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = arena_height / 2.0, .z = -arena_depth / 2.0 },
        },
        phasor_vulkan.BoxCollider{
            .half_extents = .{ .x = arena_width / 2.0, .y = arena_height / 2.0, .z = wall_thickness / 2.0 },
        },
    });

    // South wall (+Z)
    _ = try mut_commands.createEntity(.{
        wall_mesh,
        phasor_vulkan.Material{ .texture = &assets.wall_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = arena_height / 2.0, .z = arena_depth / 2.0 },
            .rotation = .{ .x = 0.0, .y = std.math.pi, .z = 0.0 },
        },
        phasor_vulkan.BoxCollider{
            .half_extents = .{ .x = arena_width / 2.0, .y = arena_height / 2.0, .z = wall_thickness / 2.0 },
        },
    });

    // East wall (+X)
    const wall_mesh_ew = try createWallMesh(allocator, arena_depth, arena_height);
    _ = try mut_commands.createEntity(.{
        wall_mesh_ew,
        phasor_vulkan.Material{ .texture = &assets.wall_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = arena_width / 2.0, .y = arena_height / 2.0, .z = 0.0 },
            .rotation = .{ .x = 0.0, .y = std.math.pi / 2.0, .z = 0.0 },
        },
        phasor_vulkan.BoxCollider{
            .half_extents = .{ .x = wall_thickness / 2.0, .y = arena_height / 2.0, .z = arena_depth / 2.0 },
        },
    });

    // West wall (-X)
    _ = try mut_commands.createEntity(.{
        wall_mesh_ew,
        phasor_vulkan.Material{ .texture = &assets.wall_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -arena_width / 2.0, .y = arena_height / 2.0, .z = 0.0 },
            .rotation = .{ .x = 0.0, .y = -std.math.pi / 2.0, .z = 0.0 },
        },
        phasor_vulkan.BoxCollider{
            .half_extents = .{ .x = wall_thickness / 2.0, .y = arena_height / 2.0, .z = arena_depth / 2.0 },
        },
    });

    // Create ramp with stepped collision boxes to approximate slope
    const ramp_mesh = try createRampMesh(allocator, 4.0, 2.0, 4.0);
    _ = try mut_commands.createEntity(.{
        ramp_mesh,
        phasor_vulkan.Material{ .texture = &assets.platform_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -5.0, .y = 0.0, .z = -5.0 },
        },
    });

    // Add invisible collision boxes to create walkable slope
    // Divide the ramp into 8 steps
    const ramp_width: f32 = 4.0;
    const ramp_height: f32 = 2.0;
    const ramp_depth: f32 = 4.0;
    const num_steps: usize = 8;
    const step_depth = ramp_depth / @as(f32, @floatFromInt(num_steps));
    const step_height = ramp_height / @as(f32, @floatFromInt(num_steps));

    var i: usize = 0;
    while (i < num_steps) : (i += 1) {
        const step_y = step_height * @as(f32, @floatFromInt(i)) + step_height / 2.0;
        const step_z = -5.0 + ramp_depth / 2.0 - step_depth * @as(f32, @floatFromInt(i)) - step_depth / 2.0;

        _ = try mut_commands.createEntity(.{
            phasor_vulkan.Transform3d{
                .translation = .{ .x = -5.0, .y = step_y, .z = step_z },
            },
            phasor_vulkan.BoxCollider{
                .half_extents = .{ .x = ramp_width / 2.0, .y = step_height / 2.0, .z = step_depth / 2.0 },
            },
        });
    }

    // Create platform at top of ramp (flush with ramp top)
    const platform_mesh = try createBoxMesh(allocator, 4.0, 0.3, 4.0);
    _ = try mut_commands.createEntity(.{
        platform_mesh,
        phasor_vulkan.Material{ .texture = &assets.platform_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -5.0, .y = 2.0, .z = -9.0 },
        },
        phasor_vulkan.BoxCollider{
            .half_extents = .{ .x = 2.0, .y = 0.15, .z = 2.0 },
        },
    });

    // Create some crates for visual interest
    const crate_mesh = try createBoxMesh(allocator, 1.5, 1.5, 1.5);

    _ = try mut_commands.createEntity(.{
        crate_mesh,
        phasor_vulkan.Material{ .texture = &assets.crate_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 5.0, .y = 0.75, .z = 5.0 },
        },
        phasor_vulkan.BoxCollider{
            .half_extents = .{ .x = 0.75, .y = 0.75, .z = 0.75 },
        },
    });

    _ = try mut_commands.createEntity(.{
        crate_mesh,
        phasor_vulkan.Material{ .texture = &assets.crate_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 7.0, .y = 0.75, .z = 3.0 },
        },
        phasor_vulkan.BoxCollider{
            .half_extents = .{ .x = 0.75, .y = 0.75, .z = 0.75 },
        },
    });

    // Create isosphere primitive (red texture)
    const isosphere_mesh = try createIsosphereMesh(allocator, 1.0, 0);
    _ = try mut_commands.createEntity(.{
        isosphere_mesh,
        phasor_vulkan.Material{ .texture = &assets.red_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -7.0, .y = 1.0, .z = 5.0 },
        },
    });

    // Create cylinder primitive (green texture)
    const cylinder_mesh = try createCylinderMesh(allocator, 0.75, 2.0, 16);
    _ = try mut_commands.createEntity(.{
        cylinder_mesh,
        phasor_vulkan.Material{ .texture = &assets.green_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = 1.0, .z = 7.0 },
        },
    });

    // Create capsule primitive (purple texture)
    const capsule_mesh = try createCapsuleMesh(allocator, 0.5, 1.5, 16, 8);
    _ = try mut_commands.createEntity(.{
        capsule_mesh,
        phasor_vulkan.Material{ .texture = &assets.purple_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 7.0, .y = 1.5, .z = -5.0 },
        },
    });
}

// ============================================================================
// Main Entry Point
// ============================================================================

pub fn main() !u8 {
    var app = try phasor_ecs.App.default(std.heap.page_allocator);
    defer app.deinit();

    try app.insertResource(phasor_common.ClearColor{ .color = phasor_common.Color.BLACK });

    const window_plugin = phasor_glfw.WindowPlugin.init(.{
        .title = "Warehouse - FPS Demo",
        .width = 1280,
        .height = 720,
    });
    try app.addPlugin(&window_plugin);

    var input_plugin = phasor_glfw.InputPlugin{};
    try app.addPlugin(&input_plugin);

    const vk_plugin = phasor_vulkan.VulkanPlugin.init(.{});
    try app.addPlugin(&vk_plugin);

    var time_plugin = phasor_vulkan.TimePlugin{};
    try app.addPlugin(&time_plugin);

    var asset_plugin = phasor_vulkan.AssetPlugin(GameAssets){};
    try app.addPlugin(&asset_plugin);

    const fps_controller_plugin = phasor_vulkan.FpsControllerPlugin{};
    try app.addPlugin(&fps_controller_plugin);

    const physics_plugin = phasor_vulkan.PhysicsPlugin.init(.{
        .gravity = -9.81,
    });
    try app.addPlugin(&physics_plugin);

    try app.addSystem("Startup", setup_scene);

    return try app.run();
}
