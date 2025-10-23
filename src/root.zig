pub const VulkanPlugin = @import("VulkanPlugin.zig");
// Optional exports if needed externally
pub const InstancePlugin = @import("instance/InstancePlugin.zig");
pub const DevicePlugin = @import("device/DevicePlugin.zig");
pub const SwapchainPlugin = @import("swapchain/SwapchainPlugin.zig");
pub const RenderPlugin = @import("render/RenderPlugin.zig");

// Export assets system
const assets = @import("assets.zig");
pub const AssetPlugin = assets.AssetPlugin;
pub const Texture = assets.Texture;
pub const Texture2D = assets.Texture; // Alias for use in asset structs
pub const Font = assets.Font;

// Export components
const components = @import("components.zig");
pub const Triangle = components.Triangle;
pub const Vertex = components.Vertex;
pub const Sprite3D = components.Sprite3D;
pub const SpriteVertex = components.SpriteVertex;
pub const Renderable = components.Renderable;
pub const Transform3d = components.Transform3d;
pub const Camera3d = components.Camera3d;
pub const ProjectionMode = components.ProjectionMode;
pub const Viewport3d = components.Viewport3d;
pub const Viewport3dN = components.Viewport3dN;
pub const Layer3d = components.Layer3d;
pub const Layer3dN = components.Layer3dN;
pub const Text = components.Text;
pub const Color4 = components.Color4;
