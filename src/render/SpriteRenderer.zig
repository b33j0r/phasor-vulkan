// ─────────────────────────────────────────────
// Sprite Renderer
// ─────────────────────────────────────────────
// Renders textured sprites and text with batching by texture.
// Supports depth testing, rotation, scaling, and alpha blending.
// Text is rendered as a special case of sprites using font atlases.

const SpriteRenderer = @This();

const std = @import("std");
const vk = @import("vulkan");
const phasor_common = @import("phasor-common");
const components = @import("../components.zig");
const assets = @import("../assets.zig");
const Transform3d = components.Transform3d;
const ShapeRenderer = @import("ShapeRenderer.zig");
const RenderContext = @import("RenderContext.zig");

/// Sprite batch groups all vertices for sprites sharing the same texture
const SpriteBatch = struct {
    texture: *const assets.Texture,
    vertices: std.ArrayList(components.SpriteVertex),
    vertex_offset: u32 = 0, // Offset into combined vertex buffer
};

/// Temporary state used during collection phase
pub const CollectionState = struct {
    batches: std.ArrayList(SpriteBatch),
    all_vertices: std.ArrayList(components.SpriteVertex),

    pub fn deinit(self: *CollectionState, allocator: std.mem.Allocator) void {
        for (self.batches.items) |*batch| {
            batch.vertices.deinit(allocator);
        }
        self.batches.deinit(allocator);
        self.all_vertices.deinit(allocator);
    }
};

pub fn init(
    vkd: anytype,
    dev_res: anytype,
    render_pass: vk.RenderPass,
    extent: vk.Extent2D,
    allocator: std.mem.Allocator,
) !ShapeRenderer.ShapeResources {
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

    // Create descriptor pool (large enough for many textures)
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

    // Create pipeline layout
    const pipeline_layout = try vkd.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&descriptor_set_layout),
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
    errdefer vkd.destroyPipelineLayout(pipeline_layout, null);

    // Create pipeline
    const pipeline = try createPipeline(vkd, pipeline_layout, render_pass, extent);
    errdefer vkd.destroyPipeline(pipeline, null);

    // Create vertex buffer
    const max_vertices: u32 = 6000; // 1000 sprites * 6 vertices
    const buffer_size = @sizeOf(components.SpriteVertex) * max_vertices;

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
    // Use HOST_VISIBLE memory to avoid staging buffers and sync issues
    const memory = try ctx.allocateMemory(vkd, mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    errdefer vkd.freeMemory(memory, null);

    try vkd.bindBufferMemory(buffer, memory, 0);

    return .{
        .pipeline_layout = pipeline_layout,
        .pipeline = pipeline,
        .vertex_buffer = buffer,
        .vertex_memory = memory,
        .max_vertices = max_vertices,
        .descriptor_set_layout = descriptor_set_layout,
        .descriptor_pool = descriptor_pool,
    };
}

pub fn deinit(vkd: anytype, resources: *const ShapeRenderer.ShapeResources) void {
    vkd.destroyBuffer(resources.vertex_buffer, null);
    vkd.freeMemory(resources.vertex_memory, null);
    vkd.destroyPipeline(resources.pipeline, null);
    vkd.destroyPipelineLayout(resources.pipeline_layout, null);
    if (resources.descriptor_pool) |pool| vkd.destroyDescriptorPool(pool, null);
    if (resources.descriptor_set_layout) |layout| vkd.destroyDescriptorSetLayout(layout, null);
}

pub fn collect(
    vkd: anytype,
    ctx: *RenderContext,
    resources: *const ShapeRenderer.ShapeResources,
    sprite_query: anytype,
    text_query: anytype,
) !CollectionState {
    var state = CollectionState{
        .batches = try std.ArrayList(SpriteBatch).initCapacity(ctx.allocator, 10),
        .all_vertices = try std.ArrayList(components.SpriteVertex).initCapacity(ctx.allocator, 100),
    };
    errdefer state.deinit(ctx.allocator);

    // Collect sprites
    var sprite_it = sprite_query.iterator();
    while (sprite_it.next()) |entity| {
        if (entity.get(components.Sprite3D)) |sprite| {
            const transform = entity.get(Transform3d).?;
            try collectSprite(ctx, &state, sprite, transform);
        }
    }

    // Collect text
    var text_it = text_query.iterator();
    while (text_it.next()) |entity| {
        if (entity.get(components.Text)) |text| {
            const transform = entity.get(Transform3d).?;
            try collectText(ctx, &state, text, transform);
        }
    }

    // Combine all batch vertices and track offsets
    for (state.batches.items) |*batch| {
        batch.vertex_offset = @intCast(state.all_vertices.items.len);
        try state.all_vertices.appendSlice(ctx.allocator, batch.vertices.items);
    }

    // Write vertices directly to mapped memory (no staging buffer)
    if (state.all_vertices.items.len > 0) {
        try ctx.writeToMappedBuffer(vkd, components.SpriteVertex, resources.vertex_memory, state.all_vertices.items);
    }

    return state;
}

