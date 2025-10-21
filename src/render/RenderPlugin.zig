const RenderPlugin = @This();

pub fn build(self: *RenderPlugin, app: *App) !void {
    _ = self;
    // VulkanPlugin creates precise schedules; we only register systems to them.
    try app.addSystem("VkRenderInit", init_system);
    try app.addSystem("VkRenderUpdate", handle_resize_system);
    try app.addSystem("VkRender", render_system);
    try app.addSystem("VkRenderDeinit", deinit_system);
}

pub const RenderResource = struct {
    allocator: std.mem.Allocator,

    // Render pass and framebuffers
    render_pass: vk.RenderPass,
    framebuffers: []vk.Framebuffer,

    // Command resources
    cmd_pool: vk.CommandPool,
    cmd_buffers: []vk.CommandBuffer,

    // Synchronization primitives
    image_available: []vk.Semaphore,
    render_finished: []vk.Semaphore,
    in_flight: []vk.Fence,

    // Triangle pipeline
    pipeline_layout: vk.PipelineLayout,
    pipeline: vk.Pipeline,
    vertex_buffer: vk.Buffer,
    vertex_memory: vk.DeviceMemory,
    max_vertices: u32,

    // Sprite pipeline
    sprite_descriptor_set_layout: vk.DescriptorSetLayout,
    sprite_descriptor_pool: vk.DescriptorPool,
    sprite_pipeline_layout: vk.PipelineLayout,
    sprite_pipeline: vk.Pipeline,
    sprite_vertex_buffer: vk.Buffer,
    sprite_vertex_memory: vk.DeviceMemory,
    max_sprite_vertices: u32,
};

