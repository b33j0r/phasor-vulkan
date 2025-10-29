// ─────────────────────────────────────────────
// Render Plugin (Modular Version)
// ─────────────────────────────────────────────
// Implements a modular Vulkan rendering pipeline where each shape type
// (Triangle, Sprite, Text, Circle, Rectangle) is handled by a dedicated
// renderer module. This architecture makes adding new shapes trivial.
//
// Key Features:
// - Modular shape renderers with unified interface
// - Centralized resource management
// - Clean separation of concerns
// - Easy extensibility - just add a new ShapeRenderer
//
// Architecture:
// 1. RenderPlugin manages core Vulkan resources (render pass, framebuffers, sync)
// 2. Each shape type has a dedicated renderer (TriangleRenderer, SpriteRenderer, etc.)
// 3. RenderContext provides shared utilities (coordinate transforms, camera, upload)
// 4. Rendering flow: init → collect → upload → record → present

const RenderPlugin = @This();

pub fn build(self: *RenderPlugin, app: *App) !void {
    _ = self;
    try app.addSystem("VkRenderInit", init_system);
    try app.addSystem("VkRender", render_system);
    try app.addSystem("VkRenderDeinit", deinit_system);
}

pub const RenderResource = struct {
    gpa: *std.heap.GeneralPurposeAllocator(.{}),
    allocator: std.mem.Allocator,

    // Resource tracking for diagnostics
    frame_count: u64 = 0,
    upload_count: u64 = 0,
    last_log_frame: u64 = 0,

    // Core Vulkan resources
    render_pass: vk.RenderPass,
    framebuffers: []vk.Framebuffer,
    cmd_pool: vk.CommandPool,
    cmd_buffers: []vk.CommandBuffer,

    // Synchronization
    image_available: []vk.Semaphore,
    render_finished: []vk.Semaphore,
    in_flight: []vk.Fence,

    // Shape renderer resources
    triangle_resources: ShapeRenderer.ShapeResources,
    sprite_resources: ShapeRenderer.ShapeResources,
    circle_resources: ShapeRenderer.ShapeResources,
    rectangle_resources: ShapeRenderer.ShapeResources,
    mesh_resources: MeshRenderer.MeshResources,
};

fn init_system(commands: *Commands, r_device: ResOpt(DeviceResource), r_swap: ResOpt(SwapchainResource), r_clear: ResOpt(ClearColor)) !void {
    const dev_res = r_device.ptr orelse return error.MissingDeviceResource;
    const vkd = dev_res.device_proxy orelse return error.MissingDevice;
    const swap = r_swap.ptr orelse return error.MissingSwapchainResource;

    // Allocate GPA on heap so it persists
    const gpa = try std.heap.c_allocator.create(std.heap.GeneralPurposeAllocator(.{}));
    gpa.* = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    if (r_clear.ptr == null) {
        try commands.insertResource(ClearColor{});
    }

    const render_pass = try createRenderPass(vkd, swap.surface_format.format);
    errdefer vkd.destroyRenderPass(render_pass, null);

    const framebuffers = try createFramebuffers(allocator, vkd, render_pass, swap);
    errdefer destroyFramebuffers(vkd, allocator, framebuffers);

    const cmd_pool = try vkd.createCommandPool(&.{
        .queue_family_index = dev_res.graphics_family_index.?,
        .flags = .{ .reset_command_buffer_bit = true },
    }, null);
    errdefer vkd.destroyCommandPool(cmd_pool, null);

    const cmd_buffers = try allocateCommandBuffers(allocator, vkd, cmd_pool, @intCast(swap.views.len));
    errdefer freeCommandBuffers(vkd, cmd_pool, allocator, cmd_buffers);

    const sync = try createSyncObjects(allocator, vkd, @intCast(swap.views.len));
    errdefer destroySyncObjects(vkd, allocator, sync);

    // Initialize all shape renderers
    const triangle_resources = try TriangleRenderer.init(vkd, dev_res, render_pass, swap.extent, allocator);
    errdefer TriangleRenderer.deinit(vkd, &triangle_resources);

    const sprite_resources = try SpriteRenderer.init(vkd, dev_res, render_pass, swap.extent, allocator);
    errdefer SpriteRenderer.deinit(vkd, &sprite_resources);

    const circle_resources = try CircleRenderer.init(vkd, dev_res, render_pass, swap.extent, allocator);
    errdefer CircleRenderer.deinit(vkd, &circle_resources);

    const rectangle_resources = try RectangleRenderer.init(vkd, dev_res, render_pass, swap.extent, allocator);
    errdefer RectangleRenderer.deinit(vkd, &rectangle_resources);

    const mesh_resources = try MeshRenderer.init(vkd, dev_res, render_pass, swap.extent, allocator);
    errdefer MeshRenderer.deinit(vkd, &mesh_resources);

    try commands.insertResource(RenderResource{
        .gpa = gpa,
        .allocator = allocator,
        .render_pass = render_pass,
        .framebuffers = framebuffers,
        .cmd_pool = cmd_pool,
        .cmd_buffers = cmd_buffers,
        .image_available = sync.image_available,
        .render_finished = sync.render_finished,
        .in_flight = sync.in_flight,
        .triangle_resources = triangle_resources,
        .sprite_resources = sprite_resources,
        .circle_resources = circle_resources,
        .rectangle_resources = rectangle_resources,
        .mesh_resources = mesh_resources,
    });

    std.log.info("Vulkan RenderPlugin: initialized (modular)", .{});
}

