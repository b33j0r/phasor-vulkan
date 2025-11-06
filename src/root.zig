pub const AllocatorPlugin = @import("AllocatorPlugin.zig");
pub const Allocator = AllocatorPlugin.Allocator;

pub const VulkanPlugin = @import("VulkanPlugin.zig");
pub const TimePlugin = @import("TimePlugin.zig");
pub const FpsControllerPlugin = @import("FpsControllerPlugin.zig");
pub const PhysicsPlugin = @import("PhysicsPlugin.zig");
pub const ParentPlugin = @import("ParentPlugin.zig");
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
pub const Shader = assets.Shader;

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
pub const Color4 = @import("phasor-common").Color.F32;
pub const Circle = components.Circle;
pub const Rectangle = components.Rectangle;
pub const Mesh = components.Mesh;
pub const MeshVertex = components.MeshVertex;
pub const MeshNode = components.MeshNode;
pub const Material = components.Material;
pub const CustomShader = components.CustomShader;
pub const OrbitCamera = components.OrbitCamera;

// Export FPS controller components
const fps_controller = @import("FpsControllerPlugin.zig");
pub const FpsController = fps_controller.FpsController;
pub const FpsCameraHead = fps_controller.FpsCameraHead;

// Export physics components
const physics = @import("PhysicsPlugin.zig");
pub const RigidBody = physics.RigidBody;
pub const BoxCollider = physics.BoxCollider;
pub const CapsuleCollider = physics.CapsuleCollider;

// Export time resources
const time_plugin = @import("TimePlugin.zig");
pub const DeltaTime = time_plugin.DeltaTime;
pub const ElapsedTime = time_plugin.ElapsedTime;

// Export parent hierarchy components
const parent_plugin = @import("ParentPlugin.zig");
pub const Parent = parent_plugin.Parent;
pub const LocalTransform3d = parent_plugin.LocalTransform3d;

// Assimp model import exports (high-level API)
pub const Model = @import("import/Assimp.zig").Model;
pub const loadGlb = @import("import/Assimp.zig").loadGlb;
pub const loadGltf = @import("import/Assimp.zig").loadGltf;
