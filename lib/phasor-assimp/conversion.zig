const std = @import("std");
const assimp = @import("assimp");
const common = @import("phasor-model-common");

const c = assimp.c;

pub fn sceneToModelData(allocator: std.mem.Allocator, scene: c.aiScene) !common.ModelData {
    // Collect materials first
    const materials = try collectMaterials(allocator, &scene);
    defer freeMaterials(allocator, materials);

    // Traverse nodes to collect mesh instances with transforms
    var meshes: std.ArrayList(common.MeshInstance) = .{};
    defer meshes.deinit(allocator);

    try traverseNode(allocator, &scene, scene.mRootNode, identityTransform(), materials, &meshes);

    return .{ .meshes = try meshes.toOwnedSlice(allocator) };
}

fn freeMaterials(allocator: std.mem.Allocator, materials: []common.MaterialData) void {
    for (materials) |*mat| {
        if (mat.name) |n| allocator.free(n);
        if (mat.base_color_texture) |tex| {
            if (tex.path) |p| allocator.free(p);
            if (tex.embedded_bytes) |b| allocator.free(b);
        }
    }
    allocator.free(materials);
}

fn identityTransform() common.Transform {
    return .{ .translation = .{}, .rotation = .{}, .scale = .{ .x = 1, .y = 1, .z = 1 } };
}

fn traverseNode(
    allocator: std.mem.Allocator,
    scene: *const c.aiScene,
    node: *const c.aiNode,
    parent_xform: common.Transform,
    materials: []const common.MaterialData,
    out_meshes: *std.ArrayList(common.MeshInstance),
) !void {
    const local = aiMatrixToTransform(node.mTransformation);
    const world = combineTransform(parent_xform, local);

    // For each mesh referenced by this node, create a MeshInstance
    var i: u32 = 0;
    while (i < node.mNumMeshes) : (i += 1) {
        const mesh_index = node.mMeshes[i];
        const mesh_ptr = scene.mMeshes[mesh_index];
        const mesh = try convertMesh(allocator, mesh_ptr);
        errdefer {
            allocator.free(mesh.vertices);
            allocator.free(mesh.indices);
        }

        const mat_index = if (mesh_ptr.*.mMaterialIndex >= 0) @as(u32, @intCast(mesh_ptr.*.mMaterialIndex)) else 0;
        var mat_copy = try dupMaterial(allocator, materials[mat_index]);
        errdefer freeMaterial(allocator, &mat_copy);

        const name = if (node.mName.length > 0) blk: {
            const s = node.mName.data[0..node.mName.length];
            break :blk try allocator.dupe(u8, s);
        } else null;

        try out_meshes.append(allocator, .{
            .mesh = mesh,
            .material = mat_copy,
            .transform = world,
            .name = name,
        });
    }

    // Recurse children
    var cidx: u32 = 0;
    while (cidx < node.mNumChildren) : (cidx += 1) {
        try traverseNode(allocator, scene, node.mChildren[cidx], world, materials, out_meshes);
    }
}

fn convertMesh(allocator: std.mem.Allocator, mesh: *const c.aiMesh) !common.MeshData {
    // Vertices
    const vcount: usize = mesh.*.mNumVertices;
    var verts = try allocator.alloc(common.MeshVertex, vcount);
    errdefer allocator.free(verts);

    const has_uv = (mesh.*.mTextureCoords[0] != null);
    const has_normals = (mesh.*.mNormals != null);
    const has_colors = (mesh.*.mColors[0] != null);

    var vi: usize = 0;
    while (vi < vcount) : (vi += 1) {
        const pos = mesh.*.mVertices[vi];
        const normal = if (has_normals) mesh.*.mNormals[vi] else c.aiVector3D{ .x = 0, .y = 0, .z = 1 };
        const uv = if (has_uv) mesh.*.mTextureCoords[0][vi] else c.aiVector3D{ .x = 0, .y = 0, .z = 0 };
        const col = if (has_colors) mesh.*.mColors[0][vi] else c.aiColor4D{ .r = 1, .g = 1, .b = 1, .a = 1 };

        verts[vi] = .{
            .pos = .{ .x = pos.x, .y = pos.y, .z = pos.z },
            .normal = .{ .x = normal.x, .y = normal.y, .z = normal.z },
            .uv = .{ .x = uv.x, .y = uv.y },
            .color = .{ .r = col.r, .g = col.g, .b = col.b, .a = col.a },
        };
    }

    // Indices
    var idx_list: std.ArrayList(u32) = .{};
    defer idx_list.deinit(allocator);

    var fi: u32 = 0;
    while (fi < mesh.*.mNumFaces) : (fi += 1) {
        const face = mesh.*.mFaces[fi];
        var j: u32 = 0;
        while (j < face.mNumIndices) : (j += 1) {
            try idx_list.append(allocator, @intCast(face.mIndices[j]));
        }
    }

    return .{ .vertices = verts, .indices = try idx_list.toOwnedSlice(allocator), .material_index = @intCast(mesh.*.mMaterialIndex) };
}

