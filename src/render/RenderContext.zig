// ─────────────────────────────────────────────
// Render Context
// ─────────────────────────────────────────────
// Shared rendering state and utilities passed to all shape renderers.
// This provides common functionality like coordinate transformation,
// camera handling, and Vulkan resource access.

const RenderContext = @This();

const std = @import("std");
const vk = @import("vulkan");
const phasor_common = @import("phasor-common");
const components = @import("../components.zig");
const DeviceResource = @import("../device/DevicePlugin.zig").DeviceResource;

/// Device resource for memory allocation
dev_res: *const DeviceResource,
cmd_pool: vk.CommandPool,

/// Window dimensions for coordinate transformation
window_width: f32,
window_height: f32,

/// Camera offset for camera-relative positioning
camera_offset: phasor_common.Vec3,

/// Memory allocator
allocator: std.mem.Allocator,

/// Transform a point from window coordinates to clip space
/// Window coords: origin at specified position, units in logical pixels
/// Clip space: [-1, 1] range for both X and Y
pub fn windowToClip(self: RenderContext, window_x: f32, window_y: f32) struct { x: f32, y: f32 } {
    return .{
        .x = window_x / (self.window_width / 2.0),
        .y = window_y / (self.window_height / 2.0),
    };
}

/// Transform a point with camera offset applied, then to clip space
pub fn worldToClip(self: RenderContext, world_x: f32, world_y: f32) struct { x: f32, y: f32 } {
    const cam_rel_x = world_x - self.camera_offset.x;
    const cam_rel_y = world_y - self.camera_offset.y;
    return self.windowToClip(cam_rel_x, cam_rel_y);
}

/// Rotate a 2D point using standard rotation matrix
/// Uses 2D rotation matrix from 4x4 homogeneous transform (top-left 2x2):
/// | cos(θ)  -sin(θ) |
/// | sin(θ)   cos(θ) |
pub fn rotatePoint(x: f32, y: f32, cos_rot: f32, sin_rot: f32) struct { x: f32, y: f32 } {
    return .{
        .x = x * cos_rot - y * sin_rot,
        .y = x * sin_rot + y * cos_rot,
    };
}

/// Map z-coordinate to normalized depth [0, 1] for depth testing
/// Lower depth values are closer to camera (rendered on top)
/// z=0 → depth=0.5 (near), z=-1 → depth=1.0 (far), z=1 → depth=0.0 (very near)
pub fn zToDepth(z: f32) f32 {
    return std.math.clamp(0.5 - z * 0.5, 0.0, 1.0);
}

/// Allocate memory for a buffer with specified properties
pub fn allocateMemory(
    self: RenderContext,
    vkd: anytype,
    requirements: vk.MemoryRequirements,
    properties: vk.MemoryPropertyFlags,
) !vk.DeviceMemory {
    const mem_props = self.dev_res.memory_properties;

    var i: u32 = 0;
    while (i < mem_props.memory_type_count) : (i += 1) {
        if ((requirements.memory_type_bits & (@as(u32, 1) << @intCast(i))) != 0) {
            const type_props = mem_props.memory_types[i].property_flags;

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

/// Upload vertex data to a device buffer using staging buffer
pub fn uploadToBuffer(
    self: RenderContext,
    vkd: anytype,
    comptime T: type,
    dst_buffer: vk.Buffer,
    data: []const T,
) !void {
    const size = @sizeOf(T) * data.len;

    const staging_buffer = try vkd.createBuffer(&.{
        .size = size,
        .usage = .{ .transfer_src_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer vkd.destroyBuffer(staging_buffer, null);

    const mem_reqs = vkd.getBufferMemoryRequirements(staging_buffer);
    const staging_memory = try self.allocateMemory(vkd, mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    defer vkd.freeMemory(staging_memory, null);

    try vkd.bindBufferMemory(staging_buffer, staging_memory, 0);

    {
        const mapped = try vkd.mapMemory(staging_memory, 0, vk.WHOLE_SIZE, .{});
        defer vkd.unmapMemory(staging_memory);

        const gpu_data: [*]T = @ptrCast(@alignCast(mapped));
        @memcpy(gpu_data[0..data.len], data);
    }

    var cmdbuf_handle: vk.CommandBuffer = undefined;
    try vkd.allocateCommandBuffers(&.{
        .command_pool = self.cmd_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf_handle));
    defer vkd.freeCommandBuffers(self.cmd_pool, 1, @ptrCast(&cmdbuf_handle));

    try vkd.beginCommandBuffer(cmdbuf_handle, &.{ .flags = .{ .one_time_submit_bit = true } });

    const region = vk.BufferCopy{ .src_offset = 0, .dst_offset = 0, .size = size };
    vkd.cmdCopyBuffer(cmdbuf_handle, staging_buffer, dst_buffer, 1, @ptrCast(&region));

    try vkd.endCommandBuffer(cmdbuf_handle);

    const submit = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmdbuf_handle),
        .p_wait_dst_stage_mask = undefined,
    };

    const gfx_q = self.dev_res.graphics_queue.?;
    try vkd.queueSubmit(gfx_q, 1, @ptrCast(&submit), .null_handle);
    try vkd.queueWaitIdle(gfx_q);
}
