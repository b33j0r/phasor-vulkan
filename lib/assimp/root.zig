// Thin C wrapper for Assimp (Open Asset Import Library)
// Follows the pattern used by lib/glfw/root.zig and lib/stb_truetype/root.zig
// This module only exposes the C API via @cImport.
// High-level Zig wrappers live in lib/phasor-assimp.

pub const c = @cImport({
    @cInclude("assimp/cimport.h");
    @cInclude("assimp/scene.h");
    @cInclude("assimp/material.h");
    @cInclude("assimp/postprocess.h");
});
