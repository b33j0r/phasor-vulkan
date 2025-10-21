const RenderPlugin = @This();

pub fn build(self: *RenderPlugin, app: *App) !void {
    _ = self;
    // VulkanPlugin creates precise schedules; we only register systems to them.
    try app.addSystem("VkRenderInit", init_system);
    try app.addSystem("VkRender", render_system);
    try app.addSystem("VkRenderDeinit", deinit_system);
}

const RenderResource = struct {
    render_pass: vk.RenderPass = .null_handle,
    framebuffers: []vk.Framebuffer = &[_]vk.Framebuffer{},
    cmd_pool: vk.CommandPool = .null_handle,
    cmd_buffers: []vk.CommandBuffer = &[_]vk.CommandBuffer{},
    image_available: []vk.Semaphore = &[_]vk.Semaphore{},
    render_finished: []vk.Semaphore = &[_]vk.Semaphore{},
    in_flight: []vk.Fence = &[_]vk.Fence{},

    // Triangle pipeline resources
    pipeline_layout: vk.PipelineLayout = .null_handle,
    pipeline: vk.Pipeline = .null_handle,

    // Vertex buffer
    vertex_buffer: vk.Buffer = .null_handle,
    vertex_memory: vk.DeviceMemory = .null_handle,
    vertex_buffer_size: vk.DeviceSize = 0,
    max_vertices: u32 = 0,
};

fn init_system(commands: *Commands, r_device: ResOpt(DeviceResource), r_swap: ResOpt(SwapchainResource), r_clear: ResOpt(ClearColor)) !void {
    const dev_res = r_device.ptr orelse return error.MissingDeviceResource;
    const vkd = dev_res.device_proxy orelse return error.MissingDevice;
    const swap = r_swap.ptr orelse return error.MissingSwapchainResource;

    // Ensure ClearColor exists; insert default if not provided
    if (r_clear.ptr == null) {
        try commands.insertResource(ClearColor{});
    }

    // Create a simple render pass with a single color attachment cleared and presented
    const color_attachment = vk.AttachmentDescription{
        .format = swap.surface_format.format,
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
    const rp = try vkd.createRenderPass(&.{
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_attachment),
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
    }, null);

    // Create framebuffers for each swapchain view
    const fbs = try std.heap.page_allocator.alloc(vk.Framebuffer, swap.views.len);
    errdefer std.heap.page_allocator.free(fbs);
    for (fbs, 0..) |*fb, i| {
        fb.* = try vkd.createFramebuffer(&.{
            .render_pass = rp,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&swap.views[i]),
            .width = swap.extent.width,
            .height = swap.extent.height,
            .layers = 1,
        }, null);
    }

    // Command pool and buffers
    const pool = try vkd.createCommandPool(&.{ .queue_family_index = dev_res.graphics_family_index.? }, null);
    const cmdbufs = try std.heap.page_allocator.alloc(vk.CommandBuffer, swap.views.len);
    errdefer std.heap.page_allocator.free(cmdbufs);
    try vkd.allocateCommandBuffers(&.{ .command_pool = pool, .level = .primary, .command_buffer_count = @intCast(cmdbufs.len) }, cmdbufs.ptr);

    // Sync objects per frame/image
    const image_available = try std.heap.page_allocator.alloc(vk.Semaphore, cmdbufs.len);
    const render_finished = try std.heap.page_allocator.alloc(vk.Semaphore, cmdbufs.len);
    const in_flight = try std.heap.page_allocator.alloc(vk.Fence, cmdbufs.len);
    for (image_available) |*s| s.* = try vkd.createSemaphore(&.{}, null);
    for (render_finished) |*s| s.* = try vkd.createSemaphore(&.{}, null);
    for (in_flight) |*f| f.* = try vkd.createFence(&.{ .flags = .{ .signaled_bit = true } }, null);

    // Create pipeline for triangle rendering
    const pipeline_layout = try vkd.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);

    const shaders = @import("shaders.zig");
    const vert_spv = shaders.vert_spv;
    const frag_spv = shaders.frag_spv;

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
        .{
            .stage = .{ .vertex_bit = true },
            .module = vert_module,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = frag_module,
            .p_name = "main",
        },
    };

    const vertex_binding = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(components.Vertex),
        .input_rate = .vertex,
    };

    const vertex_attributes = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(components.Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(components.Vertex, "color"),
        },
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
        .layout = pipeline_layout,
        .render_pass = rp,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try vkd.createGraphicsPipelines(
        .null_handle,
        1,
        @ptrCast(&pipeline_info),
        null,
        @ptrCast(&pipeline),
    );

    // Create vertex buffer (we'll allocate for max 1000 triangles = 3000 vertices)
    const max_vertices: u32 = 3000;
    const buffer_size = @sizeOf(components.Vertex) * max_vertices;
    const vertex_buffer = try vkd.createBuffer(&.{
        .size = buffer_size,
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);

    const mem_reqs = vkd.getBufferMemoryRequirements(vertex_buffer);
    const vertex_memory = try allocateMemory(vkd, dev_res, mem_reqs, .{ .device_local_bit = true });
    try vkd.bindBufferMemory(vertex_buffer, vertex_memory, 0);

    try commands.insertResource(RenderResource{
        .render_pass = rp,
        .framebuffers = fbs,
        .cmd_pool = pool,
        .cmd_buffers = cmdbufs,
        .image_available = image_available,
        .render_finished = render_finished,
        .in_flight = in_flight,
        .pipeline_layout = pipeline_layout,
        .pipeline = pipeline,
        .vertex_buffer = vertex_buffer,
        .vertex_memory = vertex_memory,
        .vertex_buffer_size = buffer_size,
        .max_vertices = max_vertices,
    });

    std.log.info("Vulkan RenderPlugin: pipeline and resources created", .{});
}