fn init_system(commands: *Commands, r_device: ResOpt(DeviceResource), r_swap: ResOpt(SwapchainResource), r_clear: ResOpt(ClearColor)) !void {
    const dev_res = r_device.ptr orelse return error.MissingDeviceResource;
    const vkd = dev_res.device_proxy orelse return error.MissingDevice;
    const swap = r_swap.ptr orelse return error.MissingSwapchainResource;
    const allocator = std.heap.page_allocator;

    // Ensure ClearColor exists
    if (r_clear.ptr == null) {
        try commands.insertResource(ClearColor{});
    }

    // Create render pass
    const render_pass = try createRenderPass(vkd, swap.surface_format.format);
    errdefer vkd.destroyRenderPass(render_pass, null);

    // Create framebuffers
    const framebuffers = try createFramebuffers(allocator, vkd, render_pass, swap);
    errdefer destroyFramebuffers(vkd, allocator, framebuffers);

    // Create command pool and buffers
    const cmd_pool = try vkd.createCommandPool(&.{
        .queue_family_index = dev_res.graphics_family_index.?,
        .flags = .{ .reset_command_buffer_bit = true },
    }, null);
    errdefer vkd.destroyCommandPool(cmd_pool, null);

    const cmd_buffers = try allocateCommandBuffers(allocator, vkd, cmd_pool, @intCast(swap.views.len));
    errdefer freeCommandBuffers(vkd, cmd_pool, allocator, cmd_buffers);

    // Create synchronization objects
    const sync = try createSyncObjects(allocator, vkd, @intCast(swap.views.len));
    errdefer destroySyncObjects(vkd, allocator, sync);

    // Create graphics pipeline
    const pipeline_layout = try vkd.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
    errdefer vkd.destroyPipelineLayout(pipeline_layout, null);

    const pipeline = try createGraphicsPipeline(vkd, pipeline_layout, render_pass, swap.extent);
    errdefer vkd.destroyPipeline(pipeline, null);

    // Create vertex buffer
    const max_vertices: u32 = 3000;
    const vertex_buffer_info = try createVertexBuffer(vkd, dev_res, max_vertices);
    errdefer {
        vkd.destroyBuffer(vertex_buffer_info.buffer, null);
        vkd.freeMemory(vertex_buffer_info.memory, null);
    }

    // Create sprite descriptor set layout
    const sampler_binding = vk.DescriptorSetLayoutBinding{
        .binding = 0,
        .descriptor_type = .combined_image_sampler,
        .descriptor_count = 1,
        .stage_flags = .{ .fragment_bit = true },
        .p_immutable_samplers = null,
    };

    const sprite_descriptor_set_layout = try vkd.createDescriptorSetLayout(&.{
        .binding_count = 1,
        .p_bindings = @ptrCast(&sampler_binding),
    }, null);
    errdefer vkd.destroyDescriptorSetLayout(sprite_descriptor_set_layout, null);

    // Create sprite descriptor pool (large enough for many textures)
    const pool_size = vk.DescriptorPoolSize{
        .type = .combined_image_sampler,
        .descriptor_count = 100, // Support up to 100 textures
    };

    const sprite_descriptor_pool = try vkd.createDescriptorPool(&.{
        .pool_size_count = 1,
        .p_pool_sizes = @ptrCast(&pool_size),
        .max_sets = 100,
    }, null);
    errdefer vkd.destroyDescriptorPool(sprite_descriptor_pool, null);

    // Create sprite pipeline layout
    const sprite_pipeline_layout = try vkd.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&sprite_descriptor_set_layout),
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
    errdefer vkd.destroyPipelineLayout(sprite_pipeline_layout, null);

    // Create sprite pipeline
    const sprite_pipeline = try createSpritePipeline(vkd, sprite_pipeline_layout, render_pass, swap.extent);
    errdefer vkd.destroyPipeline(sprite_pipeline, null);

    // Create sprite vertex buffer
    const max_sprite_vertices: u32 = 6000; // 1000 sprites * 6 vertices
    const sprite_vertex_buffer_info = try createSpriteVertexBuffer(vkd, dev_res, max_sprite_vertices);
    errdefer {
        vkd.destroyBuffer(sprite_vertex_buffer_info.buffer, null);
        vkd.freeMemory(sprite_vertex_buffer_info.memory, null);
    }

    try commands.insertResource(RenderResource{
        .allocator = allocator,
        .render_pass = render_pass,
        .framebuffers = framebuffers,
        .cmd_pool = cmd_pool,
        .cmd_buffers = cmd_buffers,
        .image_available = sync.image_available,
        .render_finished = sync.render_finished,
        .in_flight = sync.in_flight,
        .pipeline_layout = pipeline_layout,
        .pipeline = pipeline,
        .vertex_buffer = vertex_buffer_info.buffer,
        .vertex_memory = vertex_buffer_info.memory,
        .max_vertices = max_vertices,
        .sprite_descriptor_set_layout = sprite_descriptor_set_layout,
        .sprite_descriptor_pool = sprite_descriptor_pool,
        .sprite_pipeline_layout = sprite_pipeline_layout,
        .sprite_pipeline = sprite_pipeline,
        .sprite_vertex_buffer = sprite_vertex_buffer_info.buffer,
        .sprite_vertex_memory = sprite_vertex_buffer_info.memory,
        .max_sprite_vertices = max_sprite_vertices,
    });

    std.log.info("Vulkan RenderPlugin: initialized", .{});
}

fn handle_resize_system(
    commands: *Commands,
    r_device: ResOpt(DeviceResource),
    r_swap: ResOpt(SwapchainResource),
    r_render: ResOpt(RenderResource),
    event_reader: EventReader(phasor_common.WindowResized),
) !void {
    // Check if there's a resize event
    const resize_event = event_reader.tryRecv() orelse return;

    std.log.info("Vulkan RenderPlugin: handling window resize to {d}x{d}", .{ resize_event.width, resize_event.height });

    const dev_res = r_device.ptr orelse return;
    const vkd = dev_res.device_proxy orelse return;
    const swap = r_swap.ptr orelse return;
    const rr = r_render.ptr orelse return;

    // Wait for device to be idle before recreating framebuffers
    try vkd.deviceWaitIdle();

    // Destroy old framebuffers
    destroyFramebuffers(vkd, rr.allocator, rr.framebuffers);

    // Recreate framebuffers with new swapchain dimensions
    const new_framebuffers = try createFramebuffers(rr.allocator, vkd, rr.render_pass, swap);

    // Update render resource with new framebuffers
    var updated_resource = rr.*;
    updated_resource.framebuffers = new_framebuffers;
    try commands.insertResource(updated_resource);

    std.log.info("Vulkan RenderPlugin: framebuffers recreated", .{});
}

const SyncObjects = struct {
    image_available: []vk.Semaphore,
    render_finished: []vk.Semaphore,
    in_flight: []vk.Fence,
};

