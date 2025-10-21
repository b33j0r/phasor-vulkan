pub const VulkanPlugin = @import("VulkanPlugin.zig");
// Optional exports if needed externally
pub const InstancePlugin = @import("instance/InstancePlugin.zig");
pub const DevicePlugin = @import("device/DevicePlugin.zig");
pub const SwapchainPlugin = @import("swapchain/SwapchainPlugin.zig");
pub const RenderPlugin = @import("render/RenderPlugin.zig");

// Export components
const components = @import("components.zig");
pub const Triangle = components.Triangle;
pub const Vertex = components.Vertex;
pub const Camera3d = components.Camera3d;
pub const ProjectionMode = components.ProjectionMode;
pub const Viewport3d = components.Viewport3d;
pub const Viewport3dN = components.Viewport3dN;
pub const Layer3d = components.Layer3d;
pub const Layer3dN = components.Layer3dN;
