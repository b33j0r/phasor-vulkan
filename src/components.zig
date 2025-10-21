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
pub const Camera3d = struct {
    mode: ProjectionMode = .Orthographic,
    /// For orthographic: defines the half-width/height
    ortho_size: f32 = 1.0,
    /// For perspective: field of view in radians
    fov: f32 = std.math.pi / 4.0,
    near: f32 = 0.1,
    far: f32 = 100.0,
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