fn createSyncObjects(allocator: std.mem.Allocator, vkd: anytype, count: u32) !SyncObjects {
    const image_available = try allocator.alloc(vk.Semaphore, count);
    errdefer allocator.free(image_available);

    const render_finished = try allocator.alloc(vk.Semaphore, count);
    errdefer allocator.free(render_finished);

    const in_flight = try allocator.alloc(vk.Fence, count);
    errdefer allocator.free(in_flight);

    for (image_available) |*s| s.* = try vkd.createSemaphore(&.{}, null);
    for (render_finished) |*s| s.* = try vkd.createSemaphore(&.{}, null);
    for (in_flight) |*f| f.* = try vkd.createFence(&.{ .flags = .{ .signaled_bit = true } }, null);

    return .{
        .image_available = image_available,
        .render_finished = render_finished,
        .in_flight = in_flight,
    };
}

fn destroySyncObjects(vkd: anytype, allocator: std.mem.Allocator, sync: SyncObjects) void {
    for (sync.in_flight) |f| vkd.destroyFence(f, null);
    for (sync.image_available) |s| vkd.destroySemaphore(s, null);
    for (sync.render_finished) |s| vkd.destroySemaphore(s, null);
    allocator.free(sync.in_flight);
    allocator.free(sync.image_available);
    allocator.free(sync.render_finished);
}

fn createRenderPass(vkd: anytype, format: vk.Format) !vk.RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .format = format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };

    const color_ref = vk.AttachmentReference{ .attachment = 0, .layout = .color_attachment_optimal };

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_ref),
    };

    return try vkd.createRenderPass(&.{
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_attachment),
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
    }, null);
}

fn createFramebuffers(allocator: std.mem.Allocator, vkd: anytype, render_pass: vk.RenderPass, swap: *const SwapchainResource) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swap.views.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |fb| vkd.destroyFramebuffer(fb, null);

    for (framebuffers, 0..) |*fb, idx| {
        fb.* = try vkd.createFramebuffer(&.{
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&swap.views[idx]),
            .width = swap.extent.width,
            .height = swap.extent.height,
            .layers = 1,
        }, null);
        i += 1;
    }

    return framebuffers;
}

fn destroyFramebuffers(vkd: anytype, allocator: std.mem.Allocator, framebuffers: []const vk.Framebuffer) void {
    for (framebuffers) |fb| vkd.destroyFramebuffer(fb, null);
    allocator.free(framebuffers);
}

fn allocateCommandBuffers(allocator: std.mem.Allocator, vkd: anytype, pool: vk.CommandPool, count: u32) ![]vk.CommandBuffer {
    const cmdbufs = try allocator.alloc(vk.CommandBuffer, count);
    errdefer allocator.free(cmdbufs);

    try vkd.allocateCommandBuffers(&.{ .command_pool = pool, .level = .primary, .command_buffer_count = count }, cmdbufs.ptr);

    return cmdbufs;
}

fn freeCommandBuffers(vkd: anytype, pool: vk.CommandPool, allocator: std.mem.Allocator, cmdbufs: []vk.CommandBuffer) void {
    vkd.freeCommandBuffers(pool, @intCast(cmdbufs.len), cmdbufs.ptr);
    allocator.free(cmdbufs);
}

const VertexBufferInfo = struct {
    buffer: vk.Buffer,
    memory: vk.DeviceMemory,
};

