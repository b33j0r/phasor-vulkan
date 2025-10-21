const phasor_ecs = @import("phasor-ecs");

pub const glfw = @import("glfw");

// Ensure the GLFW wrapper module is referenced; placeholder for future setup
pub fn requireGlfwPlugin(_: *phasor_ecs.App) !void {
    // no-op for now; existence ensures the glfw module is pulled into the graph
}

pub const WindowPlugin = @import("WindowPlugin.zig");
