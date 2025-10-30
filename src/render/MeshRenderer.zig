// ─────────────────────────────────────────────
// Mesh Renderer
// ─────────────────────────────────────────────
// Renders 3D meshes with vertex and index buffers

const MeshRenderer = @This();

const std = @import("std");
const vk = @import("vulkan");
const phasor_common = @import("phasor-common");
const components = @import("../components.zig");
const Transform3d = components.Transform3d;
const RenderContext = @import("RenderContext.zig");

pub const MeshResources = struct {
    pipeline_layout: vk.PipelineLayout,
    pipeline: vk.Pipeline,
    vertex_buffer: vk.Buffer,
    vertex_memory: vk.DeviceMemory,
    index_buffer: vk.Buffer,
    index_memory: vk.DeviceMemory,
    max_vertices: u32,
    max_indices: u32,
    descriptor_set_layout: vk.DescriptorSetLayout,
    descriptor_pool: vk.DescriptorPool,
};

pub fn init(
    vkd: anytype,
    dev_res: anytype,
    render_pass: vk.RenderPass,
    extent: vk.Extent2D,
    allocator: std.mem.Allocator,
) !MeshResources {
    _ = allocator;

    // Create descriptor set layout for texture sampling
    const sampler_binding = vk.DescriptorSetLayoutBinding{
        .binding = 0,
        .descriptor_type = .combined_image_sampler,
        .descriptor_count = 1,
        .stage_flags = .{ .fragment_bit = true },
        .p_immutable_samplers = null,
    };

    const descriptor_set_layout = try vkd.createDescriptorSetLayout(&.{
        .binding_count = 1,
        .p_bindings = @ptrCast(&sampler_binding),
    }, null);
    errdefer vkd.destroyDescriptorSetLayout(descriptor_set_layout, null);

    // Create descriptor pool
    const pool_size = vk.DescriptorPoolSize{
        .type = .combined_image_sampler,
        .descriptor_count = 100,
    };

    const descriptor_pool = try vkd.createDescriptorPool(&.{
        .flags = .{},
        .pool_size_count = 1,
        .p_pool_sizes = @ptrCast(&pool_size),
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

    const pipeline = try createPipeline(vkd, pipeline_layout, render_pass, extent);
    errdefer vkd.destroyPipeline(pipeline, null);

    const max_vertices: u32 = 500000;  // Increased for complex scenes like Sponza
    const max_indices: u32 = 1500000;
    const vertex_buffer_size = @sizeOf(components.MeshVertex) * max_vertices;
    const index_buffer_size = @sizeOf(u32) * max_indices;

    // Create vertex buffer
    const vertex_buffer = try vkd.createBuffer(&.{
        .size = vertex_buffer_size,
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    errdefer vkd.destroyBuffer(vertex_buffer, null);

    const vertex_mem_reqs = vkd.getBufferMemoryRequirements(vertex_buffer);
    const ctx = RenderContext{
        .dev_res = dev_res,
        .cmd_pool = undefined,
        .window_width = 0,
        .window_height = 0,
        .camera_offset = .{},
        .allocator = undefined,
        .upload_counter = undefined,
    };
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
        .pipeline = pipeline,
        .vertex_buffer = vertex_buffer,
        .vertex_memory = vertex_memory,
        .index_buffer = index_buffer,
        .index_memory = index_memory,
        .max_vertices = max_vertices,
        .max_indices = max_indices,
        .descriptor_set_layout = descriptor_set_layout,
        .descriptor_pool = descriptor_pool,
    };
}

pub fn deinit(vkd: anytype, resources: *const MeshResources) void {
    vkd.destroyBuffer(resources.index_buffer, null);
    vkd.freeMemory(resources.index_memory, null);
    vkd.destroyBuffer(resources.vertex_buffer, null);
    vkd.freeMemory(resources.vertex_memory, null);
    vkd.destroyPipeline(resources.pipeline, null);
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
};

pub fn collect(
    vkd: anytype,
    ctx: *RenderContext,
    resources: *const MeshResources,
    query: anytype,
    camera: *const components.Camera3d,
    camera_transform: *const Transform3d,
) !std.ArrayList(CollectedMesh) {
    if (ctx.upload_counter.* == 0) {
        std.debug.print("MeshRenderer.collect called - camera at ({d:.2}, {d:.2}, {d:.2})\n", .{
            camera_transform.translation.x,
            camera_transform.translation.y,
            camera_transform.translation.z,
        });
    }

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

    var mesh_count: usize = 0;
    var first_transform: ?Transform3d = null;
    var it = query.iterator();
    while (it.next()) |entity| {
        if (entity.get(components.Mesh)) |mesh| {
            mesh_count += 1;
            const transform = entity.get(Transform3d) orelse &Transform3d{};
            if (first_transform == null) first_transform = transform.*;
            const material = entity.get(components.Material) orelse &components.Material{};

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
            });
        }
    }

    // Debug output
    if (ctx.upload_counter.* == 0) {
        std.debug.print("Rendering {} meshes with {} vertices, {} indices\n", .{ mesh_count, all_vertices.items.len, all_indices.items.len });
        if (first_transform) |t| {
            std.debug.print("First mesh transform: pos=({d:.2}, {d:.2}, {d:.2}) scale=({d:.2}, {d:.2}, {d:.2})\n", .{
                t.translation.x,
                t.translation.y,
                t.translation.z,
                t.scale.x,
                t.scale.y,
                t.scale.z,
            });
        }
    }

    // Write mesh data directly to mapped memory
    if (all_vertices.items.len > 0) {
        if (all_vertices.items.len > resources.max_vertices) {
            std.debug.print("ERROR: Too many vertices! Have {}, max is {}\n", .{ all_vertices.items.len, resources.max_vertices });
            return error.TooManyVertices;
        }
        try ctx.writeToMappedBuffer(vkd, components.MeshVertex, resources.vertex_memory, all_vertices.items);
    }

    if (all_indices.items.len > 0) {
        if (all_indices.items.len > resources.max_indices) {
            std.debug.print("ERROR: Too many indices! Have {}, max is {}\n", .{ all_indices.items.len, resources.max_indices });
            return error.TooManyIndices;
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

    vkd.cmdBindPipeline(cmdbuf, .graphics, resources.pipeline);

    const offset = [_]vk.DeviceSize{0};
    vkd.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&resources.vertex_buffer), &offset);
    vkd.cmdBindIndexBuffer(cmdbuf, resources.index_buffer, 0, .uint32);

    var index_offset: u32 = 0;
    for (meshes) |mesh| {
        // Bind texture if available
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

                const write_descriptor = vk.WriteDescriptorSet{
                    .dst_set = descriptor_set,
                    .dst_binding = 0,
                    .dst_array_element = 0,
                    .descriptor_count = 1,
                    .descriptor_type = .combined_image_sampler,
                    .p_image_info = @ptrCast(&image_info),
                    .p_buffer_info = undefined,
                    .p_texel_buffer_view = undefined,
                };

                vkd.updateDescriptorSets(1, @ptrCast(&write_descriptor), 0, undefined);
                vkd.cmdBindDescriptorSets(cmdbuf, .graphics, resources.pipeline_layout, 0, 1, @ptrCast(&descriptor_set), 0, undefined);
            }
        }

        // Push MVP matrix
        vkd.cmdPushConstants(
            cmdbuf,
            resources.pipeline_layout,
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

fn createPipeline(
    vkd: anytype,
    layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
    extent: vk.Extent2D,
) !vk.Pipeline {
    const shaders = @import("shader_imports");
    const vert_spv = shaders.mesh_vert;
    const frag_spv = shaders.mesh_frag;

    const vert_module = try vkd.createShaderModule(&.{
        .code_size = vert_spv.len,
        .p_code = @ptrCast(@alignCast(&vert_spv)),
    }, null);
    defer vkd.destroyShaderModule(vert_module, null);

    const frag_module = try vkd.createShaderModule(&.{
        .code_size = frag_spv.len,
        .p_code = @ptrCast(@alignCast(&frag_spv)),
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
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try vkd.createGraphicsPipelines(.null_handle, 1, @ptrCast(&pipeline_info), null, @ptrCast(&pipeline));

    return pipeline;
}
