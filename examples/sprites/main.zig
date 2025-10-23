const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_glfw = @import("phasor-glfw");
const phasor_vulkan = @import("phasor-vulkan");
const phasor_common = @import("phasor-common");

// Define our assets resource type
const GameAssets = struct {
    planet_texture: phasor_vulkan.Texture = .{
        .path = "examples/sprites/assets/planet05.png",
    },
    ship_orange: phasor_vulkan.Texture = .{
        .path = "examples/sprites/assets/playerShip1_orange.png",
    },
    ship_blue: phasor_vulkan.Texture = .{
        .path = "examples/sprites/assets/playerShip2_blue.png",
    },
    ship_green: phasor_vulkan.Texture = .{
        .path = "examples/sprites/assets/playerShip2_green.png",
    },
    ship_orange2: phasor_vulkan.Texture = .{
        .path = "examples/sprites/assets/playerShip2_orange.png",
    },
    ship_red: phasor_vulkan.Texture = .{
        .path = "examples/sprites/assets/playerShip2_red.png",
    },
    orbitron_font: phasor_vulkan.Font = .{
        .path = "examples/sprites/assets/fonts/Orbitron-VariableFont_wght.ttf",
        .font_height = 48.0,
        .atlas_width = 512,
        .atlas_height = 512,
    },
};

// Ship class definitions - tweakable parameters
const ShipClass = struct {
    name: []const u8,
    thrust: f32, // units per second squared
    turn_rate: f32, // radians per second
    max_speed: f32, // units per second
    friction: f32, // friction coefficient per frame
};

const ShipClasses = struct {
    fighter: ShipClass = .{
        .name = "Fighter",
        .thrust = 5000.0,
        .turn_rate = 3.0,
        .max_speed = 300.0,
        .friction = 0.98,
    },
    interceptor: ShipClass = .{
        .name = "Interceptor",
        .thrust = 6000.0,
        .turn_rate = 4.0,
        .max_speed = 400.0,
        .friction = 0.97,
    },
    freighter: ShipClass = .{
        .name = "Freighter",
        .thrust = 3000.0,
        .turn_rate = 2.0,
        .max_speed = 200.0,
        .friction = 0.99,
    },
    scout: ShipClass = .{
        .name = "Scout",
        .thrust = 4500.0,
        .turn_rate = 3.5,
        .max_speed = 350.0,
        .friction = 0.975,
    },
};

fn setup_sprite(
    mut_commands: *phasor_ecs.Commands,
    r_assets: phasor_ecs.Res(GameAssets),
    r_ship_classes: phasor_ecs.Res(ShipClasses),
    r_prng: phasor_ecs.ResMut(phasor_common.Prng),
) !void {
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

    // Create three planets positioned in a triangle
    const planet_positions = [_]phasor_common.Vec3{
        .{ .x = 0.0, .y = 0.0, .z = -1.0 },
        .{ .x = 800.0, .y = 600.0, .z = -1.0 },
        .{ .x = -800.0, .y = 600.0, .z = -1.0 },
    };

    for (planet_positions) |pos| {
        _ = try mut_commands.createEntity(.{
            Planet{},
            phasor_vulkan.Transform3d{
                .translation = pos,
                .scale = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
            },
            phasor_vulkan.Sprite3D{
                .texture = &r_assets.ptr.planet_texture,
                .size_mode = .Auto,
            },
        });
    }

    // Create player ship with fighter class
    _ = try mut_commands.createEntity(.{
        PlayerShip{},
        Ship{
            .class = &r_ship_classes.ptr.fighter,
        },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -240.0, .y = 0.0, .z = 0.0 },
            .scale = .{ .x = 0.7, .y = 0.7, .z = 0.7 },
        },
        phasor_vulkan.Sprite3D{
            .texture = &r_assets.ptr.ship_orange,
            .size_mode = .Auto,
        },
    });

    // Create NPC ships with different classes
    const npc_configs = [_]struct {
        texture: *const phasor_vulkan.Texture,
        class: *const ShipClass,
        start_pos: phasor_common.Vec3,
    }{
        .{ .texture = &r_assets.ptr.ship_blue, .class = &r_ship_classes.ptr.interceptor, .start_pos = .{ .x = 200.0, .y = -100.0, .z = 0.0 } },
        .{ .texture = &r_assets.ptr.ship_green, .class = &r_ship_classes.ptr.freighter, .start_pos = .{ .x = -200.0, .y = 100.0, .z = 0.0 } },
        .{ .texture = &r_assets.ptr.ship_orange2, .class = &r_ship_classes.ptr.scout, .start_pos = .{ .x = 300.0, .y = 200.0, .z = 0.0 } },
        .{ .texture = &r_assets.ptr.ship_red, .class = &r_ship_classes.ptr.fighter, .start_pos = .{ .x = -300.0, .y = -200.0, .z = 0.0 } },
    };

    for (npc_configs) |config| {
        // Pick a random initial target planet
        const target_idx = r_prng.ptr.intLessThan(usize, planet_positions.len);

        _ = try mut_commands.createEntity(.{
            NpcShip{},
            Ship{
                .class = config.class,
            },
            Autopilot{
                .target_position = planet_positions[target_idx],
            },
            phasor_vulkan.Transform3d{
                .translation = config.start_pos,
                .scale = .{ .x = 0.7, .y = 0.7, .z = 0.7 },
            },
            phasor_vulkan.Sprite3D{
                .texture = config.texture,
                .size_mode = .Auto,
            },
        });
    }

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

