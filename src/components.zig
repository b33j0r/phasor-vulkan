// ECS components for Vulkan rendering

/// A Viewport3d component that specifies a 3D viewport
/// with index V. This corresponds to a ViewportConfig(V) resource.
pub fn Viewport3d(V: i32) type {
    return struct {
        pub const __group_key__ = V;
        pub const __trait__ = Viewport3dN;
    };
}

pub const Viewport3dN = struct {};

/// A component that enables an entity to be rendered in a specific layer.
pub fn Layer3d(N: i32) type {
    return struct {
        pub const __group_key__ = N;
        pub const __trait__ = Layer3dN;
    };
}

/// A grouping trait for Layer3d components.
pub const Layer3dN = struct {};

/// 3D camera component.
pub const Camera3d = union(enum) {
    /// An orthographic camera with traditional left/right/top/bottom bounds
    Orthographic: struct {
        left: f32 = -1.0,
        right: f32 = 1.0,
        bottom: f32 = -1.0,
        top: f32 = 1.0,
        near: f32 = 0.1,
        far: f32 = 100.0,
    },
    /// A perspective camera
    Perspective: struct {
        /// Field of view in radians
        fov: f32 = std.math.pi / 4.0,
        near: f32 = 0.1,
        far: f32 = 100.0,
    },
    /// Pixel-perfect camera using window coordinates
    /// Window coordinates are DPI-independent
    /// The system automatically scales to fill the physical framebuffer
    Viewport: struct {
        mode: enum {
            /// Top-left is (0,0), y increases downwards
            TopLeft,
            /// Center is (0,0), y increases upwards
            Center,
        } = .TopLeft,
        near: f32 = -10.0,
        far: f32 = 10.0,
    },
};

pub const ProjectionMode = enum {
    Orthographic,
    Perspective,
};

/// Triangle renderable component
pub const Triangle = struct {
    /// Three vertices defining the triangle
    vertices: [3]Vertex,
};

/// Vertex data for triangle rendering
pub const Vertex = struct {
    /// Position in 2D clip space [-1, 1]
    pos: [2]f32,
    /// RGB color
    color: [3]f32,
};

/// Sprite3D component for rendering textured quads
/// All dimensions and positions are in window coordinates (DPI-independent)
pub const Sprite3D = struct {
    /// The texture to render (passed by value from Assets resource)
    texture: *const assets.Texture,

    /// How to size the sprite
    size_mode: SizeMode = .Auto,

    pub const SizeMode = union(enum) {
        /// Automatically size sprite to match texture pixel dimensions
        /// A 1280x1280 texture = 1280x1280 window units
        Auto,
        /// Manually specify sprite dimensions in window coordinates
        Manual: struct {
            width: f32,
            height: f32,
        },
    };

    pub const __trait__ = Renderable;
};

pub const Renderable = struct {};

/// Vertex data for sprite rendering
pub const SpriteVertex = extern struct {
    /// Position in clip space [-1, 1] with depth
    pos: phasor_common.Vec3,
    /// Texture coordinates [0, 1]
    uv: phasor_common.Vec2,
    /// RGBA color/tint
    color: phasor_common.Color.F32,
};

/// 3D Transform
/// Translation is in window coordinates for Viewport camera
pub const Transform3d = struct {
    translation: phasor_common.Vec3 = .{},
    rotation: phasor_common.Vec3 = .{},
    scale: phasor_common.Vec3 = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
};

/// Horizontal alignment for text rendering
pub const HorizontalAlignment = enum {
    Left,
    Center,
    Right,
};

/// Vertical alignment for text rendering
pub const VerticalAlignment = enum {
    Top,
    Center,
    Baseline,
    Bottom,
};

