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
    /// Matches the viewport size in pixels for pixel-perfect 2d games and overlays
    /// Coordinates are in physical pixels, camera automatically accounts for DPI scale
    Viewport: struct {
        mode: enum {
            /// Top-left is (0,0), y increases downwards
            TopLeft,
            /// Center is (0,0), y increases upwards
            Center,
        } = .TopLeft,
        /// Override DPI scale (1.0 = no scaling, 2.0 = render at 2x resolution)
        /// If null, uses current ContentScale from system
        scale_override: ?f32 = null,
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
pub const Sprite3D = struct {
    /// The texture to render (passed by value from Assets resource)
    texture: *const assets.Texture,

    /// How to size the sprite
    size_mode: SizeMode = .Auto,

    pub const SizeMode = union(enum) {
        /// Automatically size sprite to match texture dimensions (pixel-perfect)
        Auto,
        /// Manually specify sprite dimensions
        Manual: struct {
            width: f32,
            height: f32,
        },
    };

    pub const __trait__ = Renderable;
};

pub const Renderable = struct {};

/// Vertex data for sprite rendering
pub const SpriteVertex = struct {
    /// Position in 2D clip space [-1, 1]
    pos: [2]f32,
    /// Texture coordinates [0, 1]
    uv: [2]f32,
    /// RGBA color/tint
    color: [4]f32,
};

/// 3D Transform component (simplified for now)
pub const Transform3d = struct {
    translation: [3]f32 = .{ 0.0, 0.0, 0.0 },
    rotation: [3]f32 = .{ 0.0, 0.0, 0.0 },
    scale: [3]f32 = .{ 1.0, 1.0, 1.0 },
};

const std = @import("std");
const assets = @import("assets.zig");
