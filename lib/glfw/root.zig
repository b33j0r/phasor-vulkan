//! Thin C wrapper for GLFW 3.4.

pub const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});