/// Text component for rendering text strings using a font atlas
pub const Text = struct {
    font: *const assets.Font,
    text: [:0]const u8,
    color: phasor_common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    horizontal_alignment: HorizontalAlignment = .Left,
    vertical_alignment: VerticalAlignment = .Baseline,
    /// If true, text was heap-allocated and should be freed in deinit
    owns_text: bool = false,
    /// Allocator used to allocate the text (only used if owns_text is true)
    allocator: ?std.mem.Allocator = null,

    pub const __trait__ = Renderable;

    /// Initialize Text with a static string literal (no allocation)
    pub fn initStatic(font: *const assets.Font, text: [:0]const u8, color: phasor_common.Color.F32) Text {
        return .{
            .font = font,
            .text = text,
            .color = color,
            .owns_text = false,
            .allocator = null,
        };
    }

    /// Initialize Text with a heap-allocated dynamic string
    /// The Text component takes ownership and will free the string in deinit
    pub fn initDynamic(font: *const assets.Font, text: [:0]const u8, color: phasor_common.Color.F32, allocator: std.mem.Allocator) Text {
        return .{
            .font = font,
            .text = text,
            .color = color,
            .owns_text = true,
            .allocator = allocator,
        };
    }

    /// Called by phasor-ecs when component is replaced or removed
    /// Provides RAII-like lifecycle management within the archetype database
    pub fn deinit(self: *Text) void {
        if (self.owns_text) {
            if (self.allocator) |alloc| {
                alloc.free(self.text);
            }
            self.owns_text = false;
        }
    }
};

/// Circle component for rendering filled circles
/// Position and size are in window coordinates (DPI-independent)
pub const Circle = struct {
    /// Radius in window coordinates (logical pixels)
    radius: f32,
    /// Circle color with alpha
    color: phasor_common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },

    pub const __trait__ = Renderable;
};

/// Rectangle component for rendering filled rectangles
/// Position and size are in window coordinates (DPI-independent)
pub const Rectangle = struct {
    /// Width in window coordinates (logical pixels)
    width: f32,
    /// Height in window coordinates (logical pixels)
    height: f32,
    /// Rectangle color with alpha
    color: phasor_common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },

    pub const __trait__ = Renderable;
};

/// Vertex data for colored shape rendering (circles, rectangles)
pub const ColorVertex = extern struct {
    /// Position in clip space [-1, 1] with depth
    pos: phasor_common.Vec3,
    /// RGBA color
    color: phasor_common.Color.F32,
};

/// Mesh component for 3D rendering with vertex and index buffers
pub const Mesh = struct {
    /// Vertex data
    vertices: []const MeshVertex,
    /// Index data (triangles)
    indices: []const u32,

    pub const __trait__ = Renderable;
};

/// MeshNode component for hierarchical mesh structures (e.g., GLTF scenes)
/// This allows a mesh to be part of a scene graph with parent-child relationships
pub const MeshNode = struct {
    /// Optional name for this node (useful for debugging and identification)
    name: ?[]const u8 = null,
    /// Parent entity ID (if this is a child node)
    parent: ?u64 = null,
    /// Local transform relative to parent (if parent exists)
    /// If no parent, this is the world transform
    local_transform: Transform3d = .{},
};

/// Vertex data for 3D mesh rendering
pub const MeshVertex = extern struct {
    /// Position in 3D space
    pos: phasor_common.Vec3,
    /// Normal vector
    normal: phasor_common.Vec3,
    /// Texture coordinates
    uv: phasor_common.Vec2 = .{ .x = 0.0, .y = 0.0 },
    /// Vertex color
    color: phasor_common.Color.F32,
};

/// Material component for mesh rendering
pub const Material = struct {
    /// Base color/tint
    color: phasor_common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    /// Optional texture
    texture: ?*const assets.Texture = null,
};

/// CustomShader component for using custom shader pipelines
/// When attached to a mesh entity, the renderer will use the custom shader instead of the default
pub const CustomShader = struct {
    /// Reference to the shader asset
    shader: *const assets.Shader,
};

/// Orbit camera controller component (pure data)
pub const OrbitCamera = struct {
    /// Distance from target
    distance: f32 = 5.0,
    /// Rotation speed in radians per second
    rotation_speed: f32 = 1.0,
    /// Current angle around target
    angle: f32 = 0.0,
    /// Target position to orbit around
    target: phasor_common.Vec3 = .{},
};

/// Directional light component for simple lighting in mesh shader
/// The vector points from the light toward the scene (i.e., light direction)
/// It will be normalized by the renderer when uploaded.
pub const DirectionalLight = struct {
    dir: phasor_common.Vec3 = .{ .x = 0.5, .y = -0.7, .z = 0.3 },
};

const std = @import("std");
const assets = @import("assets.zig");
const phasor_common = @import("phasor-common");
