// ─────────────────────────────────────────────
// Mesh Renderer
// ─────────────────────────────────────────────
// Renders 3D meshes using vertex and index buffers with support for
// texture mapping, lighting, and custom shaders. Uses perspective or
// orthographic projection based on camera configuration.

const MeshRenderer = @This();

const std = @import("std");
const vk = @import("vulkan");
const phasor_common = @import("phasor-common");
const components = @import("../components.zig");
const Transform3d = components.Transform3d;
const RenderContext = @import("RenderContext.zig");

pub const MeshResources = struct {
    // Pipeline resources
    pipeline_layout: vk.PipelineLayout,
    pipeline_default: vk.Pipeline,

    // Shared buffers
    vertex_buffer: vk.Buffer,
    vertex_memory: vk.DeviceMemory,
    index_buffer: vk.Buffer,
    index_memory: vk.DeviceMemory,
    max_vertices: u32,
    max_indices: u32,

    // Lighting uniform buffer
    light_buffer: vk.Buffer,
    light_memory: vk.DeviceMemory,

    // Descriptor resources
    descriptor_set_layout: vk.DescriptorSetLayout,
    descriptor_pool: vk.DescriptorPool,
};

pub fn init(
    vkd: anytype,
    dev_res: anytype,
    color_format: vk.Format,
    depth_format: vk.Format,
    extent: vk.Extent2D,
    allocator: std.mem.Allocator,
) !MeshResources {
    _ = allocator;

    // Create descriptor set layout for texture sampling + light UBO
    const bindings = [_]vk.DescriptorSetLayoutBinding{
        .{ // binding 0: texture sampler
            .binding = 0,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = null,
        },
        .{ // binding 1: directional light uniform buffer
            .binding = 1,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = null,
        },
    };

    const descriptor_set_layout = try vkd.createDescriptorSetLayout(&.{
        .binding_count = bindings.len,
        .p_bindings = &bindings,
    }, null);
    errdefer vkd.destroyDescriptorSetLayout(descriptor_set_layout, null);

    // Create descriptor pool (samplers + uniform buffers)
    const pool_sizes = [_]vk.DescriptorPoolSize{
        .{ .type = .combined_image_sampler, .descriptor_count = 100 },
        .{ .type = .uniform_buffer, .descriptor_count = 100 },
    };

    const descriptor_pool = try vkd.createDescriptorPool(&.{
        .flags = .{},
        .pool_size_count = pool_sizes.len,
        .p_pool_sizes = &pool_sizes,
        .max_sets = 100,
    }, null);
    errdefer vkd.destroyDescriptorPool(descriptor_pool, null);

    // Create push constant range for MVP matrix
    const push_constant_range = vk.PushConstantRange{
        .stage_flags = .{ .vertex_bit = true },
        .offset = 0,
        .size = @sizeOf([16]f32), // 4x4 matrix
    };

    const pipeline_layout = try vkd.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&descriptor_set_layout),
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    }, null);
    errdefer vkd.destroyPipelineLayout(pipeline_layout, null);

    const pipeline_default = try createPipeline(vkd, pipeline_layout, color_format, depth_format, extent);
    errdefer vkd.destroyPipeline(pipeline_default, null);

    const max_vertices: u32 = 100000; // Increased to support larger models
    const max_indices: u32 = 300000;
    const vertex_buffer_size = @sizeOf(components.MeshVertex) * max_vertices;
    const index_buffer_size = @sizeOf(u32) * max_indices;

    // Create light uniform buffer (vec4)
    const light_buffer_size: vk.DeviceSize = @sizeOf([4]f32);
    const light_buffer = try vkd.createBuffer(&.{
        .size = light_buffer_size,
        .usage = .{ .uniform_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    errdefer vkd.destroyBuffer(light_buffer, null);

    const light_mem_reqs = vkd.getBufferMemoryRequirements(light_buffer);
    const ctx = RenderContext{
        .dev_res = dev_res,
        .cmd_pool = undefined,
        .window_width = 0,
        .window_height = 0,
        .camera_offset = .{},
        .allocator = undefined,
        .upload_counter = undefined,
    };
    const light_memory = try ctx.allocateMemory(vkd, light_mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    errdefer vkd.freeMemory(light_memory, null);
    try vkd.bindBufferMemory(light_buffer, light_memory, 0);

    // Initialize light to default direction
    {
        const default_dir = components.DirectionalLight{}; // uses default values
        const len = @sqrt(default_dir.dir.x * default_dir.dir.x + default_dir.dir.y * default_dir.dir.y + default_dir.dir.z * default_dir.dir.z);
        const ndx: f32 = if (len != 0) default_dir.dir.x / len else 0.0;
        const ndy: f32 = if (len != 0) default_dir.dir.y / len else -1.0;
        const ndz: f32 = if (len != 0) default_dir.dir.z / len else 0.0;
        const data = [_]f32{ ndx, ndy, ndz, 0.0 };
        const mapped = try vkd.mapMemory(light_memory, 0, light_buffer_size, .{});
        defer vkd.unmapMemory(light_memory);
        const p: [*]f32 = @ptrCast(@alignCast(mapped));
        @memcpy(p[0..4], &data);
    }

    // Create vertex buffer
    const vertex_buffer = try vkd.createBuffer(&.{
        .size = vertex_buffer_size,
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    errdefer vkd.destroyBuffer(vertex_buffer, null);

    const vertex_mem_reqs = vkd.getBufferMemoryRequirements(vertex_buffer);
    const vertex_memory = try ctx.allocateMemory(vkd, vertex_mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    errdefer vkd.freeMemory(vertex_memory, null);

    try vkd.bindBufferMemory(vertex_buffer, vertex_memory, 0);

    // Create index buffer
    const index_buffer = try vkd.createBuffer(&.{
        .size = index_buffer_size,
        .usage = .{ .transfer_dst_bit = true, .index_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    errdefer vkd.destroyBuffer(index_buffer, null);

    const index_mem_reqs = vkd.getBufferMemoryRequirements(index_buffer);
    const index_memory = try ctx.allocateMemory(vkd, index_mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    errdefer vkd.freeMemory(index_memory, null);

    try vkd.bindBufferMemory(index_buffer, index_memory, 0);

    return .{
        .pipeline_layout = pipeline_layout,
        .pipeline_default = pipeline_default,
        .vertex_buffer = vertex_buffer,
        .vertex_memory = vertex_memory,
        .index_buffer = index_buffer,
        .index_memory = index_memory,
        .max_vertices = max_vertices,
        .max_indices = max_indices,
        .light_buffer = light_buffer,
        .light_memory = light_memory,
        .descriptor_set_layout = descriptor_set_layout,
        .descriptor_pool = descriptor_pool,
    };
}

pub fn deinit(vkd: anytype, resources: *const MeshResources) void {
    vkd.destroyBuffer(resources.index_buffer, null);
    vkd.freeMemory(resources.index_memory, null);
    vkd.destroyBuffer(resources.vertex_buffer, null);
    vkd.freeMemory(resources.vertex_memory, null);
    vkd.destroyBuffer(resources.light_buffer, null);
    vkd.freeMemory(resources.light_memory, null);
    vkd.destroyPipeline(resources.pipeline_default, null);
    vkd.destroyPipelineLayout(resources.pipeline_layout, null);
    vkd.destroyDescriptorPool(resources.descriptor_pool, null);
    vkd.destroyDescriptorSetLayout(resources.descriptor_set_layout, null);
}

const assets = @import("../assets.zig");

pub const CollectedMesh = struct {
    vertex_count: u32,
    index_count: u32,
    mvp_matrix: [16]f32,
    texture: ?*const assets.Texture,
    custom_shader: ?*const assets.Shader,
};

pub fn collect(
    vkd: anytype,
    ctx: *RenderContext,
    resources: *const MeshResources,
    query: anytype,
    camera: *const components.Camera3d,
    camera_transform: *const Transform3d,
) !std.ArrayList(CollectedMesh) {
    var meshes = try std.ArrayList(CollectedMesh).initCapacity(ctx.allocator, 10);
    errdefer meshes.deinit(ctx.allocator);

    var all_vertices = try std.ArrayList(components.MeshVertex).initCapacity(ctx.allocator, 100);
    defer all_vertices.deinit(ctx.allocator);

    var all_indices = try std.ArrayList(u32).initCapacity(ctx.allocator, 300);
    defer all_indices.deinit(ctx.allocator);

    // Build view matrix from camera transform
    const view_matrix = buildViewMatrix(camera_transform);

    // Build projection matrix based on camera type
    const proj_matrix = buildProjectionMatrix(camera, ctx);

    var it = query.iterator();
    while (it.next()) |entity| {
        if (entity.get(components.Mesh)) |mesh| {
            const transform = entity.get(Transform3d) orelse &Transform3d{};
            const material = entity.get(components.Material) orelse &components.Material{};
            const custom_shader_component = entity.get(components.CustomShader);

            // Build model matrix from transform
            const model_matrix = buildModelMatrix(transform);

            // Compute MVP = Projection * View * Model
            const mv_matrix = matmul(view_matrix, model_matrix);
            const mvp_matrix = matmul(proj_matrix, mv_matrix);

            const vertex_offset: u32 = @intCast(all_vertices.items.len);

            // Append vertices with material color applied
            for (mesh.vertices) |vertex| {
                try all_vertices.append(ctx.allocator, .{
                    .pos = vertex.pos,
                    .normal = vertex.normal,
                    .uv = vertex.uv,
                    .color = .{
                        .r = vertex.color.r * material.color.r,
                        .g = vertex.color.g * material.color.g,
                        .b = vertex.color.b * material.color.b,
                        .a = vertex.color.a * material.color.a,
                    },
                });
            }

            // Append indices with vertex offset
            for (mesh.indices) |index| {
                try all_indices.append(ctx.allocator, vertex_offset + index);
            }

            try meshes.append(ctx.allocator, .{
                .vertex_count = @intCast(mesh.vertices.len),
                .index_count = @intCast(mesh.indices.len),
                .mvp_matrix = mvp_matrix,
                .texture = material.texture,
                .custom_shader = if (custom_shader_component) |cs| cs.shader else null,
            });
        }
    }

    // Write mesh data directly to mapped memory
    if (all_vertices.items.len > 0) {
        // Check if we exceed buffer capacity
        if (all_vertices.items.len > resources.max_vertices) {
            std.log.err("Vertex buffer overflow: {d} vertices exceeds max {d}", .{ all_vertices.items.len, resources.max_vertices });
            return error.VertexBufferOverflow;
        }
        try ctx.writeToMappedBuffer(vkd, components.MeshVertex, resources.vertex_memory, all_vertices.items);
    }

    if (all_indices.items.len > 0) {
        // Check if we exceed buffer capacity
        if (all_indices.items.len > resources.max_indices) {
            std.log.err("Index buffer overflow: {d} indices exceeds max {d}", .{ all_indices.items.len, resources.max_indices });
            return error.IndexBufferOverflow;
        }
        try ctx.writeToMappedBuffer(vkd, u32, resources.index_memory, all_indices.items);
    }

    return meshes;
}

pub fn record(
    vkd: anytype,
    ctx: *RenderContext,
    resources: *const MeshResources,
    cmdbuf: vk.CommandBuffer,
    meshes: []const CollectedMesh,
) void {
    _ = ctx;
    if (meshes.len == 0) return;

    const offset = [_]vk.DeviceSize{0};
    vkd.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&resources.vertex_buffer), &offset);
    vkd.cmdBindIndexBuffer(cmdbuf, resources.index_buffer, 0, .uint32);

    var index_offset: u32 = 0;
    var current_pipeline: ?vk.Pipeline = null;
    var current_layout: ?vk.PipelineLayout = null;

    for (meshes) |mesh| {
        // Determine which pipeline and layout to use
        const pipeline = if (mesh.custom_shader) |shader|
            shader.pipeline.?
        else
            resources.pipeline_default;

        const layout = if (mesh.custom_shader) |shader|
            shader.pipeline_layout.?
        else
            resources.pipeline_layout;

        // Bind pipeline if it changed
        if (current_pipeline == null or current_pipeline.? != pipeline) {
            vkd.cmdBindPipeline(cmdbuf, .graphics, pipeline);
            current_pipeline = pipeline;
            current_layout = layout;
        }

        // Only handle texture binding for default pipeline (custom shaders don't have descriptor sets)
        if (mesh.custom_shader == null) {
            if (mesh.texture) |texture| {
                if (texture.image_view != null and texture.sampler != null) {
                    // Create and bind descriptor set for this texture
                    var descriptor_set: vk.DescriptorSet = undefined;
                    vkd.allocateDescriptorSets(&.{
                        .descriptor_pool = resources.descriptor_pool,
                        .descriptor_set_count = 1,
                        .p_set_layouts = @ptrCast(&resources.descriptor_set_layout),
                    }, @ptrCast(&descriptor_set)) catch {
                        index_offset += mesh.index_count;
                        continue;
                    };

                    const image_info = vk.DescriptorImageInfo{
                        .sampler = texture.sampler.?,
                        .image_view = texture.image_view.?,
                        .image_layout = .shader_read_only_optimal,
                    };

                    const buffer_info = vk.DescriptorBufferInfo{
                        .buffer = resources.light_buffer,
                        .offset = 0,
                        .range = @sizeOf([4]f32),
                    };

                    const writes = [_]vk.WriteDescriptorSet{
                        .{
                            .dst_set = descriptor_set,
                            .dst_binding = 0,
                            .dst_array_element = 0,
                            .descriptor_count = 1,
                            .descriptor_type = .combined_image_sampler,
                            .p_image_info = @ptrCast(&image_info),
                            .p_buffer_info = undefined,
                            .p_texel_buffer_view = undefined,
                        },
                        .{
                            .dst_set = descriptor_set,
                            .dst_binding = 1,
                            .dst_array_element = 0,
                            .descriptor_count = 1,
                            .descriptor_type = .uniform_buffer,
                            .p_image_info = undefined,
                            .p_buffer_info = @ptrCast(&buffer_info),
                            .p_texel_buffer_view = undefined,
                        },
                    };

                    vkd.updateDescriptorSets(writes.len, &writes, 0, undefined);
                    vkd.cmdBindDescriptorSets(cmdbuf, .graphics, layout, 0, 1, @ptrCast(&descriptor_set), 0, undefined);
                }
            }
        }

        // Push MVP matrix
        vkd.cmdPushConstants(
            cmdbuf,
            layout,
            .{ .vertex_bit = true },
            0,
            @sizeOf([16]f32),
            &mesh.mvp_matrix,
        );

        vkd.cmdDrawIndexed(cmdbuf, mesh.index_count, 1, index_offset, 0, 0);
        index_offset += mesh.index_count;
    }
}

fn buildModelMatrix(transform: *const Transform3d) [16]f32 {
    // Build TRS matrix (column-major for Vulkan)
    const t = transform.translation;
    const r = transform.rotation;
    const s = transform.scale;

    // Rotation matrices (Euler angles: XYZ order)
    const cos_x = @cos(r.x);
    const sin_x = @sin(r.x);
    const cos_y = @cos(r.y);
    const sin_y = @sin(r.y);
    const cos_z = @cos(r.z);
    const sin_z = @sin(r.z);

    // Combined rotation matrix (Z * Y * X)
    const r00 = cos_y * cos_z;
    const r01 = cos_y * sin_z;
    const r02 = -sin_y;

    const r10 = sin_x * sin_y * cos_z - cos_x * sin_z;
    const r11 = sin_x * sin_y * sin_z + cos_x * cos_z;
    const r12 = sin_x * cos_y;

    const r20 = cos_x * sin_y * cos_z + sin_x * sin_z;
    const r21 = cos_x * sin_y * sin_z - sin_x * cos_z;
    const r22 = cos_x * cos_y;

    // Column-major: each column is a basis vector
    return [16]f32{
        r00 * s.x, r10 * s.y, r20 * s.z, 0.0,  // column 0
        r01 * s.x, r11 * s.y, r21 * s.z, 0.0,  // column 1
        r02 * s.x, r12 * s.y, r22 * s.z, 0.0,  // column 2
        t.x,       t.y,       t.z,       1.0,  // column 3
    };
}

fn buildViewMatrix(camera_transform: *const Transform3d) [16]f32 {
    const pos = camera_transform.translation;
    const rot = camera_transform.rotation;

    // Build view matrix from FPS camera (pitch/yaw)
    // pitch = rotation.x, yaw = rotation.y
    const cos_pitch = @cos(rot.x);
    const sin_pitch = @sin(rot.x);
    const cos_yaw = @cos(rot.y);
    const sin_yaw = @sin(rot.y);

    // Calculate forward vector from pitch and yaw
    const forward = phasor_common.Vec3{
        .x = sin_yaw * cos_pitch,
        .y = sin_pitch,
        .z = cos_yaw * cos_pitch,
    };

    const target = phasor_common.Vec3{
        .x = pos.x + forward.x,
        .y = pos.y + forward.y,
        .z = pos.z + forward.z,
    };

    const up = phasor_common.Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };

    return lookAt(pos, target, up);
}

fn lookAt(eye: phasor_common.Vec3, center: phasor_common.Vec3, up: phasor_common.Vec3) [16]f32 {
    const f = normalize(vec3Sub(center, eye));
    const s = normalize(cross(f, up));
    const u = cross(s, f);

    // Column-major view matrix
    return [16]f32{
        s.x,  u.x,  -f.x, 0.0,  // column 0
        s.y,  u.y,  -f.y, 0.0,  // column 1
        s.z,  u.z,  -f.z, 0.0,  // column 2
        -dot(s, eye), -dot(u, eye), dot(f, eye), 1.0,  // column 3
    };
}

fn buildProjectionMatrix(camera: *const components.Camera3d, ctx: *RenderContext) [16]f32 {
    return switch (camera.*) {
        .Perspective => |persp| {
            const aspect = ctx.window_width / ctx.window_height;
            return perspective(persp.fov, aspect, persp.near, persp.far);
        },
        .Orthographic => |ortho| {
            return orthographic(ortho.left, ortho.right, ortho.bottom, ortho.top, ortho.near, ortho.far);
        },
        .Viewport => {
            // Use perspective for viewport mode
            const aspect = ctx.window_width / ctx.window_height;
            return perspective(std.math.pi / 4.0, aspect, 0.1, 100.0);
        },
    };
}

fn perspective(fov: f32, aspect: f32, near: f32, far: f32) [16]f32 {
    _ = far; // unused with reverse-Z
    const tan_half_fov = @tan(fov / 2.0);
    const f = 1.0 / tan_half_fov;

    // Column-major perspective matrix for Vulkan
    // Using reverse-Z: near=1.0, far=0.0 for better precision
    return [16]f32{
        f / aspect, 0.0, 0.0,  0.0,  // column 0
        0.0,        -f,  0.0,  0.0,  // column 1 (flip Y for Vulkan)
        0.0,        0.0, 0.0,  -1.0, // column 2 (reverse-Z)
        0.0,        0.0, near, 0.0,  // column 3
    };
}

fn orthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) [16]f32 {
    // Column-major orthographic matrix
    return [16]f32{
        2.0 / (right - left), 0.0,                  0.0,                 0.0,  // column 0
        0.0,                  2.0 / (top - bottom), 0.0,                 0.0,  // column 1
        0.0,                  0.0,                  -2.0 / (far - near), 0.0,  // column 2
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1.0,  // column 3
    };
}

fn matmul(a: [16]f32, b: [16]f32) [16]f32 {
    var result: [16]f32 = undefined;
    // Column-major multiplication
    var col: usize = 0;
    while (col < 4) : (col += 1) {
        var row: usize = 0;
        while (row < 4) : (row += 1) {
            result[col * 4 + row] =
                a[0 * 4 + row] * b[col * 4 + 0] +
                a[1 * 4 + row] * b[col * 4 + 1] +
                a[2 * 4 + row] * b[col * 4 + 2] +
                a[3 * 4 + row] * b[col * 4 + 3];
        }
    }
    return result;
}

fn vec3Sub(a: phasor_common.Vec3, b: phasor_common.Vec3) phasor_common.Vec3 {
    return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
}

fn normalize(v: phasor_common.Vec3) phasor_common.Vec3 {
    const len = @sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    return .{ .x = v.x / len, .y = v.y / len, .z = v.z / len };
}

fn cross(a: phasor_common.Vec3, b: phasor_common.Vec3) phasor_common.Vec3 {
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

fn dot(a: phasor_common.Vec3, b: phasor_common.Vec3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

pub fn updateDirectionalLight(
    vkd: anytype,
    resources: *const MeshResources,
    dir: phasor_common.Vec3,
) void {
    // Normalize and write to light uniform buffer as vec4 (xyz, 0)
    const len = @sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z);
    const ndx: f32 = if (len != 0) dir.x / len else 0.0;
    const ndy: f32 = if (len != 0) dir.y / len else -1.0;
    const ndz: f32 = if (len != 0) dir.z / len else 0.0;
    const data = [_]f32{ ndx, ndy, ndz, 0.0 };
    const mapped = vkd.mapMemory(resources.light_memory, 0, @sizeOf([4]f32), .{}) catch return;
    defer vkd.unmapMemory(resources.light_memory);
    const p: [*]f32 = @ptrCast(@alignCast(mapped));
    @memcpy(p[0..4], &data);
}

fn createPipeline(
    vkd: anytype,
    layout: vk.PipelineLayout,
    color_format: vk.Format,
    depth_format: vk.Format,
    extent: vk.Extent2D,
) !vk.Pipeline {
    const shaders = @import("shader_imports");

    const vert_module = try vkd.createShaderModule(&.{
        .code_size = shaders.mesh_vert.len,
        .p_code = @ptrCast(&shaders.mesh_vert),
    }, null);
    defer vkd.destroyShaderModule(vert_module, null);

    const frag_module = try vkd.createShaderModule(&.{
        .code_size = shaders.mesh_frag.len,
        .p_code = @ptrCast(&shaders.mesh_frag),
    }, null);
    defer vkd.destroyShaderModule(frag_module, null);

    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
        .{ .stage = .{ .vertex_bit = true }, .module = vert_module, .p_name = "main" },
        .{ .stage = .{ .fragment_bit = true }, .module = frag_module, .p_name = "main" },
    };

    const vertex_binding = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(components.MeshVertex),
        .input_rate = .vertex,
    };

    const vertex_attributes = [_]vk.VertexInputAttributeDescription{
        .{ .binding = 0, .location = 0, .format = .r32g32b32_sfloat, .offset = @offsetOf(components.MeshVertex, "pos") },
        .{ .binding = 0, .location = 1, .format = .r32g32b32_sfloat, .offset = @offsetOf(components.MeshVertex, "normal") },
        .{ .binding = 0, .location = 2, .format = .r32g32_sfloat, .offset = @offsetOf(components.MeshVertex, "uv") },
        .{ .binding = 0, .location = 3, .format = .r32g32b32a32_sfloat, .offset = @offsetOf(components.MeshVertex, "color") },
    };

    const vertex_input = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&vertex_binding),
        .vertex_attribute_description_count = vertex_attributes.len,
        .p_vertex_attribute_descriptions = &vertex_attributes,
    };

    const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list,
        .primitive_restart_enable = .false,
    };

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    const viewport_state = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = @ptrCast(&viewport),
        .scissor_count = 1,
        .p_scissors = @ptrCast(&scissor),
    };

    const rasterizer = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false,
        .rasterizer_discard_enable = .false,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .counter_clockwise,
        .depth_bias_enable = .false,
        .depth_bias_constant_factor = 0.0,
        .depth_bias_clamp = 0.0,
        .depth_bias_slope_factor = 0.0,
        .line_width = 1.0,
    };

    const multisampling = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = .false,
        .min_sample_shading = 1.0,
        .p_sample_mask = null,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    const color_blend_attachment = vk.PipelineColorBlendAttachmentState{
        .blend_enable = .false,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const color_blending = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_blend_attachment),
        .blend_constants = .{ 0.0, 0.0, 0.0, 0.0 },
    };

    const depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
        .depth_test_enable = .true,
        .depth_write_enable = .true,
        .depth_compare_op = .greater,
        .depth_bounds_test_enable = .false,
        .min_depth_bounds = 0.0,
        .max_depth_bounds = 1.0,
        .stencil_test_enable = .false,
        .front = .{
            .fail_op = .keep,
            .pass_op = .keep,
            .depth_fail_op = .keep,
            .compare_op = .always,
            .compare_mask = 0,
            .write_mask = 0,
            .reference = 0,
        },
        .back = .{
            .fail_op = .keep,
            .pass_op = .keep,
            .depth_fail_op = .keep,
            .compare_op = .always,
            .compare_mask = 0,
            .write_mask = 0,
            .reference = 0,
        },
    };

    var rendering_info = vk.PipelineRenderingCreateInfo{
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachment_formats = @ptrCast(&color_format),
        .depth_attachment_format = depth_format,
        .stencil_attachment_format = .undefined,
    };

    const pipeline_info = vk.GraphicsPipelineCreateInfo{
        .stage_count = shader_stages.len,
        .p_stages = &shader_stages,
        .p_vertex_input_state = &vertex_input,
        .p_input_assembly_state = &input_assembly,
        .p_viewport_state = &viewport_state,
        .p_rasterization_state = &rasterizer,
        .p_multisample_state = &multisampling,
        .p_depth_stencil_state = &depth_stencil,
        .p_color_blend_state = &color_blending,
        .p_dynamic_state = null,
        .layout = layout,
        .render_pass = .null_handle,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
        .p_next = &rendering_info,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try vkd.createGraphicsPipelines(.null_handle, 1, @ptrCast(&pipeline_info), null, @ptrCast(&pipeline));

    return pipeline;
}