pub fn record(
    vkd: anytype,
    ctx: *RenderContext,
    resources: *const ShapeRenderer.ShapeResources,
    cmdbuf: vk.CommandBuffer,
    state: *const CollectionState,
) void {
    _ = ctx;
    if (state.batches.items.len == 0) return;

    vkd.cmdBindPipeline(cmdbuf, .graphics, resources.pipeline);

    // Bind vertex buffer once for all batches
    const offset = [_]vk.DeviceSize{0};
    vkd.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&resources.vertex_buffer), &offset);

    // Draw each batch with its texture
    for (state.batches.items) |batch| {
        if (batch.vertices.items.len == 0) continue;

        const texture = batch.texture;
        if (texture.image_view == null or texture.sampler == null) continue;

        // Create and bind descriptor set for this texture
        var descriptor_set: vk.DescriptorSet = undefined;
        vkd.allocateDescriptorSets(&.{
            .descriptor_pool = resources.descriptor_pool.?,
            .descriptor_set_count = 1,
            .p_set_layouts = @ptrCast(&resources.descriptor_set_layout.?),
        }, @ptrCast(&descriptor_set)) catch continue;

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

        vkd.cmdDraw(cmdbuf, @intCast(batch.vertices.items.len), 1, batch.vertex_offset, 0);
    }
}

// ─────────────────────────────────────────────
// Helper Functions
// ─────────────────────────────────────────────

fn collectSprite(
    ctx: *RenderContext,
    state: *CollectionState,
    sprite: *const components.Sprite3D,
    transform: *const Transform3d,
) !void {
    // Determine sprite size
    var sprite_width: f32 = 1.0;
    var sprite_height: f32 = 1.0;

    switch (sprite.size_mode) {
        .Auto => {
            sprite_width = @floatFromInt(sprite.texture.width);
            sprite_height = @floatFromInt(sprite.texture.height);
        },
        .Manual => |manual| {
            sprite_width = manual.width;
            sprite_height = manual.height;
        },
    }

    const pos = transform.translation;
    const scale = transform.scale;

    // Swap width and height to match texture orientation
    // Texture points up, so its width becomes our height and vice versa
    const half_w = (sprite_height * scale.y) / 2.0;
    const half_h = (sprite_width * scale.x) / 2.0;

    // Rotate in window space before clip space transform
    const rotation = transform.rotation.z;
    const cos_r = @cos(rotation);
    const sin_r = @sin(rotation);

    const p1_window = RenderContext.rotatePoint(-half_w, -half_h, cos_r, sin_r);
    const p2_window = RenderContext.rotatePoint(half_w, -half_h, cos_r, sin_r);
    const p3_window = RenderContext.rotatePoint(half_w, half_h, cos_r, sin_r);
    const p4_window = RenderContext.rotatePoint(-half_w, half_h, cos_r, sin_r);

    const depth = RenderContext.zToDepth(pos.z);
    const color = phasor_common.Color.F32{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };

    // Find or create batch
    var batch = try findOrCreateBatch(ctx, state, sprite.texture);

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

    // Add two triangles forming a quad
    // UV rotated 90° CW: texture pointing up in image → sprite pointing up on screen
    try batch.vertices.append(ctx.allocator, .{ .pos = .{ .x = p1_clip.x, .y = p1_clip.y, .z = depth }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color });
    try batch.vertices.append(ctx.allocator, .{ .pos = .{ .x = p2_clip.x, .y = p2_clip.y, .z = depth }, .uv = .{ .x = 0.0, .y = 0.0 }, .color = color });
    try batch.vertices.append(ctx.allocator, .{ .pos = .{ .x = p3_clip.x, .y = p3_clip.y, .z = depth }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color });

    try batch.vertices.append(ctx.allocator, .{ .pos = .{ .x = p3_clip.x, .y = p3_clip.y, .z = depth }, .uv = .{ .x = 1.0, .y = 0.0 }, .color = color });
    try batch.vertices.append(ctx.allocator, .{ .pos = .{ .x = p4_clip.x, .y = p4_clip.y, .z = depth }, .uv = .{ .x = 1.0, .y = 1.0 }, .color = color });
    try batch.vertices.append(ctx.allocator, .{ .pos = .{ .x = p1_clip.x, .y = p1_clip.y, .z = depth }, .uv = .{ .x = 0.0, .y = 1.0 }, .color = color });
}