fn createVertexBuffer(vkd: anytype, dev_res: *const DeviceResource, max_vertices: u32) !VertexBufferInfo {
    const buffer_size = @sizeOf(components.Vertex) * max_vertices;

    const buffer = try vkd.createBuffer(&.{
        .size = buffer_size,
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    errdefer vkd.destroyBuffer(buffer, null);

    const mem_reqs = vkd.getBufferMemoryRequirements(buffer);
    const memory = try allocateMemory(vkd, dev_res, mem_reqs, .{ .device_local_bit = true });
    errdefer vkd.freeMemory(memory, null);

    try vkd.bindBufferMemory(buffer, memory, 0);

    return .{ .buffer = buffer, .memory = memory };
}

fn createGraphicsPipeline(vkd: anytype, layout: vk.PipelineLayout, render_pass: vk.RenderPass, extent: vk.Extent2D) !vk.Pipeline {
    _ = extent;

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
        .p_depth_stencil_state = null,
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

fn createSpritePipeline(vkd: anytype, layout: vk.PipelineLayout, render_pass: vk.RenderPass, extent: vk.Extent2D) !vk.Pipeline {
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
        .{ .binding = 0, .location = 0, .format = .r32g32_sfloat, .offset = @offsetOf(components.SpriteVertex, "pos") },
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

    // Enable alpha blending for transparency
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
        .p_depth_stencil_state = null,
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

fn createSpriteVertexBuffer(vkd: anytype, dev_res: *const DeviceResource, max_vertices: u32) !VertexBufferInfo {
    const buffer_size = @sizeOf(components.SpriteVertex) * max_vertices;

    const buffer = try vkd.createBuffer(&.{
        .size = buffer_size,
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    errdefer vkd.destroyBuffer(buffer, null);

    const mem_reqs = vkd.getBufferMemoryRequirements(buffer);
    const memory = try allocateMemory(vkd, dev_res, mem_reqs, .{ .device_local_bit = true });
    errdefer vkd.freeMemory(memory, null);

    try vkd.bindBufferMemory(buffer, memory, 0);

    return .{ .buffer = buffer, .memory = memory };
}

fn allocateMemory(vkd: anytype, dev_res: *const DeviceResource, requirements: vk.MemoryRequirements, properties: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    const mem_props = dev_res.memory_properties;

    var i: u32 = 0;
    while (i < mem_props.memory_type_count) : (i += 1) {
        if ((requirements.memory_type_bits & (@as(u32, 1) << @intCast(i))) != 0) {
            const type_props = mem_props.memory_types[i].property_flags;

            // Check if all required properties are present
            const has_host_visible = type_props.host_visible_bit or !properties.host_visible_bit;
            const has_host_coherent = type_props.host_coherent_bit or !properties.host_coherent_bit;
            const has_device_local = type_props.device_local_bit or !properties.device_local_bit;

            if (has_host_visible and has_host_coherent and has_device_local) {
                return try vkd.allocateMemory(&.{
                    .allocation_size = requirements.size,
                    .memory_type_index = i,
                }, null);
            }
        }
    }
    return error.NoSuitableMemoryType;
}

fn render_system(
    commands: *Commands,
    r_device: ResOpt(DeviceResource),
    r_swap: ResOpt(SwapchainResource),
    r_bounds: ResOpt(RenderBounds),
    r_rend: ResOpt(RenderResource),
    r_clear: ResOpt(ClearColor),
    q_triangles: Query(.{components.Triangle}),
    q_sprites: Query(.{ components.Sprite3D, Transform3d }),
    q_cameras: Query(.{components.Camera3d}),
) !void {
    _ = r_bounds;
    _ = commands;

    const dev_res = r_device.ptr orelse return;
    const vkd = dev_res.device_proxy orelse return;
    const gfx_q = dev_res.graphics_queue.?;
    const present_q = dev_res.present_queue.?;
    const swap = r_swap.ptr orelse return;
    const rr = r_rend.ptr orelse return;
    const clear_color = if (r_clear.ptr) |cc| cc.* else ClearColor{};

    // Find active camera to determine coordinate system
    var camera_mode: ?components.Camera3d = null;
    var cam_it = q_cameras.iterator();
    if (cam_it.next()) |cam_entity| {
        if (cam_entity.get(components.Camera3d)) |cam| {
            camera_mode = cam.*;
        }
    }

    // Acquire next image
    const next_image_sem = rr.image_available[0];
    const acquire = try vkd.acquireNextImageKHR(swap.swapchain.?, std.math.maxInt(u64), next_image_sem, .null_handle);

    switch (acquire.result) {
        .success, .suboptimal_khr => {},
        .error_out_of_date_khr => return,
        else => return error.ImageAcquireFailed,
    }

    const img_idx: usize = @intCast(acquire.image_index);

    // Collect triangle vertices from ECS
    var vertices = try std.ArrayList(components.Vertex).initCapacity(rr.allocator, 100);
    defer vertices.deinit(rr.allocator);

    var it = q_triangles.iterator();
    while (it.next()) |entity| {
        if (entity.get(components.Triangle)) |tri| {
            try vertices.appendSlice(rr.allocator, &tri.vertices);
        }
    }

    // Upload vertices to GPU if any exist
    if (vertices.items.len > 0) {
        try uploadVertices(vkd, dev_res, rr.cmd_pool, rr.vertex_buffer, vertices.items);
    }

    // Collect sprite vertices from ECS
    var sprite_vertices = try std.ArrayList(components.SpriteVertex).initCapacity(rr.allocator, 100);
    defer sprite_vertices.deinit(rr.allocator);

    // Calculate viewport dimensions for coordinate transformation
    const viewport_width: f32 = @floatFromInt(swap.extent.width);
    const viewport_height: f32 = @floatFromInt(swap.extent.height);

    var sprite_it = q_sprites.iterator();
    while (sprite_it.next()) |entity| {
        if (entity.get(components.Sprite3D)) |sprite| {
            // Determine sprite size based on size_mode
            var sprite_width: f32 = 1.0;
            var sprite_height: f32 = 1.0;

            switch (sprite.size_mode) {
                .Auto => {
                    // Use texture dimensions for pixel-perfect rendering
                    sprite_width = @floatFromInt(sprite.texture.width);
                    sprite_height = @floatFromInt(sprite.texture.height);
                },
                .Manual => |manual| {
                    sprite_width = manual.width;
                    sprite_height = manual.height;
                },
            }

            // Get transform if available, otherwise use identity
            const transform = entity.get(Transform3d) orelse &Transform3d{};
            const pos = transform.translation;
            const scale = transform.scale;

            // Apply scale to sprite size
            const half_w = (sprite_width * scale[0]) / 2.0;
            const half_h = (sprite_height * scale[1]) / 2.0;

            const color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 }; // White tint

            // Transform to clip space based on camera mode
            var clip_x: f32 = pos[0];
            var clip_y: f32 = pos[1];
            var clip_half_w: f32 = half_w;
            var clip_half_h: f32 = half_h;

            if (camera_mode) |cam| {
                switch (cam) {
                    .Viewport => |vp| {
                        // Transform from pixel/screen space to clip space [-1, 1]
                        switch (vp.mode) {
                            .Center => {
                                // Center mode: (0,0) is center, y increases upwards
                                // Transform to NDC: x/halfWidth, y/halfHeight
                                clip_x = pos[0] / (viewport_width / 2.0);
                                clip_y = pos[1] / (viewport_height / 2.0);
                                clip_half_w = half_w / (viewport_width / 2.0);
                                clip_half_h = half_h / (viewport_height / 2.0);
                            },
                            .TopLeft => {
                                // TopLeft mode: (0,0) is top-left, y increases downwards
                                // Transform: (x,y) -> (2*x/width - 1, 1 - 2*y/height)
                                clip_x = 2.0 * pos[0] / viewport_width - 1.0;
                                clip_y = 1.0 - 2.0 * pos[1] / viewport_height;
                                clip_half_w = half_w / (viewport_width / 2.0);
                                clip_half_h = half_h / (viewport_height / 2.0);
                            },
                        }
                    },
                    .Orthographic => |ortho| {
                        // Transform using orthographic bounds
                        const width = ortho.right - ortho.left;
                        const height = ortho.top - ortho.bottom;
                        clip_x = (pos[0] - ortho.left) / (width / 2.0) - 1.0;
                        clip_y = (pos[1] - ortho.bottom) / (height / 2.0) - 1.0;
                        clip_half_w = half_w / (width / 2.0);
                        clip_half_h = half_h / (height / 2.0);
                    },
                    .Perspective => {
                        // Perspective projection not implemented for sprites yet
                        // Use identity transform
                    },
                }
            }

            // Generate quad (2 triangles = 6 vertices) in clip space
            // Triangle 1
            try sprite_vertices.append(rr.allocator, .{ .pos = .{ clip_x - clip_half_w, clip_y - clip_half_h }, .uv = .{ 0.0, 0.0 }, .color = color });
            try sprite_vertices.append(rr.allocator, .{ .pos = .{ clip_x + clip_half_w, clip_y - clip_half_h }, .uv = .{ 1.0, 0.0 }, .color = color });
            try sprite_vertices.append(rr.allocator, .{ .pos = .{ clip_x + clip_half_w, clip_y + clip_half_h }, .uv = .{ 1.0, 1.0 }, .color = color });

            // Triangle 2
            try sprite_vertices.append(rr.allocator, .{ .pos = .{ clip_x + clip_half_w, clip_y + clip_half_h }, .uv = .{ 1.0, 1.0 }, .color = color });
            try sprite_vertices.append(rr.allocator, .{ .pos = .{ clip_x - clip_half_w, clip_y + clip_half_h }, .uv = .{ 0.0, 1.0 }, .color = color });
            try sprite_vertices.append(rr.allocator, .{ .pos = .{ clip_x - clip_half_w, clip_y - clip_half_h }, .uv = .{ 0.0, 0.0 }, .color = color });
        }
    }

    // Upload sprite vertices to GPU if any exist
    if (sprite_vertices.items.len > 0) {
        try uploadSpriteVertices(vkd, dev_res, rr.cmd_pool, rr.sprite_vertex_buffer, sprite_vertices.items);
    }

    // Collect all unique textures from sprites for descriptor set creation
    var texture_descriptors = try std.ArrayList(*const assets.Texture).initCapacity(rr.allocator, 10);
    defer texture_descriptors.deinit(rr.allocator);

    var tex_sprite_it = q_sprites.iterator();
    while (tex_sprite_it.next()) |entity| {
        if (entity.get(components.Sprite3D)) |sprite| {
            // For simplicity, assume one texture for now
            var found = false;
            for (texture_descriptors.items) |tex| {
                if (tex == sprite.texture) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try texture_descriptors.append(rr.allocator, sprite.texture);
            }
        }
    }

    // Reset descriptor pool for this frame
    try vkd.resetDescriptorPool(rr.sprite_descriptor_pool, .{});

    // Record command buffer
    try recordCommandBuffer(vkd, rr, swap, img_idx, clear_color, @intCast(vertices.items.len), @intCast(sprite_vertices.items.len), texture_descriptors.items);

    // Submit
    const wait_stages = [_]vk.PipelineStageFlags{.{ .color_attachment_output_bit = true }};
    const submit = vk.SubmitInfo{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&next_image_sem),
        .p_wait_dst_stage_mask = &wait_stages,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&rr.cmd_buffers[img_idx]),
        .signal_semaphore_count = 1,
        .p_signal_semaphores = @ptrCast(&rr.render_finished[img_idx]),
    };
    try vkd.queueSubmit(gfx_q, 1, @ptrCast(&submit), .null_handle);

    // Present
    const sc = swap.swapchain.?;
    var present_img_idx: u32 = acquire.image_index;
    const present_info = vk.PresentInfoKHR{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&rr.render_finished[img_idx]),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&sc),
        .p_image_indices = @ptrCast(&present_img_idx),
        .p_results = null,
    };
    _ = try vkd.queuePresentKHR(present_q, &present_info);

    // Simple synchronization: wait for queue idle
    try vkd.queueWaitIdle(present_q);
}

fn recordCommandBuffer(
    vkd: anytype,
    rr: *const RenderResource,
    swap: *const SwapchainResource,
    img_idx: usize,
    clear_color: ClearColor,
    vertex_count: u32,
    sprite_vertex_count: u32,
    textures: []const *const assets.Texture,
) !void {
    const cmdbuf = rr.cmd_buffers[img_idx];

    try vkd.resetCommandBuffer(cmdbuf, .{});
    try vkd.beginCommandBuffer(cmdbuf, &.{});

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swap.extent.width),
        .height = @floatFromInt(swap.extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swap.extent,
    };

    vkd.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(&viewport));
    vkd.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(&scissor));

    const clear_f32 = phasor_common.Color.F32.fromColor(clear_color.color);
    const clear_value = vk.ClearValue{
        .color = .{ .float_32 = .{ clear_f32.r, clear_f32.g, clear_f32.b, clear_f32.a } },
    };

    vkd.cmdBeginRenderPass(cmdbuf, &.{
        .render_pass = rr.render_pass,
        .framebuffer = rr.framebuffers[img_idx],
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = swap.extent },
        .clear_value_count = 1,
        .p_clear_values = @ptrCast(&clear_value),
    }, .@"inline");

    // Draw triangles
    if (vertex_count > 0) {
        vkd.cmdBindPipeline(cmdbuf, .graphics, rr.pipeline);
        const offset = [_]vk.DeviceSize{0};
        vkd.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&rr.vertex_buffer), &offset);
        vkd.cmdDraw(cmdbuf, vertex_count, 1, 0, 0);
    }

    // Draw sprites
    if (sprite_vertex_count > 0 and textures.len > 0) {
        vkd.cmdBindPipeline(cmdbuf, .graphics, rr.sprite_pipeline);

        // For simplicity, use the first texture for all sprites for now
        const texture = textures[0];
        if (texture.image_view) |view| {
            if (texture.sampler) |sampler| {
                // Create a descriptor set for this texture
                var descriptor_set: vk.DescriptorSet = undefined;
                try vkd.allocateDescriptorSets(&.{
                    .descriptor_pool = rr.sprite_descriptor_pool,
                    .descriptor_set_count = 1,
                    .p_set_layouts = @ptrCast(&rr.sprite_descriptor_set_layout),
                }, @ptrCast(&descriptor_set));

                // Update descriptor set
                const image_info = vk.DescriptorImageInfo{
                    .sampler = sampler,
                    .image_view = view,
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

                // Bind descriptor set and draw
                vkd.cmdBindDescriptorSets(cmdbuf, .graphics, rr.sprite_pipeline_layout, 0, 1, @ptrCast(&descriptor_set), 0, undefined);

                const sprite_offset = [_]vk.DeviceSize{0};
                vkd.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&rr.sprite_vertex_buffer), &sprite_offset);
                vkd.cmdDraw(cmdbuf, sprite_vertex_count, 1, 0, 0);
            }
        }
    }

    vkd.cmdEndRenderPass(cmdbuf);
    try vkd.endCommandBuffer(cmdbuf);
}