fn render_system(
    commands: *Commands,
    r_device: ResOpt(DeviceResource),
    r_swap: ResOpt(SwapchainResource),
    r_window_bounds: ResOpt(phasor_common.WindowBounds),
    r_rend: ResMut(RenderResource),
    r_clear: ResOpt(ClearColor),
    q_triangles: Query(.{components.Triangle}),
    q_sprites: Query(.{ components.Sprite3D, Transform3d }),
    q_text: Query(.{ components.Text, Transform3d }),
    q_circles: Query(.{ components.Circle, Transform3d }),
    q_rectangles: Query(.{ components.Rectangle, Transform3d }),
    q_meshes: Query(.{ components.Mesh, Transform3d }),
    q_cameras: Query(.{ components.Camera3d, Transform3d }),
) !void {
    _ = commands;

    const dev_res = r_device.ptr orelse return;
    const vkd = dev_res.device_proxy orelse return;
    const gfx_q = dev_res.graphics_queue.?;
    const present_q = dev_res.present_queue.?;
    const swap = r_swap.ptr orelse return;
    const rr = r_rend.ptr;
    const clear_color = if (r_clear.ptr) |cc| cc.* else ClearColor{};

    const window_bounds = r_window_bounds.ptr orelse return;
    const window_width: f32 = @floatFromInt(window_bounds.width);
    const window_height: f32 = @floatFromInt(window_bounds.height);

    // Resource tracking diagnostics
    rr.frame_count += 1;
    if (rr.frame_count - rr.last_log_frame >= 180) { // Log every 3 seconds at 60 FPS
        std.log.info("=== FRAME {d} === Uploads/3sec: {d} (avg {d}/frame)", .{
            rr.frame_count,
            rr.upload_count,
            rr.upload_count / 180,
        });
        rr.last_log_frame = rr.frame_count;
        rr.upload_count = 0;
    }

    // Find camera for projection and offset
    var camera_offset = phasor_common.Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    var camera: ?*const components.Camera3d = null;
    var camera_transform: ?*const Transform3d = null;
    var cam_it = q_cameras.iterator();
    if (cam_it.next()) |cam_entity| {
        camera = cam_entity.get(components.Camera3d);
        if (cam_entity.get(Transform3d)) |cam_transform| {
            camera_offset = cam_transform.translation;
            camera_transform = cam_transform;
        }
    }

    // Create render context
    var ctx = RenderContext{
        .dev_res = dev_res,
        .cmd_pool = rr.cmd_pool,
        .window_width = window_width,
        .window_height = window_height,
        .camera_offset = camera_offset,
        .allocator = rr.allocator,
        .upload_counter = &rr.upload_count,
    };

    // Reset descriptor pools for this frame (before allocating new descriptor sets)
    if (rr.sprite_resources.descriptor_pool) |pool| {
        try vkd.resetDescriptorPool(pool, .{});
    }
    try vkd.resetDescriptorPool(rr.mesh_resources.descriptor_pool, .{});

    // Acquire swapchain image
    const next_image_sem = rr.image_available[0];
    const acquire = try vkd.acquireNextImageKHR(swap.swapchain.?, std.math.maxInt(u64), next_image_sem, .null_handle);

    switch (acquire.result) {
        .success, .suboptimal_khr => {},
        .error_out_of_date_khr => return,
        else => return error.ImageAcquireFailed,
    }

    const img_idx: usize = @intCast(acquire.image_index);

    // Collect and upload vertices for each shape type
    const triangle_count = try TriangleRenderer.collect(vkd, &ctx, &rr.triangle_resources, q_triangles);

    const sprite_state = try SpriteRenderer.collect(vkd, &ctx, &rr.sprite_resources, q_sprites, q_text);
    defer {
        var state_copy = sprite_state;
        state_copy.deinit(rr.allocator);
    }

    const circle_count = try CircleRenderer.collect(vkd, &ctx, &rr.circle_resources, q_circles);
    const rectangle_count = try RectangleRenderer.collect(vkd, &ctx, &rr.rectangle_resources, q_rectangles);

    // Collect meshes (requires camera)
    var collected_meshes = if (camera != null and camera_transform != null)
        try MeshRenderer.collect(vkd, &ctx, &rr.mesh_resources, q_meshes, camera.?, camera_transform.?)
    else
        try std.ArrayList(MeshRenderer.CollectedMesh).initCapacity(rr.allocator, 0);
    defer collected_meshes.deinit(rr.allocator);

    // Record command buffer
    try recordCommandBuffer(
        vkd,
        &ctx,
        rr,
        swap,
        img_idx,
        clear_color,
        triangle_count,
        &sprite_state,
        circle_count,
        rectangle_count,
        collected_meshes.items,
    );

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
}

