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

            // Triangle 1
            indices[idx] = v0;
            indices[idx + 1] = v1;
            indices[idx + 2] = v2;
            // Triangle 2
            indices[idx + 3] = v2;
            indices[idx + 4] = v1;
            indices[idx + 5] = v3;
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
    vertices[22] = .{ .pos = .{ .x = -half_w, .y = height, .z = half_d }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color };
    vertices[23] = .{ .pos = .{ .x = -half_w, .y = height, .z = -half_d }, .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color };

    const indices = try allocator.alloc(u32, 30);
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
        20, 21, 22, 22, 23, 20,
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
            .translation = .{ .x = 0.0, .y = 1.6, .z = 5.0 },
            .rotation = .{ .x = 0.0, .y = std.math.pi, .z = 0.0 },
        },
        phasor_vulkan.FpsController{
            .mouse_sensitivity = 0.002,
            .move_speed = 5.0,
            .yaw = std.math.pi,
        },
        phasor_vulkan.CapsuleCollider{
            .radius = 0.4,
            .height = 1.8,
        },
        phasor_vulkan.RigidBody{
            .gravity_scale = 0.0, // Floating controller
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
        phasor_vulkan.Transform3d{},
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

    // Create ramp with platform
    const ramp_mesh = try createRampMesh(allocator, 4.0, 2.0, 4.0);
    _ = try mut_commands.createEntity(.{
        ramp_mesh,
        phasor_vulkan.Material{ .texture = &assets.platform_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -5.0, .y = 0.0, .z = -5.0 },
        },
        phasor_vulkan.BoxCollider{
            .half_extents = .{ .x = 2.0, .y = 1.0, .z = 2.0 },
        },
    });

    // Create platform at top of ramp
    const platform_mesh = try createBoxMesh(allocator, 4.0, 0.3, 4.0);
    _ = try mut_commands.createEntity(.{
        platform_mesh,
        phasor_vulkan.Material{ .texture = &assets.platform_texture },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -5.0, .y = 2.15, .z = -7.0 },
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
        .gravity = 0.0, // No gravity for floating FPS
    });
    try app.addPlugin(&physics_plugin);

    try app.addSystem("Startup", setup_scene);

    return try app.run();
}