fn uploadVertices(vkd: anytype, dev_res: *const DeviceResource, pool: vk.CommandPool, dst_buffer: vk.Buffer, vertices: []const components.Vertex) !void {
    const size = @sizeOf(components.Vertex) * vertices.len;

    // Create staging buffer
    const staging_buffer = try vkd.createBuffer(&.{
        .size = size,
        .usage = .{ .transfer_src_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer vkd.destroyBuffer(staging_buffer, null);

    const mem_reqs = vkd.getBufferMemoryRequirements(staging_buffer);
    const staging_memory = try allocateMemory(vkd, dev_res, mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    defer vkd.freeMemory(staging_memory, null);

    try vkd.bindBufferMemory(staging_buffer, staging_memory, 0);

    // Copy vertices to staging buffer
    {
        const data = try vkd.mapMemory(staging_memory, 0, vk.WHOLE_SIZE, .{});
        defer vkd.unmapMemory(staging_memory);

        const gpu_vertices: [*]components.Vertex = @ptrCast(@alignCast(data));
        @memcpy(gpu_vertices[0..vertices.len], vertices);
    }

    // Copy from staging to device buffer
    var cmdbuf_handle: vk.CommandBuffer = undefined;
    try vkd.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf_handle));
    defer vkd.freeCommandBuffers(pool, 1, @ptrCast(&cmdbuf_handle));

    try vkd.beginCommandBuffer(cmdbuf_handle, &.{ .flags = .{ .one_time_submit_bit = true } });

    const region = vk.BufferCopy{ .src_offset = 0, .dst_offset = 0, .size = size };
    vkd.cmdCopyBuffer(cmdbuf_handle, staging_buffer, dst_buffer, 1, @ptrCast(&region));

    try vkd.endCommandBuffer(cmdbuf_handle);

    const submit = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmdbuf_handle),
        .p_wait_dst_stage_mask = undefined,
    };

    const gfx_q = dev_res.graphics_queue.?;
    try vkd.queueSubmit(gfx_q, 1, @ptrCast(&submit), .null_handle);
    try vkd.queueWaitIdle(gfx_q);
}

