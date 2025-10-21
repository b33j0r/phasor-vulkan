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
    next_image_acquired: vk.Semaphore = .null_handle,
    frame_index: usize = 0,
};

fn init_system(commands: *Commands, r_device: ResOpt(DeviceResource), r_swap: ResOpt(SwapchainResource), r_clear: ResOpt(ClearColor)) !void {
    const dev_res = r_device.ptr orelse return error.MissingDeviceResource;
    const vkd = dev_res.device_proxy orelse return error.MissingDevice;
    const swap = r_swap.ptr orelse return error.MissingSwapchainResource;

    // Ensure ClearColor exists; insert default if not provided
    if (r_clear.ptr == null) {
        try commands.insertResource(ClearColor{});
    }
    const clear_color_val = if (r_clear.ptr) |cc| cc.* else ClearColor{};
    const clear = clear_color_val.color;

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

    // Record command buffers with a clear pass
    const viewport = vk.Viewport{ .x = 0, .y = 0, .width = @floatFromInt(swap.extent.width), .height = @floatFromInt(swap.extent.height), .min_depth = 0, .max_depth = 1 };
    const scissor = vk.Rect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = swap.extent };
    const clear_f32 = phasor_common.Color.F32.fromColor(clear);
    const clear_value = vk.ClearValue{ .color = .{ .float_32 = .{ clear_f32.r, clear_f32.g, clear_f32.b, clear_f32.a } } };

    for (cmdbufs, 0..) |cmdbuf, i| {
        try vkd.beginCommandBuffer(cmdbuf, &.{});
        vkd.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(&viewport));
        vkd.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(&scissor));
        const render_area = vk.Rect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = swap.extent };
        vkd.cmdBeginRenderPass(cmdbuf, &.{
            .render_pass = rp,
            .framebuffer = fbs[i],
            .render_area = render_area,
            .clear_value_count = 1,
            .p_clear_values = @ptrCast(&clear_value),
        }, .@"inline");
        vkd.cmdEndRenderPass(cmdbuf);
        try vkd.endCommandBuffer(cmdbuf);
    }

    // Sync objects per frame/image
    const image_available = try std.heap.page_allocator.alloc(vk.Semaphore, cmdbufs.len);
    const render_finished = try std.heap.page_allocator.alloc(vk.Semaphore, cmdbufs.len);
    const in_flight = try std.heap.page_allocator.alloc(vk.Fence, cmdbufs.len);
    for (image_available) |*s| s.* = try vkd.createSemaphore(&.{}, null);
    for (render_finished) |*s| s.* = try vkd.createSemaphore(&.{}, null);
    for (in_flight) |*f| f.* = try vkd.createFence(&.{ .flags = .{ .signaled_bit = true } }, null);
    const next_image_acquired = try vkd.createSemaphore(&.{}, null);

    try commands.insertResource(RenderResource{
        .render_pass = rp,
        .framebuffers = fbs,
        .cmd_pool = pool,
        .cmd_buffers = cmdbufs,
        .image_available = image_available,
        .render_finished = render_finished,
        .in_flight = in_flight,
        .next_image_acquired = next_image_acquired,
        .frame_index = 0,
    });

    std.log.info("Vulkan RenderPlugin: render pass and framebuffers created", .{});
}

fn render_system(_: *Commands, r_device: ResOpt(DeviceResource), r_swap: ResOpt(SwapchainResource), r_bounds: ResOpt(RenderBounds), r_rend: ResOpt(RenderResource)) !void {
    _ = r_bounds;
    const dev_res = r_device.ptr orelse return;
    const vkd = dev_res.device_proxy orelse return;
    const gfx_q = dev_res.graphics_queue.?;
    const present_q = dev_res.present_queue.?;
    const swap = r_swap.ptr orelse return;
    const rr = r_rend.ptr orelse return;

    // Acquire next image and use its index for per-image synchronization
    const acquire = try vkd.acquireNextImageKHR(swap.swapchain.?, std.math.maxInt(u64), rr.next_image_acquired, .null_handle);
    switch (acquire.result) {
        .success, .suboptimal_khr => {},
        .error_out_of_date_khr => return, // skip frame; resize handling not implemented
        else => return error.ImageAcquireFailed,
    }

    const img: usize = @intCast(acquire.image_index);

    // Wait for previous work on this image to complete
    // Simple synchronization for now: no fences; we serialize by waiting for the queue to idle after presenting.

    // Submit
    const wait_stages = [_]vk.PipelineStageFlags{ .{ .color_attachment_output_bit = true } };
    const submit = vk.SubmitInfo{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&rr.next_image_acquired),
        .p_wait_dst_stage_mask = &wait_stages,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&rr.cmd_buffers[img]),
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
}

fn deinit_system(r_device: ResOpt(DeviceResource), r_swap: ResOpt(SwapchainResource), r_rend: ResOpt(RenderResource)) !void {
    _ = r_swap;
    if (r_rend.ptr) |rr| {
        if (r_device.ptr) |dev| {
            if (dev.device_proxy) |vkd| {
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

const phasor_common = @import("phasor-common");
const RenderBounds = phasor_common.RenderBounds;
const ClearColor = phasor_common.ClearColor;

const DeviceResource = @import("../device/DevicePlugin.zig").DeviceResource;
const SwapchainResource = @import("../swapchain/SwapchainPlugin.zig").SwapchainResource;