fn collectMaterials(allocator: std.mem.Allocator, scene: *const c.aiScene) ![]common.MaterialData {
    var out = try allocator.alloc(common.MaterialData, scene.mNumMaterials);
    errdefer allocator.free(out);

    var i: u32 = 0;
    while (i < scene.mNumMaterials) : (i += 1) {
        const aimat = scene.mMaterials[i];

        // Name
        var mat: common.MaterialData = .{};
        // Use aiGetMaterialString to get the material name
        var mat_name: c.aiString = undefined;
        mat_name.length = 0;
        if (c.aiGetMaterialString(aimat, "?mat.name", 0, 0, &mat_name) == c.aiReturn_SUCCESS and mat_name.length > 0) {
            const s = mat_name.data[0..mat_name.length];
            mat.name = try allocator.dupe(u8, s);
        }

        // Base color (diffuse)
        var color = c.aiColor4D{ .r = 1, .g = 1, .b = 1, .a = 1 };
        if (c.aiGetMaterialColor(aimat, "$clr.diffuse", 0, 0, &color) == c.aiReturn_SUCCESS) {
            mat.base_color = .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        }

        // Texture: prefer base color/diffuse
        var tex_path: c.aiString = undefined;
        tex_path.length = 0;
        if (c.aiGetMaterialTexture(aimat, c.aiTextureType_DIFFUSE, 0, &tex_path, null, null, null, null, null, null) == c.aiReturn_SUCCESS) {
            // Duplicate path
            const s = tex_path.data[0..tex_path.length];
            if (s.len > 0) {
                var td: common.TextureData = .{};
                if (s[0] == '*') {
                    // Embedded texture e.g. "*0"
                    const idx = parseEmbeddedIndex(s);
                    if (idx < scene.mNumTextures) {
                        const tex = scene.mTextures[idx];
                        if (tex.*.mHeight == 0) {
                            // Compressed data of length mWidth
                            const len: usize = tex.*.mWidth;
                            const bytes = try allocator.alloc(u8, len);
                            const src: [*]const u8 = @ptrCast(tex.*.pcData);
                            @memcpy(bytes, src[0..len]);
                            td.embedded_bytes = bytes;
                            td.width = 0;
                            td.height = 0;
                        } else {
                            // Raw ARGB8888 pixels (aiTexel has bgra?) Assimp docs say aiTexel is rgba8
                            const pixel_count: usize = @as(usize, tex.*.mWidth) * @as(usize, tex.*.mHeight);
                            const bytes = try allocator.alloc(u8, pixel_count * 4);
                            var p: usize = 0;
                            while (p < pixel_count) : (p += 1) {
                                const t = tex.*.pcData[p];
                                bytes[p * 4 + 0] = t.r;
                                bytes[p * 4 + 1] = t.g;
                                bytes[p * 4 + 2] = t.b;
                                bytes[p * 4 + 3] = t.a;
                            }
                            td.embedded_bytes = bytes;
                            td.width = @intCast(tex.*.mWidth);
                            td.height = @intCast(tex.*.mHeight);
                        }
                    }
                } else {
                    td.path = try allocator.dupeZ(u8, s);
                }
                mat.base_color_texture = td;
            }
        }

        out[i] = mat;
    }

    return out;
}

