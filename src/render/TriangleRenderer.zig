// ─────────────────────────────────────────────
// Triangle Renderer
// ─────────────────────────────────────────────
// Renders colored triangles using the basic triangle pipeline.
// Triangles use 2D clip-space coordinates directly.

const TriangleRenderer = @This();

const std = @import("std");
const vk = @import("vulkan");
const components = @import("../components.zig");
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

    // Create pipeline layout (no descriptor sets)
    const pipeline_layout = try vkd.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
    errdefer vkd.destroyPipelineLayout(pipeline_layout, null);

    // Create graphics pipeline
    const pipeline = try createPipeline(vkd, pipeline_layout, color_format, depth_format, extent);
    errdefer vkd.destroyPipeline(pipeline, null);

    // Create vertex buffer
    const max_vertices: u32 = 3000;
    const buffer_size = @sizeOf(components.Vertex) * max_vertices;

    const buffer = try vkd.createBuffer(&.{
        .size = buffer_size,
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    errdefer vkd.destroyBuffer(buffer, null);

    const mem_reqs = vkd.getBufferMemoryRequirements(buffer);
    const ctx = RenderContext{
        .dev_res = dev_res,
        .cmd_pool = undefined, // Not needed for init
        .window_width = 0,
        .window_height = 0,
        .camera_offset = .{},
        .allocator = undefined,
        .upload_counter = undefined, // Not needed for init
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
    var vertices = try std.ArrayList(components.Vertex).initCapacity(ctx.allocator, 100);
    defer vertices.deinit(ctx.allocator);

    var it = query.iterator();
    while (it.next()) |entity| {
        if (entity.get(components.Triangle)) |tri| {
            try vertices.appendSlice(ctx.allocator, &tri.vertices);
        }
    }

    if (vertices.items.len > 0) {
        try ctx.writeToMappedBuffer(vkd, components.Vertex, resources.vertex_memory, vertices.items);
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
    const vert_spv = shaders.triangle_vert;
    const frag_spv = shaders.triangle_frag;

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
        .stride = @sizeOf(components.Vertex),
        .input_rate = .vertex,
    };

    const vertex_attributes = [_]vk.VertexInputAttributeDescription{
        .{ .binding = 0, .location = 0, .format = .r32g32_sfloat, .offset = @offsetOf(components.Vertex, "pos") },
        .{ .binding = 0, .location = 1, .format = .r32g32b32_sfloat, .offset = @offsetOf(components.Vertex, "color") },
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
        .p_viewports = undefined, // Dynamic
        .scissor_count = 1,
        .p_scissors = undefined, // Dynamic
    };

    const rasterization = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false,
        .rasterizer_discard_enable = .false,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
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
        .blend_enable = .false,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
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

    const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };
    const dynamic_state = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynamic_states.len,
        .p_dynamic_states = &dynamic_states,
    };

    // Dynamic rendering info (Vulkan 1.3)
    var rendering_info = vk.PipelineRenderingCreateInfo{
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachment_formats = @ptrCast(&color_format),
        .depth_attachment_format = .undefined, // Triangles don't use depth
        .stencil_attachment_format = .undefined,
    };

    const pipeline_info = vk.GraphicsPipelineCreateInfo{
        .p_next = &rendering_info,
        .flags = .{},
        .stage_count = 2,
        .p_stages = &shader_stages,
        .p_vertex_input_state = &vertex_input,
        .p_input_assembly_state = &input_assembly,
        .p_tessellation_state = null,
        .p_viewport_state = &viewport_state,
        .p_rasterization_state = &rasterization,
        .p_multisample_state = &multisample,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &color_blend,
        .p_dynamic_state = &dynamic_state,
        .layout = layout,
        .render_pass = .null_handle,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try vkd.createGraphicsPipelines(.null_handle, 1, @ptrCast(&pipeline_info), null, @ptrCast(&pipeline));

    return pipeline;
}
