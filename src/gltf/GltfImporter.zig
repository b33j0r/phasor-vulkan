// GLTF/GLB file importer with custom parser
const std = @import("std");
const types = @import("types.zig");
const components = @import("../components.zig");
const phasor_common = @import("phasor-common");

const GltfScene = types.GltfScene;
const GltfNode = types.GltfNode;
const GltfMesh = types.GltfMesh;
const GltfMaterial = types.GltfMaterial;

// GLB file format constants
const GLB_MAGIC = 0x46546C67; // "glTF"
const GLB_VERSION = 2;
const GLB_CHUNK_JSON = 0x4E4F534A; // "JSON"
const GLB_CHUNK_BIN = 0x004E4942; // "BIN\0"

const GlbHeader = extern struct {
    magic: u32,
    version: u32,
    length: u32,
};

const GlbChunkHeader = extern struct {
    length: u32,
    type: u32,
};

pub const GltfImporter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GltfImporter {
        return .{
            .allocator = allocator,
        };
    }

    fn getNumber(value: std.json.Value) f64 {
        return switch (value) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            else => 0.0,
        };
    }

    pub fn loadScene(self: *GltfImporter, path: []const u8) !GltfScene {
        // Open GLTF file
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        // Read entire file
        const file_size = try file.getEndPos();
        const file_data = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(file_data);
        _ = try file.readAll(file_data);

        // Check if it's a GLB file
        if (file_data.len >= @sizeOf(GlbHeader)) {
            const header: *const GlbHeader = @ptrCast(@alignCast(file_data.ptr));
            if (header.magic == GLB_MAGIC) {
                return try self.loadGlb(file_data);
            }
        }

        // Otherwise try to parse as GLTF JSON
        return try self.loadGltfJson(file_data, null);
    }

    fn loadGlb(self: *GltfImporter, data: []const u8) !GltfScene {
        if (data.len < @sizeOf(GlbHeader)) return error.InvalidGlbFile;

        const header: *const GlbHeader = @ptrCast(@alignCast(data.ptr));
        if (header.magic != GLB_MAGIC) return error.InvalidGlbMagic;
        if (header.version != GLB_VERSION) return error.UnsupportedGlbVersion;

        var offset: usize = @sizeOf(GlbHeader);

        // Read JSON chunk
        if (offset + @sizeOf(GlbChunkHeader) > data.len) return error.InvalidGlbFile;
        const json_chunk_header: *const GlbChunkHeader = @ptrCast(@alignCast(data.ptr + offset));
        offset += @sizeOf(GlbChunkHeader);

        if (json_chunk_header.type != GLB_CHUNK_JSON) return error.ExpectedJsonChunk;
        if (offset + json_chunk_header.length > data.len) return error.InvalidGlbFile;

        const json_data = data[offset .. offset + json_chunk_header.length];
        offset += json_chunk_header.length;

        // Read BIN chunk (optional)
        var bin_data: ?[]const u8 = null;
        if (offset + @sizeOf(GlbChunkHeader) <= data.len) {
            const bin_chunk_header: *const GlbChunkHeader = @ptrCast(@alignCast(data.ptr + offset));
            offset += @sizeOf(GlbChunkHeader);

            if (bin_chunk_header.type == GLB_CHUNK_BIN) {
                if (offset + bin_chunk_header.length <= data.len) {
                    bin_data = data[offset .. offset + bin_chunk_header.length];
                }
            }
        }

        return try self.loadGltfJson(json_data, bin_data);
    }

    fn loadGltfJson(self: *GltfImporter, json_data: []const u8, bin_data: ?[]const u8) !GltfScene {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidGltfJson;

        // Extract buffers
        var buffers = std.ArrayList([]const u8){};
        defer buffers.deinit(self.allocator);

        if (root.object.get("buffers")) |buffers_value| {
            if (buffers_value == .array) {
                for (buffers_value.array.items) |_| {
                    // For GLB files, the first buffer is the BIN chunk
                    if (bin_data) |bin| {
                        try buffers.append(self.allocator, bin);
                    }
                }
            }
        }

        // Extract buffer views
        var buffer_views = std.ArrayList(BufferView){};
        defer buffer_views.deinit(self.allocator);

        if (root.object.get("bufferViews")) |views_value| {
            if (views_value == .array) {
                for (views_value.array.items) |view_value| {
                    if (view_value != .object) continue;
                    const view_obj = view_value.object;

                    const buffer = if (view_obj.get("buffer")) |b| @as(usize, @intFromFloat(getNumber(b))) else 0;
                    const byte_offset = if (view_obj.get("byteOffset")) |o| @as(usize, @intFromFloat(getNumber(o))) else 0;
                    const byte_length = if (view_obj.get("byteLength")) |l| @as(usize, @intFromFloat(getNumber(l))) else 0;

                    try buffer_views.append(self.allocator, .{
                        .buffer = buffer,
                        .byte_offset = byte_offset,
                        .byte_length = byte_length,
                    });
                }
            }
        }

        // Extract accessors
        var accessors = std.ArrayList(Accessor){};
        defer accessors.deinit(self.allocator);

        if (root.object.get("accessors")) |accessors_value| {
            if (accessors_value == .array) {
                for (accessors_value.array.items) |accessor_value| {
                    if (accessor_value != .object) continue;
                    const accessor_obj = accessor_value.object;

                    const buffer_view = if (accessor_obj.get("bufferView")) |bv| @as(?usize, @intFromFloat(getNumber(bv))) else null;
                    const byte_offset = if (accessor_obj.get("byteOffset")) |o| @as(usize, @intFromFloat(getNumber(o))) else 0;
                    const component_type = if (accessor_obj.get("componentType")) |ct| @as(u32, @intFromFloat(getNumber(ct))) else 0;
                    const count = if (accessor_obj.get("count")) |c| @as(usize, @intFromFloat(getNumber(c))) else 0;
                    const type_str = if (accessor_obj.get("type")) |t| t.string else "SCALAR";

                    try accessors.append(self.allocator, .{
                        .buffer_view = buffer_view,
                        .byte_offset = byte_offset,
                        .component_type = component_type,
                        .count = count,
                        .type_str = type_str,
                    });
                }
            }
        }

        // Extract meshes
        const meshes = try self.extractMeshes(&root, &buffers, &buffer_views, &accessors);

        // Extract materials
        const materials = try self.extractMaterials(&root);

        // Extract nodes
        const nodes = try self.extractNodes(&root);

        // Create empty textures array
        const textures = try self.allocator.alloc(?*const @import("../assets.zig").Texture, 0);

        // Get scene name
        var scene_name: ?[]const u8 = null;
        if (root.object.get("scene")) |scene_idx_value| {
            const scene_idx = @as(usize, @intFromFloat(getNumber(scene_idx_value)));
            if (root.object.get("scenes")) |scenes_value| {
                if (scenes_value == .array and scene_idx < scenes_value.array.items.len) {
                    const scene_obj = scenes_value.array.items[scene_idx];
                    if (scene_obj == .object) {
                        if (scene_obj.object.get("name")) |name_value| {
                            scene_name = try self.allocator.dupe(u8, name_value.string);
                        }
                    }
                }
            }
        }

        return GltfScene{
            .name = scene_name,
            .nodes = nodes,
            .meshes = meshes,
            .materials = materials,
            .textures = textures,
            .allocator = self.allocator,
        };
    }

    fn extractMeshes(
        self: *GltfImporter,
        root: *const std.json.Value,
        buffers: *const std.ArrayList([]const u8),
        buffer_views: *const std.ArrayList(BufferView),
        accessors: *const std.ArrayList(Accessor),
    ) ![]GltfMesh {
        const meshes_value = root.object.get("meshes") orelse return try self.allocator.alloc(GltfMesh, 0);
        if (meshes_value != .array) return try self.allocator.alloc(GltfMesh, 0);

        std.debug.print("Extracting {} GLTF meshes from file\n", .{meshes_value.array.items.len});

        // First pass: count total primitives across all meshes
        var total_primitives: usize = 0;
        for (meshes_value.array.items) |mesh_value| {
            if (mesh_value != .object) continue;
            const mesh_obj = mesh_value.object;
            if (mesh_obj.get("primitives")) |primitives| {
                if (primitives == .array) {
                    total_primitives += primitives.array.items.len;
                }
            }
        }

        std.debug.print("Total primitives to extract: {}\n", .{total_primitives});
        var meshes = try self.allocator.alloc(GltfMesh, total_primitives);
        var mesh_idx: usize = 0;

        for (meshes_value.array.items, 0..) |mesh_value, gltf_mesh_idx| {
            if (mesh_value != .object) continue;

            const mesh_obj = mesh_value.object;
            const base_name = if (mesh_obj.get("name")) |n| n.string else null;

            const primitives = mesh_obj.get("primitives") orelse continue;
            if (primitives != .array or primitives.array.items.len == 0) continue;

            std.debug.print("GLTF Mesh {} '{s}' has {} primitives\n", .{ gltf_mesh_idx, base_name orelse "unnamed", primitives.array.items.len });

            // Process each primitive as a separate mesh
            for (primitives.array.items, 0..) |primitive, prim_idx| {
                if (primitive != .object) {
                    mesh_idx += 1;
                    continue;
                }

                const prim_obj = primitive.object;
                const attributes = prim_obj.get("attributes") orelse {
                    mesh_idx += 1;
                    continue;
                };

                if (attributes != .object) {
                    mesh_idx += 1;
                    continue;
                }

            const attr_obj = attributes.object;

            // Get accessors for position, normal, texcoord
            const position_accessor_idx = if (attr_obj.get("POSITION")) |p| @as(?usize, @intFromFloat(getNumber(p))) else null;
            const normal_accessor_idx = if (attr_obj.get("NORMAL")) |n| @as(?usize, @intFromFloat(getNumber(n))) else null;
            const texcoord_accessor_idx = if (attr_obj.get("TEXCOORD_0")) |t| @as(?usize, @intFromFloat(getNumber(t))) else null;

            const vertex_count = if (position_accessor_idx) |idx| accessors.items[idx].count else 0;
            var vertices = try self.allocator.alloc(components.MeshVertex, vertex_count);

            // Extract positions
            if (position_accessor_idx) |idx| {
                const positions = try self.extractFloatData(buffers, buffer_views, &accessors.items[idx]);
                defer self.allocator.free(positions);

                for (0..vertex_count) |v| {
                    vertices[v].pos = .{
                        .x = positions[v * 3],
                        .y = positions[v * 3 + 1],
                        .z = positions[v * 3 + 2],
                    };
                }
            }

            // Extract normals
            if (normal_accessor_idx) |idx| {
                const normals = try self.extractFloatData(buffers, buffer_views, &accessors.items[idx]);
                defer self.allocator.free(normals);

                for (0..vertex_count) |v| {
                    vertices[v].normal = .{
                        .x = normals[v * 3],
                        .y = normals[v * 3 + 1],
                        .z = normals[v * 3 + 2],
                    };
                }
            } else {
                for (0..vertex_count) |v| {
                    vertices[v].normal = .{ .x = 0, .y = 1, .z = 0 };
                }
            }

            // Extract texcoords
            if (texcoord_accessor_idx) |idx| {
                const texcoords = try self.extractFloatData(buffers, buffer_views, &accessors.items[idx]);
                defer self.allocator.free(texcoords);

                for (0..vertex_count) |v| {
                    vertices[v].uv = .{
                        .x = texcoords[v * 2],
                        .y = texcoords[v * 2 + 1],
                    };
                }
            } else {
                for (0..vertex_count) |v| {
                    vertices[v].uv = .{ .x = 0, .y = 0 };
                }
            }

            // Set default color
            for (0..vertex_count) |v| {
                vertices[v].color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
            }

            // Extract indices
            var indices: []u32 = &.{};
            if (prim_obj.get("indices")) |indices_value| {
                const indices_accessor_idx = @as(usize, @intFromFloat(getNumber(indices_value)));
                indices = try self.extractIndexData(buffers, buffer_views, &accessors.items[indices_accessor_idx]);
            }

                // Get material index for this primitive
                const material_idx = if (prim_obj.get("material")) |mat_val|
                    @as(?u32, @intFromFloat(getNumber(mat_val)))
                else
                    null;

                // Create name for this primitive
                const prim_name = if (base_name) |bn| blk: {
                    const name_buf = try std.fmt.allocPrint(self.allocator, "{s}_prim{}", .{ bn, prim_idx });
                    break :blk name_buf;
                } else blk: {
                    const name_buf = try std.fmt.allocPrint(self.allocator, "mesh{}_prim{}", .{ gltf_mesh_idx, prim_idx });
                    break :blk name_buf;
                };

                meshes[mesh_idx] = .{
                    .vertices = vertices,
                    .indices = indices,
                    .name = prim_name,
                    .material_index = material_idx,
                };
                mesh_idx += 1;
            }
        }

        return meshes;
    }

    fn extractFloatData(
        self: *GltfImporter,
        buffers: *const std.ArrayList([]const u8),
        buffer_views: *const std.ArrayList(BufferView),
        accessor: *const Accessor,
    ) ![]f32 {
        const buffer_view_idx = accessor.buffer_view orelse return try self.allocator.alloc(f32, 0);
        const buffer_view = buffer_views.items[buffer_view_idx];
        const buffer = buffers.items[buffer_view.buffer];

        const byte_offset = buffer_view.byte_offset + accessor.byte_offset;
        const component_count = accessor.count * componentCountForType(accessor.type_str);

        var data = try self.allocator.alloc(f32, component_count);

        switch (accessor.component_type) {
            5126 => { // FLOAT
                const src = buffer[byte_offset..];
                for (0..component_count) |i| {
                    const offset = i * @sizeOf(f32);
                    data[i] = @bitCast(@as(u32, @bitCast([4]u8{
                        src[offset],
                        src[offset + 1],
                        src[offset + 2],
                        src[offset + 3],
                    })));
                }
            },
            else => return error.UnsupportedComponentType,
        }

        return data;
    }

    fn extractIndexData(
        self: *GltfImporter,
        buffers: *const std.ArrayList([]const u8),
        buffer_views: *const std.ArrayList(BufferView),
        accessor: *const Accessor,
    ) ![]u32 {
        const buffer_view_idx = accessor.buffer_view orelse return try self.allocator.alloc(u32, 0);
        const buffer_view = buffer_views.items[buffer_view_idx];
        const buffer = buffers.items[buffer_view.buffer];

        const byte_offset = buffer_view.byte_offset + accessor.byte_offset;

        var data = try self.allocator.alloc(u32, accessor.count);

        switch (accessor.component_type) {
            5123 => { // UNSIGNED_SHORT
                const src = buffer[byte_offset..];
                for (0..accessor.count) |i| {
                    const offset = i * @sizeOf(u16);
                    const value: u16 = @bitCast([2]u8{
                        src[offset],
                        src[offset + 1],
                    });
                    data[i] = value;
                }
            },
            5125 => { // UNSIGNED_INT
                const src = buffer[byte_offset..];
                for (0..accessor.count) |i| {
                    const offset = i * @sizeOf(u32);
                    data[i] = @bitCast([4]u8{
                        src[offset],
                        src[offset + 1],
                        src[offset + 2],
                        src[offset + 3],
                    });
                }
            },
            else => return error.UnsupportedComponentType,
        }

        return data;
    }

    fn extractMaterials(self: *GltfImporter, root: *const std.json.Value) ![]GltfMaterial {
        const materials_value = root.object.get("materials") orelse return try self.allocator.alloc(GltfMaterial, 0);
        if (materials_value != .array) return try self.allocator.alloc(GltfMaterial, 0);

        var materials = try self.allocator.alloc(GltfMaterial, materials_value.array.items.len);

        for (materials_value.array.items, 0..) |material_value, i| {
            var material = GltfMaterial{};

            if (material_value == .object) {
                const mat_obj = material_value.object;

                if (mat_obj.get("pbrMetallicRoughness")) |pbr_value| {
                    if (pbr_value == .object) {
                        const pbr_obj = pbr_value.object;

                        if (pbr_obj.get("baseColorFactor")) |color_value| {
                            if (color_value == .array and color_value.array.items.len >= 4) {
                                material.base_color = .{
                                    .r = @floatCast(getNumber(color_value.array.items[0])),
                                    .g = @floatCast(getNumber(color_value.array.items[1])),
                                    .b = @floatCast(getNumber(color_value.array.items[2])),
                                    .a = @floatCast(getNumber(color_value.array.items[3])),
                                };
                            }
                        }

                        if (pbr_obj.get("metallicFactor")) |metallic_value| {
                            material.metallic = @floatCast(getNumber(metallic_value));
                        }

                        if (pbr_obj.get("roughnessFactor")) |roughness_value| {
                            material.roughness = @floatCast(getNumber(roughness_value));
                        }

                        if (pbr_obj.get("baseColorTexture")) |tex_value| {
                            if (tex_value == .object) {
                                if (tex_value.object.get("index")) |idx_value| {
                                    material.base_color_texture = @intFromFloat(getNumber(idx_value));
                                }
                            }
                        }
                    }
                }
            }

            materials[i] = material;
        }

        return materials;
    }

    fn extractNodes(self: *GltfImporter, root: *const std.json.Value) ![]GltfNode {
        const nodes_value = root.object.get("nodes") orelse return try self.allocator.alloc(GltfNode, 0);
        if (nodes_value != .array) return try self.allocator.alloc(GltfNode, 0);

        std.debug.print("Extracting {} nodes from GLTF\n", .{nodes_value.array.items.len});
        var nodes = try self.allocator.alloc(GltfNode, nodes_value.array.items.len);

        for (nodes_value.array.items, 0..) |node_value, i| {
            var node = GltfNode{};

            if (node_value == .object) {
                const node_obj = node_value.object;

                if (node_obj.get("name")) |name_value| {
                    node.name = try self.allocator.dupe(u8, name_value.string);
                }

                if (node_obj.get("mesh")) |mesh_value| {
                    node.mesh_index = @intFromFloat(getNumber(mesh_value));
                }

                if (node_obj.get("translation")) |trans_value| {
                    if (trans_value == .array and trans_value.array.items.len >= 3) {
                        node.transform.translation = .{
                            .x = @floatCast(getNumber(trans_value.array.items[0])),
                            .y = @floatCast(getNumber(trans_value.array.items[1])),
                            .z = @floatCast(getNumber(trans_value.array.items[2])),
                        };
                    }
                }

                if (node_obj.get("rotation")) |rot_value| {
                    if (rot_value == .array and rot_value.array.items.len >= 4) {
                        // Quaternion to Euler (simplified)
                        const x: f32 = @floatCast(getNumber(rot_value.array.items[0]));
                        const y: f32 = @floatCast(getNumber(rot_value.array.items[1]));
                        const z: f32 = @floatCast(getNumber(rot_value.array.items[2]));
                        const w: f32 = @floatCast(getNumber(rot_value.array.items[3]));

                        // Convert quaternion to Euler angles (YXZ order)
                        const sinr_cosp = 2.0 * (w * x + y * z);
                        const cosr_cosp = 1.0 - 2.0 * (x * x + y * y);
                        node.transform.rotation.x = std.math.atan2(sinr_cosp, cosr_cosp);

                        const sinp = 2.0 * (w * y - z * x);
                        if (@abs(sinp) >= 1.0) {
                            node.transform.rotation.y = std.math.copysign(@as(f32, std.math.pi / 2.0), sinp);
                        } else {
                            node.transform.rotation.y = std.math.asin(sinp);
                        }

                        const siny_cosp = 2.0 * (w * z + x * y);
                        const cosy_cosp = 1.0 - 2.0 * (y * y + z * z);
                        node.transform.rotation.z = std.math.atan2(siny_cosp, cosy_cosp);
                    }
                }

                if (node_obj.get("scale")) |scale_value| {
                    if (scale_value == .array and scale_value.array.items.len >= 3) {
                        node.transform.scale = .{
                            .x = @floatCast(getNumber(scale_value.array.items[0])),
                            .y = @floatCast(getNumber(scale_value.array.items[1])),
                            .z = @floatCast(getNumber(scale_value.array.items[2])),
                        };
                    }
                }

                if (node_obj.get("children")) |children_value| {
                    if (children_value == .array) {
                        node.children = try self.allocator.alloc(u32, children_value.array.items.len);
                        for (children_value.array.items, 0..) |child_value, j| {
                            node.children[j] = @intFromFloat(getNumber(child_value));
                        }
                    }
                }
            }

            nodes[i] = node;
        }

        // Build parent relationships
        for (nodes, 0..) |node, i| {
            for (node.children) |child_idx| {
                nodes[child_idx].parent = @intCast(i);
            }
        }

        return nodes;
    }

    fn componentCountForType(type_str: []const u8) usize {
        if (std.mem.eql(u8, type_str, "SCALAR")) return 1;
        if (std.mem.eql(u8, type_str, "VEC2")) return 2;
        if (std.mem.eql(u8, type_str, "VEC3")) return 3;
        if (std.mem.eql(u8, type_str, "VEC4")) return 4;
        if (std.mem.eql(u8, type_str, "MAT2")) return 4;
        if (std.mem.eql(u8, type_str, "MAT3")) return 9;
        if (std.mem.eql(u8, type_str, "MAT4")) return 16;
        return 1;
    }
};

const BufferView = struct {
    buffer: usize,
    byte_offset: usize,
    byte_length: usize,
};

const Accessor = struct {
    buffer_view: ?usize,
    byte_offset: usize,
    component_type: u32,
    count: usize,
    type_str: []const u8,
};