fn dupMaterial(allocator: std.mem.Allocator, m: common.MaterialData) !common.MaterialData {
    var out = m;
    if (m.name) |n| out.name = try allocator.dupe(u8, n);
    if (m.base_color_texture) |tex| {
        var t: common.TextureData = .{ .width = tex.width, .height = tex.height };
        if (tex.path) |p| t.path = try allocator.dupeZ(u8, p);
        if (tex.embedded_bytes) |b| {
            t.embedded_bytes = try allocator.dupe(u8, b);
        }
        out.base_color_texture = t;
    }
    return out;
}

fn freeMaterial(allocator: std.mem.Allocator, m: *common.MaterialData) void {
    if (m.name) |n| allocator.free(n);
    if (m.base_color_texture) |tex| {
        if (tex.path) |p| allocator.free(p);
        if (tex.embedded_bytes) |b| allocator.free(b);
    }
}

fn parseEmbeddedIndex(s: []const u8) u32 {
    var i: usize = 1;
    var idx: u32 = 0;
    while (i < s.len) : (i += 1) {
        const cch = s[i];
        if (cch < '0' or cch > '9') break;
        idx = idx * 10 + @as(u32, @intCast(cch - '0'));
    }
    return idx;
}

fn aiMatrixToTransform(m: c.aiMatrix4x4) common.Transform {
    // Extract translation
    const t = common.Vec3{ .x = m.a4, .y = m.b4, .z = m.c4 };

    // Extract scale from column vectors
    const sx = @sqrt(m.a1 * m.a1 + m.b1 * m.b1 + m.c1 * m.c1);
    const sy = @sqrt(m.a2 * m.a2 + m.b2 * m.b2 + m.c2 * m.c2);
    const sz = @sqrt(m.a3 * m.a3 + m.b3 * m.b3 + m.c3 * m.c3);

    // Build rotation matrix by removing scale (only compute elements we actually use)
    const r11 = m.a1 / sx; const r12 = m.a2 / sy;
    const r21 = m.b1 / sx; const r22 = m.b2 / sy;
    const r31 = m.c1 / sx; const r32 = m.c2 / sy; const r33 = m.c3 / sz;

    // Convert to Euler XYZ (intrinsic) from rotation matrix
    var rx: f32 = 0; var ry: f32 = 0; var rz: f32 = 0;
    if (r31 < 1) {
        if (r31 > -1) {
            ry = -@as(f32, @floatCast(std.math.asin(r31)));
            rx = @as(f32, @floatCast(std.math.atan2(r32, r33)));
            rz = @as(f32, @floatCast(std.math.atan2(r21, r11)));
        } else {
            // r31 == -1
            ry = std.math.pi / 2.0;
            rx = -@as(f32, @floatCast(std.math.atan2(-r12, r22)));
            rz = 0;
        }
    } else {
        // r31 == 1
        ry = -std.math.pi / 2.0;
        rx = @as(f32, @floatCast(std.math.atan2(-r12, r22)));
        rz = 0;
    }

    return .{ .translation = t, .rotation = .{ .x = rx, .y = ry, .z = rz }, .scale = .{ .x = sx, .y = sy, .z = sz } };
}

fn combineTransform(a: common.Transform, b: common.Transform) common.Transform {
    // Simplified: compose translation + scale + rotation (Euler) approximately.
    // For now, just add translations, add rotations, multiply scales.
    return .{
        .translation = .{ .x = a.translation.x + b.translation.x, .y = a.translation.y + b.translation.y, .z = a.translation.z + b.translation.z },
        .rotation = .{ .x = a.rotation.x + b.rotation.x, .y = a.rotation.y + b.rotation.y, .z = a.rotation.z + b.rotation.z },
        .scale = .{ .x = a.scale.x * b.scale.x, .y = a.scale.y * b.scale.y, .z = a.scale.z * b.scale.z },
    };
}