fn uploadSpriteVertices(vkd: anytype, dev_res: *const DeviceResource, pool: vk.CommandPool, dst_buffer: vk.Buffer, vertices: []const components.SpriteVertex) !void {
    const size = @sizeOf(components.SpriteVertex) * vertices.len;

    const staging_buffer = try vkd.createBuffer(&.{
        .size = size,
        .usage = .{ .transfer_src_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer vkd.destroyBuffer(staging_buffer, null);

    const mem_reqs = vkd.getBufferMemoryRequirements(staging_buffer);
    const staging_memory = try allocateMemory(vkd, dev_res, mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    defer vkd.freeMemory(staging_memory, null);

    try vkd.bindBufferMemory(staging_buffer, staging_memory, 0);

    {
        const data = try vkd.mapMemory(staging_memory, 0, vk.WHOLE_SIZE, .{});
        defer vkd.unmapMemory(staging_memory);

        const gpu_vertices: [*]components.SpriteVertex = @ptrCast(@alignCast(data));
        @memcpy(gpu_vertices[0..vertices.len], vertices);
    }

    var cmdbuf_handle: vk.CommandBuffer = undefined;
    try vkd.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf_handle));
    defer vkd.freeCommandBuffers(pool, 1, @ptrCast(&cmdbuf_handle));

    try vkd.beginCommandBuffer(cmdbuf_handle, &.{ .flags = .{ .one_time_submit_bit = true } });

    const region = vk.BufferCopy{ .src_offset = 0, .dst_offset = 0, .size = size };
    vkd.cmdCopyBuffer(cmdbuf_handle, staging_buffer, dst_buffer, 1, @ptrCast(&region));

    try vkd.endCommandBuffer(cmdbuf_handle);

    const submit = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmdbuf_handle),
        .p_wait_dst_stage_mask = undefined,
    };

    const gfx_q = dev_res.graphics_queue.?;
    try vkd.queueSubmit(gfx_q, 1, @ptrCast(&submit), .null_handle);
    try vkd.queueWaitIdle(gfx_q);
}