// Component that references a ship class
const Ship = struct {
    class: *const ShipClass,
    velocity_x: f32 = 0.0,
    velocity_y: f32 = 0.0,
    rotation: f32 = -std.math.pi / 2.0, // radians, -π/2 = pointing up
};

// Tag component for player-controlled ship
const PlayerShip = struct {};

// Tag component for NPC ships
const NpcShip = struct {};

// Tag component for planets
const Planet = struct {};

// Component for autopilot navigation
const Autopilot = struct {
    target_position: phasor_common.Vec3,
    arrival_radius: f32 = 100.0, // How close to get before "arriving"
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

// System to control the player ship with Escape Velocity-like physics
fn control_ship(
    key_events: phasor_ecs.EventReader(phasor_glfw.InputPlugin.KeyDown),
    q_ship: phasor_ecs.Query(.{ PlayerShip, Ship, phasor_vulkan.Transform3d }),
    delta_time: phasor_ecs.Res(phasor_vulkan.DeltaTime),
) !void {
    const dt = delta_time.ptr.seconds;

    var it = q_ship.iterator();
    if (it.next()) |entity| {
        var ship = entity.get(Ship).?;
        var transform = entity.get(phasor_vulkan.Transform3d).?;

        const class = ship.class;
        const thrust = class.thrust;
        const turn_rate = class.turn_rate;
        const max_speed = class.max_speed;
        const friction = class.friction;

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

        // Apply controls with delta time for frame-rate independence
        if (thrust_forward) {
            ship.velocity_x += @cos(ship.rotation) * thrust * dt;
            ship.velocity_y += @sin(ship.rotation) * thrust * dt;
        }
        if (thrust_reverse) {
            ship.velocity_x -= @cos(ship.rotation) * thrust * 0.5 * dt;
            ship.velocity_y -= @sin(ship.rotation) * thrust * 0.5 * dt;
        }
        if (turn_left) {
            ship.rotation -= turn_rate * dt;  // Counter-clockwise
        }
        if (turn_right) {
            ship.rotation += turn_rate * dt;  // Clockwise
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

        // Update position based on velocity with delta time
        transform.translation.x += ship.velocity_x * dt;
        transform.translation.y += ship.velocity_y * dt;

        // Update visual rotation to match ship rotation
        transform.rotation.z = ship.rotation;
    }
}

// System to control NPC ships with autopilot
fn autopilot_system(
    q_ships: phasor_ecs.Query(.{ NpcShip, Ship, Autopilot, phasor_vulkan.Transform3d }),
    delta_time: phasor_ecs.Res(phasor_vulkan.DeltaTime),
) !void {
    const dt = delta_time.ptr.seconds;

    var it = q_ships.iterator();
    while (it.next()) |entity| {
        var ship = entity.get(Ship).?;
        const autopilot = entity.get(Autopilot).?;
        var transform = entity.get(phasor_vulkan.Transform3d).?;

        const class = ship.class;

        // Calculate direction to target
        const dx = autopilot.target_position.x - transform.translation.x;
        const dy = autopilot.target_position.y - transform.translation.y;
        const distance = @sqrt(dx * dx + dy * dy);

        // Calculate desired heading
        const desired_heading = std.math.atan2(dy, dx);

        // Normalize angle difference to [-π, π]
        var angle_diff = desired_heading - ship.rotation;
        while (angle_diff > std.math.pi) angle_diff -= 2.0 * std.math.pi;
        while (angle_diff < -std.math.pi) angle_diff += 2.0 * std.math.pi;

        // Turn towards target
        const turn_amount = class.turn_rate * dt;
        if (@abs(angle_diff) < turn_amount) {
            ship.rotation = desired_heading;
        } else if (angle_diff > 0) {
            ship.rotation += turn_amount;
        } else {
            ship.rotation -= turn_amount;
        }

        // Apply thrust if reasonably aligned with target
        if (@abs(angle_diff) < std.math.pi / 4.0 and distance > autopilot.arrival_radius) {
            // Apply thrust in current heading direction
            ship.velocity_x += @cos(ship.rotation) * class.thrust * dt;
            ship.velocity_y += @sin(ship.rotation) * class.thrust * dt;
        }

        // Apply braking if approaching target
        if (distance < autopilot.arrival_radius * 3.0) {
            const brake_factor = 0.95;
            ship.velocity_x *= brake_factor;
            ship.velocity_y *= brake_factor;
        }

        // Cap velocity at max speed
        const speed = @sqrt(ship.velocity_x * ship.velocity_x + ship.velocity_y * ship.velocity_y);
        if (speed > class.max_speed) {
            ship.velocity_x = (ship.velocity_x / speed) * class.max_speed;
            ship.velocity_y = (ship.velocity_y / speed) * class.max_speed;
        }

        // Apply friction
        ship.velocity_x *= class.friction;
        ship.velocity_y *= class.friction;

        // Update position based on velocity
        transform.translation.x += ship.velocity_x * dt;
        transform.translation.y += ship.velocity_y * dt;

        // Update visual rotation
        transform.rotation.z = ship.rotation;
    }
}

// System to give NPCs new waypoints when they reach their destination
fn npc_waypoint_planner(
    q_ships: phasor_ecs.Query(.{ NpcShip, Autopilot, phasor_vulkan.Transform3d }),
    q_planets: phasor_ecs.Query(.{ Planet, phasor_vulkan.Transform3d }),
    r_prng: phasor_ecs.ResMut(phasor_common.Prng),
) !void {
    // Collect all planet positions
    var planet_positions: [16]phasor_common.Vec3 = undefined;
    var planet_count: usize = 0;

    var planet_it = q_planets.iterator();
    while (planet_it.next()) |planet_entity| {
        if (planet_count >= planet_positions.len) break;
        const planet_transform = planet_entity.get(phasor_vulkan.Transform3d).?;
        planet_positions[planet_count] = planet_transform.translation;
        planet_count += 1;
    }

    if (planet_count == 0) return;

    // Check each NPC ship
    var it = q_ships.iterator();
    while (it.next()) |entity| {
        var autopilot = entity.get(Autopilot).?;
        const transform = entity.get(phasor_vulkan.Transform3d).?;

        // Check if ship has reached its destination
        const dx = autopilot.target_position.x - transform.translation.x;
        const dy = autopilot.target_position.y - transform.translation.y;
        const distance = @sqrt(dx * dx + dy * dy);

        if (distance < autopilot.arrival_radius) {
            // Pick a new random planet target (might be the same one, but that's ok)
            const new_target_idx = r_prng.ptr.intLessThan(usize, planet_count);
            autopilot.target_position = planet_positions[new_target_idx];
        }
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

    // Add time plugin for frame-rate independent physics
    var time_plugin = phasor_vulkan.TimePlugin{};
    try app.addPlugin(&time_plugin);

    // Add PRNG plugin for random number generation
    var prng_plugin = phasor_common.PrngPlugin.default();
    try app.addPlugin(&prng_plugin);

    // Add ship classes resource
    try app.insertResource(ShipClasses{});

    // Add asset plugin - loads PNG textures using zigimg
    var asset_plugin = phasor_vulkan.AssetPlugin(GameAssets){};
    try app.addPlugin(&asset_plugin);

    // Add system to setup the sprites (must run after assets are loaded)
    try app.addSystem("Startup", setup_sprite);

    // Add system to control the player ship with WASD
    try app.addSystem("Update", control_ship);

    // Add system to control NPC ships with autopilot
    try app.addSystem("Update", autopilot_system);

    // Add system to give NPCs new waypoints
    try app.addSystem("Update", npc_waypoint_planner);

    // Add system to make camera follow ship
    // Use a separate schedule to ensure it runs after ship updates
    _ = try app.addSchedule("CameraUpdate");
    try app.scheduleAfter("CameraUpdate", "Update");
    try app.scheduleBefore("CameraUpdate", "Render");
    try app.addSystem("CameraUpdate", camera_follow_ship);

    return try app.run();
}