fn recordCommandBuffer(
    vkd: anytype,
    ctx: *RenderContext,
    rr: *const RenderResource,
    swap: *const SwapchainResource,
    img_idx: usize,
    clear_color: ClearColor,
    triangle_count: u32,
    sprite_state: *const SpriteRenderer.CollectionState,
    circle_count: u32,
    rectangle_count: u32,
    mesh_list: []const MeshRenderer.CollectedMesh,
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
    const clear_values = [_]vk.ClearValue{
        .{ .color = .{ .float_32 = .{ clear_f32.r, clear_f32.g, clear_f32.b, clear_f32.a } } },
        .{ .depth_stencil = .{ .depth = 0.0, .stencil = 0 } }, // reverse-Z: clear to 0
    };

    vkd.cmdBeginRenderPass(cmdbuf, &.{
        .render_pass = rr.render_pass,
        .framebuffer = rr.framebuffers[img_idx],
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = swap.extent },
        .clear_value_count = clear_values.len,
        .p_clear_values = &clear_values,
    }, .@"inline");

    // Record draw calls for each shape type
    MeshRenderer.record(vkd, ctx, &rr.mesh_resources, cmdbuf, mesh_list);
    TriangleRenderer.record(vkd, ctx, &rr.triangle_resources, cmdbuf, triangle_count);
    SpriteRenderer.record(vkd, ctx, &rr.sprite_resources, cmdbuf, sprite_state);
    CircleRenderer.record(vkd, ctx, &rr.circle_resources, cmdbuf, circle_count);
    RectangleRenderer.record(vkd, ctx, &rr.rectangle_resources, cmdbuf, rectangle_count);

    vkd.cmdEndRenderPass(cmdbuf);
    try vkd.endCommandBuffer(cmdbuf);
}

fn deinit_system(r_device: ResOpt(DeviceResource), r_swap: ResOpt(SwapchainResource), r_rend: ResOpt(RenderResource)) !void {
    _ = r_swap;

    if (r_rend.ptr) |rr| {
        if (r_device.ptr) |dev| {
            if (dev.device_proxy) |vkd| {
                try vkd.deviceWaitIdle();

                // Destroy shape renderer resources
                TriangleRenderer.deinit(vkd, &rr.triangle_resources);
                SpriteRenderer.deinit(vkd, &rr.sprite_resources);
                CircleRenderer.deinit(vkd, &rr.circle_resources);
                RectangleRenderer.deinit(vkd, &rr.rectangle_resources);
                MeshRenderer.deinit(vkd, &rr.mesh_resources);

                // Destroy core resources
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

        // Deinit and free GPA
        _ = rr.gpa.deinit();
        std.heap.c_allocator.destroy(rr.gpa);
    }

    std.log.info("Vulkan RenderPlugin: deinitialized", .{});
}

// ─────────────────────────────────────────────
// Helper Functions
// ─────────────────────────────────────────────

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

    const depth_attachment = vk.AttachmentDescription{
        .format = .d32_sfloat,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .dont_care,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .depth_stencil_attachment_optimal,
    };

    const attachments = [_]vk.AttachmentDescription{ color_attachment, depth_attachment };

    const color_ref = vk.AttachmentReference{ .attachment = 0, .layout = .color_attachment_optimal };
    const depth_ref = vk.AttachmentReference{ .attachment = 1, .layout = .depth_stencil_attachment_optimal };

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_ref),
        .p_depth_stencil_attachment = &depth_ref,
    };

    return try vkd.createRenderPass(&.{
        .attachment_count = attachments.len,
        .p_attachments = &attachments,
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
        const attachments = [_]vk.ImageView{ swap.views[idx], swap.depth_image_view.? };
        fb.* = try vkd.createFramebuffer(&.{
            .render_pass = render_pass,
            .attachment_count = attachments.len,
            .p_attachments = &attachments,
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

// ─────────────────────────────────────────────
// Imports
// ─────────────────────────────────────────────
const std = @import("std");
const vk = @import("vulkan");

const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
const Commands = phasor_ecs.Commands;
const ResOpt = phasor_ecs.ResOpt;
const ResMut = phasor_ecs.ResMut;
const Query = phasor_ecs.Query;

const phasor_common = @import("phasor-common");
const ClearColor = phasor_common.ClearColor;

const components = @import("../components.zig");
const Transform3d = components.Transform3d;
const DeviceResource = @import("../device/DevicePlugin.zig").DeviceResource;
const SwapchainResource = @import("../swapchain/SwapchainPlugin.zig").SwapchainResource;

const RenderContext = @import("RenderContext.zig");
const ShapeRenderer = @import("ShapeRenderer.zig");
const TriangleRenderer = @import("TriangleRenderer.zig");
const SpriteRenderer = @import("SpriteRenderer.zig");
const CircleRenderer = @import("CircleRenderer.zig");
const RectangleRenderer = @import("RectangleRenderer.zig");
const MeshRenderer = @import("MeshRenderer.zig");