fn deinit_system(r_device: ResOpt(DeviceResource), r_swap: ResOpt(SwapchainResource), r_rend: ResOpt(RenderResource)) !void {
    _ = r_swap;

    if (r_rend.ptr) |rr| {
        if (r_device.ptr) |dev| {
            if (dev.device_proxy) |vkd| {
                try vkd.deviceWaitIdle();

                // Destroy triangle resources
                vkd.destroyBuffer(rr.vertex_buffer, null);
                vkd.freeMemory(rr.vertex_memory, null);
                vkd.destroyPipeline(rr.pipeline, null);
                vkd.destroyPipelineLayout(rr.pipeline_layout, null);

                // Destroy sprite resources
                vkd.destroyBuffer(rr.sprite_vertex_buffer, null);
                vkd.freeMemory(rr.sprite_vertex_memory, null);
                vkd.destroyPipeline(rr.sprite_pipeline, null);
                vkd.destroyPipelineLayout(rr.sprite_pipeline_layout, null);
                vkd.destroyDescriptorPool(rr.sprite_descriptor_pool, null);
                vkd.destroyDescriptorSetLayout(rr.sprite_descriptor_set_layout, null);

                destroySyncObjects(vkd, rr.allocator, .{
                    .in_flight = rr.in_flight,
                    .image_available = rr.image_available,
                    .render_finished = rr.render_finished,
                });

                destroyFramebuffers(vkd, rr.allocator, rr.framebuffers);
                vkd.destroyRenderPass(rr.render_pass, null);
                freeCommandBuffers(vkd, rr.cmd_pool, rr.allocator, rr.cmd_buffers);
                vkd.destroyCommandPool(rr.cmd_pool, null);
            }
        }
    }

    std.log.info("Vulkan RenderPlugin: deinitialized", .{});
}

// ─────────────────────────────────────────────
// Imports
// ─────────────────────────────────────────────
const std = @import("std");
const vk = @import("vulkan");

const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
const Commands = phasor_ecs.Commands;
const ResOpt = phasor_ecs.ResOpt;
const Query = phasor_ecs.Query;
const EventReader = phasor_ecs.EventReader;

const phasor_common = @import("phasor-common");
const RenderBounds = phasor_common.RenderBounds;
const ClearColor = phasor_common.ClearColor;

const components = @import("../components.zig");
const Transform3d = components.Transform3d;
const assets = @import("../assets.zig");
const DeviceResource = @import("../device/DevicePlugin.zig").DeviceResource;
const SwapchainResource = @import("../swapchain/SwapchainPlugin.zig").SwapchainResource;
