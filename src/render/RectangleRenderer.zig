// ─────────────────────────────────────────────
// Rectangle Renderer
// ─────────────────────────────────────────────
// Renders filled rectangles with optional rotation and scaling.
// Rectangles are positioned in window coordinates with Transform3d.

const RectangleRenderer = @This();

const std = @import("std");
const vk = @import("vulkan");
const phasor_common = @import("phasor-common");
const components = @import("../components.zig");
const Transform3d = components.Transform3d;
const ShapeRenderer = @import("ShapeRenderer.zig");
const RenderContext = @import("RenderContext.zig");

pub fn init(
    vkd: anytype,
    dev_res: anytype,
    color_format: vk.Format,
    depth_format: vk.Format,
    extent: vk.Extent2D,
    allocator: std.mem.Allocator,
) !ShapeRenderer.ShapeResources {
    _ = allocator;

    const pipeline_layout = try vkd.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
    errdefer vkd.destroyPipelineLayout(pipeline_layout, null);

    const pipeline = try createPipeline(vkd, pipeline_layout, color_format, depth_format, extent);
    errdefer vkd.destroyPipeline(pipeline, null);

    const max_vertices: u32 = 6000; // 1000 rectangles * 6 vertices
    const buffer_size = @sizeOf(components.ColorVertex) * max_vertices;

    const buffer = try vkd.createBuffer(&.{
        .size = buffer_size,
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    errdefer vkd.destroyBuffer(buffer, null);

    const mem_reqs = vkd.getBufferMemoryRequirements(buffer);
    const ctx = RenderContext{
        
        .dev_res = dev_res,
        .cmd_pool = undefined,
        .window_width = 0,
        .window_height = 0,
        .camera_offset = .{},
        .allocator = undefined,
        .upload_counter = undefined,
    };
    const memory = try ctx.allocateMemory(vkd, mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    errdefer vkd.freeMemory(memory, null);

    try vkd.bindBufferMemory(buffer, memory, 0);

    return .{
        .pipeline_layout = pipeline_layout,
        .pipeline = pipeline,
        .vertex_buffer = buffer,
        .vertex_memory = memory,
        .max_vertices = max_vertices,
    };
}

pub fn deinit(vkd: anytype, resources: *const ShapeRenderer.ShapeResources) void {
    vkd.destroyBuffer(resources.vertex_buffer, null);
    vkd.freeMemory(resources.vertex_memory, null);
    vkd.destroyPipeline(resources.pipeline, null);
    vkd.destroyPipelineLayout(resources.pipeline_layout, null);
}

pub fn collect(
    vkd: anytype,
    ctx: *RenderContext,
    resources: *const ShapeRenderer.ShapeResources,
    query: anytype,
) !u32 {
    var vertices = try std.ArrayList(components.ColorVertex).initCapacity(ctx.allocator, 100);
    defer vertices.deinit(ctx.allocator);

    var it = query.iterator();
    while (it.next()) |entity| {
        if (entity.get(components.Rectangle)) |rect| {
            const transform = entity.get(Transform3d).?;
            try collectRectangle(ctx, &vertices, rect, transform);
        }
    }

    if (vertices.items.len > 0) {
        try ctx.writeToMappedBuffer(vkd, components.ColorVertex, resources.vertex_memory, vertices.items);
    }

    return @intCast(vertices.items.len);
}

pub fn record(
    vkd: anytype,
    ctx: *RenderContext,
    resources: *const ShapeRenderer.ShapeResources,
    cmdbuf: vk.CommandBuffer,
    vertex_count: u32,
) void {
    _ = ctx;
    if (vertex_count == 0) return;

    vkd.cmdBindPipeline(cmdbuf, .graphics, resources.pipeline);
    const offset = [_]vk.DeviceSize{0};
    vkd.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&resources.vertex_buffer), &offset);
    vkd.cmdDraw(cmdbuf, vertex_count, 1, 0, 0);
}

fn collectRectangle(
    ctx: *RenderContext,
    vertices: *std.ArrayList(components.ColorVertex),
    rect: *const components.Rectangle,
    transform: *const Transform3d,
) !void {
    const pos = transform.translation;
    const scale = transform.scale;
    const rotation = transform.rotation.z;

    // Apply transform scale to rectangle size
    const half_w = (rect.width * scale.x) / 2.0;
    const half_h = (rect.height * scale.y) / 2.0;

    // Rotate in window space before clip space transform (same as sprites)
    const cos_r = @cos(rotation);
    const sin_r = @sin(rotation);

    const p1_window = RenderContext.rotatePoint(-half_w, -half_h, cos_r, sin_r);
    const p2_window = RenderContext.rotatePoint(half_w, -half_h, cos_r, sin_r);
    const p3_window = RenderContext.rotatePoint(half_w, half_h, cos_r, sin_r);
    const p4_window = RenderContext.rotatePoint(-half_w, half_h, cos_r, sin_r);

    const depth = RenderContext.zToDepth(pos.z);

    // Apply camera offset and transform to clip space
    const camera_relative_x = pos.x - ctx.camera_offset.x;
    const camera_relative_y = pos.y - ctx.camera_offset.y;

    const toClip = struct {
        fn f(wx: f32, wy: f32, px: f32, py: f32, ww: f32, wh: f32) struct { x: f32, y: f32 } {
            return .{
                .x = (px + wx) / (ww / 2.0),
                .y = (py + wy) / (wh / 2.0),
            };
        }
    }.f;

    const p1_clip = toClip(p1_window.x, p1_window.y, camera_relative_x, camera_relative_y, ctx.window_width, ctx.window_height);
    const p2_clip = toClip(p2_window.x, p2_window.y, camera_relative_x, camera_relative_y, ctx.window_width, ctx.window_height);
    const p3_clip = toClip(p3_window.x, p3_window.y, camera_relative_x, camera_relative_y, ctx.window_width, ctx.window_height);
    const p4_clip = toClip(p4_window.x, p4_window.y, camera_relative_x, camera_relative_y, ctx.window_width, ctx.window_height);

    const p1 = phasor_common.Vec3{ .x = p1_clip.x, .y = p1_clip.y, .z = depth };
    const p2 = phasor_common.Vec3{ .x = p2_clip.x, .y = p2_clip.y, .z = depth };
    const p3 = phasor_common.Vec3{ .x = p3_clip.x, .y = p3_clip.y, .z = depth };
    const p4 = phasor_common.Vec3{ .x = p4_clip.x, .y = p4_clip.y, .z = depth };

    // Two triangles forming a quad
    try vertices.append(ctx.allocator, .{ .pos = p1, .color = rect.color });
    try vertices.append(ctx.allocator, .{ .pos = p2, .color = rect.color });
    try vertices.append(ctx.allocator, .{ .pos = p3, .color = rect.color });

    try vertices.append(ctx.allocator, .{ .pos = p3, .color = rect.color });
    try vertices.append(ctx.allocator, .{ .pos = p4, .color = rect.color });
    try vertices.append(ctx.allocator, .{ .pos = p1, .color = rect.color });
}

fn createPipeline(
    vkd: anytype,
    layout: vk.PipelineLayout,
    color_format: vk.Format,
    depth_format: vk.Format,
    extent: vk.Extent2D,
) !vk.Pipeline {
    _ = extent;
    _ = depth_format;

    const shaders = @import("shader_imports");
    const vert_spv = shaders.rectangle_vert;
    const frag_spv = shaders.rectangle_frag;

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
        .stride = @sizeOf(components.ColorVertex),
        .input_rate = .vertex,
    };

    const vertex_attributes = [_]vk.VertexInputAttributeDescription{
        .{ .binding = 0, .location = 0, .format = .r32g32b32_sfloat, .offset = @offsetOf(components.ColorVertex, "pos") },
        .{ .binding = 0, .location = 1, .format = .r32g32b32a32_sfloat, .offset = @offsetOf(components.ColorVertex, "color") },
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

    const viewport_state = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = undefined,
        .scissor_count = 1,
        .p_scissors = undefined,
    };

    const rasterization = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false,
        .rasterizer_discard_enable = .false,
        .polygon_mode = .fill,
        .cull_mode = .{},
        .front_face = .clockwise,
        .depth_bias_enable = .false,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const multisample = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = .false,
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    const color_blend_attachment = vk.PipelineColorBlendAttachmentState{
        .blend_enable = .true,
        .src_color_blend_factor = .src_alpha,
        .dst_color_blend_factor = .one_minus_src_alpha,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const color_blend = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_blend_attachment),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
        .depth_test_enable = .true,
        .depth_write_enable = .true,
        .depth_compare_op = .greater,
        .depth_bounds_test_enable = .false,
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
        .min_depth_bounds = 0.0,
        .max_depth_bounds = 1.0,
    };

    const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };
    const dynamic_state = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynamic_states.len,
        .p_dynamic_states = &dynamic_states,
    };

    var rendering_info = vk.PipelineRenderingCreateInfo{
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachment_formats = @ptrCast(&color_format),
        .depth_attachment_format = .undefined,
        .stencil_attachment_format = .undefined,
    };

    const pipeline_info = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &shader_stages,
        .p_vertex_input_state = &vertex_input,
        .p_input_assembly_state = &input_assembly,
        .p_tessellation_state = null,
        .p_viewport_state = &viewport_state,
        .p_rasterization_state = &rasterization,
        .p_multisample_state = &multisample,
        .p_depth_stencil_state = &depth_stencil,
        .p_color_blend_state = &color_blend,
        .p_dynamic_state = &dynamic_state,
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
