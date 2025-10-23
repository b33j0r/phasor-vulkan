// ─────────────────────────────────────────────
// Shape Renderer Interface
// ─────────────────────────────────────────────
// Defines the interface that all shape renderers must implement.
// Each shape type (Triangle, Sprite, Circle, Rectangle, etc.) implements
// this interface to provide modular, self-contained rendering logic.

const std = @import("std");
const vk = @import("vulkan");
const RenderContext = @import("RenderContext.zig");

/// Resources allocated for a specific shape renderer
pub const ShapeResources = struct {
    pipeline_layout: vk.PipelineLayout,
    pipeline: vk.Pipeline,
    vertex_buffer: vk.Buffer,
    vertex_memory: vk.DeviceMemory,
    max_vertices: u32,

    /// Optional descriptor resources (used by textured shapes)
    descriptor_set_layout: ?vk.DescriptorSetLayout = null,
    descriptor_pool: ?vk.DescriptorPool = null,
};

/// Interface for shape renderers - all shape types implement these methods
pub fn ShapeRenderer(comptime Self: type) type {
    return struct {
        /// Initialize GPU resources (pipelines, buffers, etc.)
        pub fn init(
            vkd: anytype,
            dev_res: anytype,
            render_pass: vk.RenderPass,
            extent: vk.Extent2D,
            allocator: std.mem.Allocator,
        ) !ShapeResources {
            return Self.init(vkd, dev_res, render_pass, extent, allocator);
        }

        /// Clean up GPU resources
        pub fn deinit(vkd: anytype, resources: *const ShapeResources) void {
            return Self.deinit(vkd, resources);
        }

        /// Collect renderable entities and prepare vertex data
        /// Returns the number of vertices to render
        pub fn collect(
            ctx: *RenderContext,
            resources: *const ShapeResources,
            query: anytype,
        ) !u32 {
            return Self.collect(ctx, resources, query);
        }

        /// Record draw commands into command buffer
        pub fn record(
            ctx: *RenderContext,
            resources: *const ShapeResources,
            cmdbuf: vk.CommandBuffer,
            vertex_count: u32,
        ) void {
            return Self.record(ctx, resources, cmdbuf, vertex_count);
        }
    };
}
