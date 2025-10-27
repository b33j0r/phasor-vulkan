const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_glfw = @import("phasor-glfw");
const phasor_common = @import("phasor-common");
const components = @import("components.zig");
const glfw = @import("glfw").c;

const Transform3d = components.Transform3d;
const DeltaTime = @import("TimePlugin.zig").DeltaTime;
const Window = phasor_glfw.WindowPlugin.Window;

/// FPS controller component for first-person camera control
pub const FpsController = struct {
    /// Mouse sensitivity (radians per pixel)
    mouse_sensitivity: f32 = 0.002,
    /// Movement speed (units per second)
    move_speed: f32 = 5.0,
    /// Current yaw angle (rotation around Y axis)
    yaw: f32 = 0.0,
    /// Current pitch angle (rotation around X axis, clamped)
    pitch: f32 = 0.0,
    /// Whether the controller is paused (disables input)
    paused: bool = false,
    /// Whether mouse look is enabled
    enabled: bool = true,
    /// Previous mouse position
    last_mouse_x: f64 = 0.0,
    last_mouse_y: f64 = 0.0,
    first_mouse: bool = true,
};

const Plugin = @This();

pub fn build(plugin: *const Plugin, app: *phasor_ecs.App) !void {
    _ = plugin;

    try app.addSystem("Update", fps_pause_system);
    try app.addSystem("Update", fps_mouselook_system);
    try app.addSystem("Update", fps_movement_system);
}

fn fps_pause_system(
    q_controller: phasor_ecs.Query(.{FpsController}),
    key_events: phasor_ecs.EventReader(phasor_glfw.InputPlugin.KeyDown),
    r_window: phasor_ecs.ResOpt(Window),
) !void {
    var it = q_controller.iterator();
    if (it.next()) |entity| {
        var controller = entity.get(FpsController).?;

        // Check for ESC key to toggle pause
        while (key_events.tryRecv()) |event| {
            if (event.key == .escape) {
                controller.paused = !controller.paused;

                // Toggle cursor mode
                if (r_window.ptr) |window_res| {
                    if (window_res.handle) |handle| {
                        if (controller.paused) {
                            glfw.glfwSetInputMode(handle, glfw.GLFW_CURSOR, glfw.GLFW_CURSOR_NORMAL);
                        } else {
                            glfw.glfwSetInputMode(handle, glfw.GLFW_CURSOR, glfw.GLFW_CURSOR_DISABLED);
                            controller.first_mouse = true; // Reset mouse tracking
                        }
                    }
                }
            }
        }
    }
}

fn fps_mouselook_system(
    q_controller: phasor_ecs.Query(.{ FpsController, Transform3d }),
    r_window: phasor_ecs.ResOpt(Window),
) !void {
    if (r_window.ptr) |window_res| {
        if (window_res.handle) |handle| {
            var it = q_controller.iterator();
            if (it.next()) |entity| {
                var controller = entity.get(FpsController).?;
                const transform = entity.get(Transform3d).?;

                if (!controller.enabled or controller.paused) return;

                // Get current mouse position
                var xpos: f64 = 0.0;
                var ypos: f64 = 0.0;
                glfw.glfwGetCursorPos(handle, &xpos, &ypos);

                // Initialize last position on first frame
                if (controller.first_mouse) {
                    controller.last_mouse_x = xpos;
                    controller.last_mouse_y = ypos;
                    controller.first_mouse = false;
                    // Disable cursor for FPS mode
                    glfw.glfwSetInputMode(handle, glfw.GLFW_CURSOR, glfw.GLFW_CURSOR_DISABLED);
                    return;
                }

                // Calculate mouse delta
                const delta_x = xpos - controller.last_mouse_x;
                const delta_y = ypos - controller.last_mouse_y;
                controller.last_mouse_x = xpos;
                controller.last_mouse_y = ypos;

                // Update yaw and pitch based on mouse delta
                controller.yaw -= @as(f32, @floatCast(delta_x)) * controller.mouse_sensitivity;
                controller.pitch -= @as(f32, @floatCast(delta_y)) * controller.mouse_sensitivity;

                // Clamp pitch to prevent camera flipping
                const max_pitch = std.math.pi / 2.0 - 0.01;
                controller.pitch = std.math.clamp(controller.pitch, -max_pitch, max_pitch);

                // Apply rotation to transform
                transform.rotation.y = controller.yaw;
                transform.rotation.x = controller.pitch;
            }
        }
    }
}

fn fps_movement_system(
    q_controller: phasor_ecs.Query(.{ FpsController, Transform3d }),
    key_events: phasor_ecs.EventReader(phasor_glfw.InputPlugin.KeyPressed),
    delta_time: phasor_ecs.Res(DeltaTime),
) !void {
    const dt = delta_time.ptr.seconds;

    var it = q_controller.iterator();
    if (it.next()) |entity| {
        const controller = entity.get(FpsController).?;
        const transform = entity.get(Transform3d).?;

        if (!controller.enabled or controller.paused) return;

        // Track movement input
        var move_forward = false;
        var move_backward = false;
        var move_left = false;
        var move_right = false;

        // Process key events
        while (key_events.tryRecv()) |event| {
            switch (event.key) {
                .w => move_forward = true,
                .s => move_backward = true,
                .a => move_left = true,
                .d => move_right = true,
                else => {},
            }
        }

        // Calculate movement direction based on yaw
        // Forward in XZ plane: (sin(yaw), cos(yaw))
        const forward_x = @sin(controller.yaw);
        const forward_z = @cos(controller.yaw);
        // Right is 90° clockwise from forward (in top-down view)
        const right_x = @cos(controller.yaw);
        const right_z = -@sin(controller.yaw);

        var velocity_x: f32 = 0.0;
        var velocity_z: f32 = 0.0;

        if (move_forward) {
            velocity_x += forward_x;
            velocity_z += forward_z;
        }
        if (move_backward) {
            velocity_x -= forward_x;
            velocity_z -= forward_z;
        }
        if (move_right) {
            velocity_x -= right_x;
            velocity_z -= right_z;
        }
        if (move_left) {
            velocity_x += right_x;
            velocity_z += right_z;
        }

        // Normalize and apply speed
        const mag = @sqrt(velocity_x * velocity_x + velocity_z * velocity_z);
        if (mag > 0.0) {
            velocity_x = (velocity_x / mag) * controller.move_speed * dt;
            velocity_z = (velocity_z / mag) * controller.move_speed * dt;

            transform.translation.x += velocity_x;
            transform.translation.z += velocity_z;
        }
    }
}
