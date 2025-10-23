const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_glfw = @import("phasor-glfw");
const phasor_vulkan = @import("phasor-vulkan");

// Define our assets resource type
const GameAssets = struct {
    planet_texture: phasor_vulkan.Texture = .{
        .path = "examples/sprites/assets/planet05.png",
    },
    ship_texture: phasor_vulkan.Texture = .{
        .path = "examples/sprites/assets/playerShip1_orange.png",
    },
    orbitron_font: phasor_vulkan.Font = .{
        .path = "examples/sprites/assets/fonts/Orbitron-VariableFont_wght.ttf",
        .font_height = 48.0,
        .atlas_width = 512,
        .atlas_height = 512,
    },
};

fn setup_sprite(mut_commands: *phasor_ecs.Commands, r_assets: phasor_ecs.Res(GameAssets)) !void {
    // Create a camera entity with Viewport.Center mode and FollowShip component
    _ = try mut_commands.createEntity(.{
        FollowShip{},
        phasor_vulkan.Camera3d{
            .Viewport = .{
                .mode = .Center,
            },
        },
        phasor_vulkan.Transform3d{},
    });

    // Create a sprite entity with the planet texture
    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = 0.0, .z = -1.0 },
            .scale = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
        },
        phasor_vulkan.Sprite3D{
            .texture = &r_assets.ptr.planet_texture,
            .size_mode = .Auto, // Sprite will be sized to match texture dimensions
        },
    });

    // Create another sprite entity for the ship texture
    // Positioned above the planet, with PlayerShip component for physics
    _ = try mut_commands.createEntity(.{
        PlayerShip{
            .rotation = 0.0, // Start pointing right (0 degrees)
        },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -240.0, .y = 0.0, .z = 0.0 },
            .scale = .{ .x = 0.7, .y = 0.7, .z = 0.7 },
        },
        phasor_vulkan.Sprite3D{
            .texture = &r_assets.ptr.ship_texture,
            .size_mode = .Auto, // Sprite will be sized to match texture dimensions
        },
    });

    // Create text entity
    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -300.0, .y = -250.0, .z = 1.0 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "PHASOR VULKAN",
            .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        },
    });
}

// Component for the player ship with velocity and rotation
const PlayerShip = struct {
    velocity_x: f32 = 0.0,
    velocity_y: f32 = 0.0,
    rotation: f32 = 0.0, // radians, 0 = pointing right
};

// Tag component for camera that follows the ship
const FollowShip = struct {};

// System to make camera follow the ship
fn camera_follow_ship(
    q_camera: phasor_ecs.Query(.{ FollowShip, phasor_vulkan.Transform3d }),
    q_ship: phasor_ecs.Query(.{ PlayerShip, phasor_vulkan.Transform3d }),
) !void {
    // Find the ship
    var ship_it = q_ship.iterator();
    if (ship_it.next()) |ship_entity| {
        const ship_transform = ship_entity.get(phasor_vulkan.Transform3d).?;

        // Update all cameras that follow the ship
        var cam_it = q_camera.iterator();
        while (cam_it.next()) |cam_entity| {
            const cam_transform = cam_entity.get(phasor_vulkan.Transform3d).?;

            // Copy ship position to camera
            cam_transform.translation.x = ship_transform.translation.x;
            cam_transform.translation.y = ship_transform.translation.y;
        }
    }
}

// System to control the ship with Escape Velocity-like physics
fn control_ship(
    key_events: phasor_ecs.EventReader(phasor_glfw.InputPlugin.KeyDown),
    q_ship: phasor_ecs.Query(.{ PlayerShip, phasor_vulkan.Transform3d }),
) !void {
    const thrust: f32 = 0.05;
    const turn_rate: f32 = 0.05;  // Increased for testing
    const max_speed: f32 = 3.0;
    const friction: f32 = 0.99;

    var it = q_ship.iterator();
    if (it.next()) |entity| {
        var ship = entity.get(PlayerShip).?;
        var transform = entity.get(phasor_vulkan.Transform3d).?;

        // Track which keys are pressed this frame
        var thrust_forward = false;
        var thrust_reverse = false;
        var turn_left = false;
        var turn_right = false;

        // Process all key down events
        while (key_events.tryRecv()) |event| {
            switch (event.key) {
                .w => thrust_forward = true,
                .s => thrust_reverse = true,
                .a => turn_left = true,
                .d => turn_right = true,
                else => {},
            }
        }

        // Apply controls once per frame
        if (thrust_forward) {
            ship.velocity_x += @cos(ship.rotation) * thrust;
            ship.velocity_y += @sin(ship.rotation) * thrust;
        }
        if (thrust_reverse) {
            ship.velocity_x -= @cos(ship.rotation) * thrust * 0.5;
            ship.velocity_y -= @sin(ship.rotation) * thrust * 0.5;
        }
        if (turn_left) {
            ship.rotation -= turn_rate;  // Counter-clockwise
        }
        if (turn_right) {
            ship.rotation += turn_rate;  // Clockwise
        }

        // Cap velocity at max speed
        const speed = @sqrt(ship.velocity_x * ship.velocity_x + ship.velocity_y * ship.velocity_y);
        if (speed > max_speed) {
            ship.velocity_x = (ship.velocity_x / speed) * max_speed;
            ship.velocity_y = (ship.velocity_y / speed) * max_speed;
        }

        // Apply friction
        ship.velocity_x *= friction;
        ship.velocity_y *= friction;

        // Update position based on velocity
        transform.translation.x += ship.velocity_x;
        transform.translation.y += ship.velocity_y;

        // Update visual rotation to match ship rotation
        // Add pi/2 because sprite points up by default
        transform.rotation.z = ship.rotation + std.math.pi / 2.0;
    }
}

pub fn main() !u8 {
    var app = try phasor_ecs.App.default(std.heap.page_allocator);
    defer app.deinit();

    const window_plugin = phasor_glfw.WindowPlugin.init(.{
        .title = "Phasor Vulkan - PNG Texture Loading Demo",
        .width = 800,
        .height = 600,
    });
    try app.addPlugin(&window_plugin);

    // Add input plugin for keyboard controls
    var input_plugin = phasor_glfw.InputPlugin{};
    try app.addPlugin(&input_plugin);

    const vk_plugin = phasor_vulkan.VulkanPlugin.init(.{});
    try app.addPlugin(&vk_plugin);

    // Add asset plugin - loads PNG textures using zigimg
    var asset_plugin = phasor_vulkan.AssetPlugin(GameAssets){};
    try app.addPlugin(&asset_plugin);

    // Add system to setup the sprite (must run after assets are loaded)
    try app.addSystem("Startup", setup_sprite);

    // Add system to control the ship with WASD
    try app.addSystem("Update", control_ship);

    // Add system to make camera follow ship
    // Use a separate schedule to ensure it runs after ship updates
    _ = try app.addSchedule("CameraUpdate");
    try app.scheduleAfter("CameraUpdate", "Update");
    try app.scheduleBefore("CameraUpdate", "Render");
    try app.addSystem("CameraUpdate", camera_follow_ship);

    return try app.run();
}