fn allocateMemory(vkd: anytype, dev_res: *const DeviceResource, requirements: vk.MemoryRequirements, properties: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    const mem_props = dev_res.memory_properties;

    var i: u32 = 0;
    while (i < mem_props.memory_type_count) : (i += 1) {
        if ((requirements.memory_type_bits & (@as(u32, 1) << @intCast(i))) != 0) {
            const type_props = mem_props.memory_types[i].property_flags;
            if ((type_props.host_visible_bit == properties.host_visible_bit or !properties.host_visible_bit) and
                (type_props.host_coherent_bit == properties.host_coherent_bit or !properties.host_coherent_bit) and
                (type_props.device_local_bit == properties.device_local_bit or !properties.device_local_bit))
            {
                return try vkd.allocateMemory(&.{
                    .allocation_size = requirements.size,
                    .memory_type_index = i,
                }, null);
            }
        }
    }
    return error.NoSuitableMemoryType;
}

fn render_system(commands: *Commands, r_device: ResOpt(DeviceResource), r_swap: ResOpt(SwapchainResource), r_bounds: ResOpt(RenderBounds), r_rend: ResOpt(RenderResource), r_clear: ResOpt(ClearColor), q_triangles: Query(.{components.Triangle})) !void {
    _ = r_bounds;
    const dev_res = r_device.ptr orelse return;
    const vkd = dev_res.device_proxy orelse return;
    const gfx_q = dev_res.graphics_queue.?;
    const present_q = dev_res.present_queue.?;
    const swap = r_swap.ptr orelse return;
    const rr = r_rend.ptr orelse return;
    const clear_color = if (r_clear.ptr) |cc| cc.* else ClearColor{};

    // Acquire next image
    const next_image_sem = rr.image_available[0]; // Simple rotation for now
    const acquire = try vkd.acquireNextImageKHR(swap.swapchain.?, std.math.maxInt(u64), next_image_sem, .null_handle);
    switch (acquire.result) {
        .success, .suboptimal_khr => {},
        .error_out_of_date_khr => return,
        else => return error.ImageAcquireFailed,
    }

    const img: usize = @intCast(acquire.image_index);

    // Collect all triangle vertices
    var vertices = try std.ArrayList(components.Vertex).initCapacity(std.heap.page_allocator, 100);
    defer vertices.deinit(std.heap.page_allocator);

    var it = q_triangles.iterator();
    while (it.next()) |entity| {
        if (entity.get(components.Triangle)) |tri| {
            try vertices.appendSlice(std.heap.page_allocator, &tri.vertices);
        }
    }

    // Upload vertices to GPU
    if (vertices.items.len > 0) {
        try uploadVertices(vkd, dev_res, rr.cmd_pool, rr.vertex_buffer, vertices.items);
    }

    // Record command buffer
    const cmdbuf = rr.cmd_buffers[img];
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

    const render_area = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swap.extent,
    };

    vkd.cmdBeginRenderPass(cmdbuf, &.{
        .render_pass = rr.render_pass,
        .framebuffer = rr.framebuffers[img],
        .render_area = render_area,
        .clear_value_count = 1,
        .p_clear_values = @ptrCast(&clear_value),
    }, .@"inline");

    vkd.cmdBindPipeline(cmdbuf, .graphics, rr.pipeline);

    if (vertices.items.len > 0) {
        const offset = [_]vk.DeviceSize{0};
        vkd.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&rr.vertex_buffer), &offset);
        vkd.cmdDraw(cmdbuf, @intCast(vertices.items.len), 1, 0, 0);
    }

    vkd.cmdEndRenderPass(cmdbuf);
    try vkd.endCommandBuffer(cmdbuf);

    // Submit
    const wait_stages = [_]vk.PipelineStageFlags{.{ .color_attachment_output_bit = true }};
    const submit = vk.SubmitInfo{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&next_image_sem),
        .p_wait_dst_stage_mask = &wait_stages,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmdbuf),
        .signal_semaphore_count = 1,
        .p_signal_semaphores = @ptrCast(&rr.render_finished[img]),
    };
    try vkd.queueSubmit(gfx_q, 1, @ptrCast(&submit), .null_handle);

    // Present
    const sc = swap.swapchain.?;
    var img_idx: u32 = acquire.image_index;
    const present_info = vk.PresentInfoKHR{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&rr.render_finished[img]),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&sc),
        .p_image_indices = @ptrCast(&img_idx),
        .p_results = null,
    };
    _ = try vkd.queuePresentKHR(present_q, &present_info);

    // Simple synchronization: wait for queue idle
    try vkd.queueWaitIdle(present_q);

    _ = commands;
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

    // Copy to staging
    {
        const data = try vkd.mapMemory(staging_memory, 0, vk.WHOLE_SIZE, .{});
        defer vkd.unmapMemory(staging_memory);

        const gpu_vertices: [*]components.Vertex = @ptrCast(@alignCast(data));
        @memcpy(gpu_vertices[0..vertices.len], vertices);
    }

    // Copy from staging to device
    var cmdbuf_handle: vk.CommandBuffer = undefined;
    try vkd.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf_handle));
    defer vkd.freeCommandBuffers(pool, 1, @ptrCast(&cmdbuf_handle));

    try vkd.beginCommandBuffer(cmdbuf_handle, &.{ .flags = .{ .one_time_submit_bit = true } });

    const region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
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

                vkd.destroyBuffer(rr.vertex_buffer, null);
                vkd.freeMemory(rr.vertex_memory, null);
                vkd.destroyPipeline(rr.pipeline, null);
                vkd.destroyPipelineLayout(rr.pipeline_layout, null);

                for (rr.in_flight) |f| vkd.destroyFence(f, null);
                for (rr.image_available) |s| vkd.destroySemaphore(s, null);
                for (rr.render_finished) |s| vkd.destroySemaphore(s, null);
                for (rr.framebuffers) |fb| vkd.destroyFramebuffer(fb, null);
                vkd.destroyRenderPass(rr.render_pass, null);
                vkd.freeCommandBuffers(rr.cmd_pool, @intCast(rr.cmd_buffers.len), rr.cmd_buffers.ptr);
                vkd.destroyCommandPool(rr.cmd_pool, null);
            }
        }
        if (rr.framebuffers.len > 0) std.heap.page_allocator.free(rr.framebuffers);
        if (rr.cmd_buffers.len > 0) std.heap.page_allocator.free(rr.cmd_buffers);
        if (rr.image_available.len > 0) std.heap.page_allocator.free(rr.image_available);
        if (rr.render_finished.len > 0) std.heap.page_allocator.free(rr.render_finished);
        if (rr.in_flight.len > 0) std.heap.page_allocator.free(rr.in_flight);
    }
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

const phasor_common = @import("phasor-common");
const RenderBounds = phasor_common.RenderBounds;
const ClearColor = phasor_common.ClearColor;

const components = @import("../components.zig");
const DeviceResource = @import("../device/DevicePlugin.zig").DeviceResource;
const SwapchainResource = @import("../swapchain/SwapchainPlugin.zig").SwapchainResource;