fn collectText(
    ctx: *RenderContext,
    state: *CollectionState,
    text: *const components.Text,
    transform: *const Transform3d,
) !void {
    const font = text.font;
    if (font.image == null) return;

    var batch = try findOrCreateBatch(ctx, state, @as(*const assets.Texture, @ptrCast(font)));

    const pos = transform.translation;
    const depth = RenderContext.zToDepth(pos.z);

    const camera_relative_x = pos.x - ctx.camera_offset.x;
    const camera_relative_y = pos.y - ctx.camera_offset.y;

    // First pass: calculate text dimensions for alignment
    var text_width: f32 = 0.0;
    var text_height: f32 = 0.0;
    var min_yoff: f32 = 0.0;
    var max_bottom: f32 = 0.0;

    for (text.text) |ch| {
        if (ch < font.first_char or ch >= font.first_char + font.char_data.len) continue;
        const char_idx = ch - font.first_char;
        const char_data = font.char_data[char_idx];

        text_width += char_data.xadvance;
        min_yoff = @min(min_yoff, char_data.yoff);
        max_bottom = @max(max_bottom, char_data.yoff + (char_data.y1 - char_data.y0));
    }
    text_height = max_bottom - min_yoff;

    // Calculate alignment offsets
    const h_offset: f32 = switch (text.horizontal_alignment) {
        .Left => 0.0,
        .Center => -text_width / 2.0,
        .Right => -text_width,
    };

    const v_offset: f32 = switch (text.vertical_alignment) {
        .Top => -min_yoff,
        .Center => -(min_yoff + text_height / 2.0),
        .Baseline => 0.0,
        .Bottom => -max_bottom,
    };

    var cursor_x: f32 = 0.0;

    for (text.text) |ch| {
        if (ch < font.first_char or ch >= font.first_char + font.char_data.len) continue;

        const char_idx = ch - font.first_char;
        const char_data = font.char_data[char_idx];

        const char_x = camera_relative_x + h_offset + cursor_x + char_data.xoff;
        const char_y = camera_relative_y + v_offset + char_data.yoff;
        const char_w = char_data.x1 - char_data.x0;
        const char_h = char_data.y1 - char_data.y0;

        const atlas_w: f32 = @floatFromInt(font.atlas_width);
        const atlas_h: f32 = @floatFromInt(font.atlas_height);
        const uv0_x = char_data.x0 / atlas_w;
        const uv0_y = char_data.y0 / atlas_h;
        const uv1_x = char_data.x1 / atlas_w;
        const uv1_y = char_data.y1 / atlas_h;

        const p1 = ctx.windowToClip(char_x, char_y);
        const p2 = ctx.windowToClip(char_x + char_w, char_y);
        const p3 = ctx.windowToClip(char_x + char_w, char_y + char_h);
        const p4 = ctx.windowToClip(char_x, char_y + char_h);

        try batch.vertices.append(ctx.allocator, .{ .pos = .{ .x = p1.x, .y = p1.y, .z = depth }, .uv = .{ .x = uv0_x, .y = uv0_y }, .color = text.color });
        try batch.vertices.append(ctx.allocator, .{ .pos = .{ .x = p2.x, .y = p2.y, .z = depth }, .uv = .{ .x = uv1_x, .y = uv0_y }, .color = text.color });
        try batch.vertices.append(ctx.allocator, .{ .pos = .{ .x = p3.x, .y = p3.y, .z = depth }, .uv = .{ .x = uv1_x, .y = uv1_y }, .color = text.color });

        try batch.vertices.append(ctx.allocator, .{ .pos = .{ .x = p3.x, .y = p3.y, .z = depth }, .uv = .{ .x = uv1_x, .y = uv1_y }, .color = text.color });
        try batch.vertices.append(ctx.allocator, .{ .pos = .{ .x = p4.x, .y = p4.y, .z = depth }, .uv = .{ .x = uv0_x, .y = uv1_y }, .color = text.color });
        try batch.vertices.append(ctx.allocator, .{ .pos = .{ .x = p1.x, .y = p1.y, .z = depth }, .uv = .{ .x = uv0_x, .y = uv0_y }, .color = text.color });

        cursor_x += char_data.xadvance;
    }
}

fn findOrCreateBatch(
    ctx: *RenderContext,
    state: *CollectionState,
    texture: *const assets.Texture,
) !*SpriteBatch {
    for (state.batches.items) |*batch| {
        if (batch.texture == texture) {
            return batch;
        }
    }

    try state.batches.append(ctx.allocator, .{
        .texture = texture,
        .vertices = try std.ArrayList(components.SpriteVertex).initCapacity(ctx.allocator, 6),
    });
    return &state.batches.items[state.batches.items.len - 1];
}

fn createPipeline(
    vkd: anytype,
    layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
    extent: vk.Extent2D,
) !vk.Pipeline {
    _ = extent;

    const shaders = @import("shader_imports");
    const vert_spv = shaders.sprite_vert;
    const frag_spv = shaders.sprite_frag;

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
        .stride = @sizeOf(components.SpriteVertex),
        .input_rate = .vertex,
    };

    const vertex_attributes = [_]vk.VertexInputAttributeDescription{
        .{ .binding = 0, .location = 0, .format = .r32g32b32_sfloat, .offset = @offsetOf(components.SpriteVertex, "pos") },
        .{ .binding = 0, .location = 1, .format = .r32g32_sfloat, .offset = @offsetOf(components.SpriteVertex, "uv") },
        .{ .binding = 0, .location = 2, .format = .r32g32b32a32_sfloat, .offset = @offsetOf(components.SpriteVertex, "color") },
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
        .cull_mode = .{}, // No culling for sprites
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
        .depth_write_enable = .false,
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
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try vkd.createGraphicsPipelines(.null_handle, 1, @ptrCast(&pipeline_info), null, @ptrCast(&pipeline));

    return pipeline;
}
