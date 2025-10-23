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

/// A 3D camera component with orthographic projection.
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
    /// Window coordinates are DPI-independent (800x600 on all displays)
    /// The system automatically scales to fill the physical framebuffer
    Viewport: struct {
        mode: enum {
            /// Top-left is (0,0), y increases downwards
            TopLeft,
            /// Center is (0,0), y increases upwards
            Center,
        } = .TopLeft,
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

/// Color with 4 components (RGBA)
pub const Color4 = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

/// Vertex data for sprite rendering
pub const SpriteVertex = extern struct {
    /// Position in clip space [-1, 1] with depth
    pos: phasor_common.Vec3,
    /// Texture coordinates [0, 1]
    uv: phasor_common.Vec2,
    /// RGBA color/tint
    color: Color4,
};

/// 3D Transform component (simplified for now)
/// Translation is in window coordinates for Viewport camera
pub const Transform3d = struct {
    translation: phasor_common.Vec3 = .{},
    rotation: phasor_common.Vec3 = .{},
    scale: phasor_common.Vec3 = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
};

/// Text component for rendering text strings using a font atlas
pub const Text = struct {
    font: *const assets.Font,
    text: [:0]const u8,
    color: Color4 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },

    pub const __trait__ = Renderable;
};

/// Circle component for rendering filled circles
/// Position and size are in window coordinates (DPI-independent)
pub const Circle = struct {
    /// Radius in window coordinates (logical pixels)
    radius: f32,
    /// Circle color with alpha
    color: Color4 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },

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
    color: Color4 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },

    pub const __trait__ = Renderable;
};

/// Vertex data for colored shape rendering (circles, rectangles)
pub const ColorVertex = extern struct {
    /// Position in clip space [-1, 1] with depth
    pos: phasor_common.Vec3,
    /// RGBA color
    color: Color4,
};

/// Mesh component for 3D rendering with vertex and index buffers
pub const Mesh = struct {
    /// Vertex data
    vertices: []const MeshVertex,
    /// Index data (triangles)
    indices: []const u32,

    pub const __trait__ = Renderable;
};

/// Vertex data for 3D mesh rendering
pub const MeshVertex = extern struct {
    /// Position in 3D space
    pos: phasor_common.Vec3,
    /// Normal vector
    normal: phasor_common.Vec3,
    /// Vertex color
    color: Color4,
};

/// Material component for mesh rendering
pub const Material = struct {
    /// Base color/tint
    color: Color4 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
};

/// Orbit camera controller component
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

const std = @import("std");
const assets = @import("assets.zig");
const phasor_common = @import("phasor-common");
