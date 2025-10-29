const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_common = @import("phasor-common");
const components = @import("components.zig");

const Transform3d = components.Transform3d;
const DeltaTime = @import("TimePlugin.zig").DeltaTime;

/// Rigid body component for physics simulation
pub const RigidBody = struct {
    /// Velocity in world space
    velocity: phasor_common.Vec3 = .{},
    /// Gravity scale (0.0 = no gravity, 1.0 = normal gravity)
    gravity_scale: f32 = 1.0,
    /// Whether the body is kinematic (controlled by script, not physics)
    kinematic: bool = false,
};

/// Box collider component
pub const BoxCollider = struct {
    /// Half-extents of the box
    half_extents: phasor_common.Vec3,
    /// Whether this is a trigger (no collision response)
    is_trigger: bool = false,
};

/// Capsule collider for character controllers
pub const CapsuleCollider = struct {
    /// Radius of the capsule
    radius: f32,
    /// Height of the capsule (including hemispheres)
    height: f32,
    /// Whether this is a trigger
    is_trigger: bool = false,
};

const Plugin = @This();

/// Configuration for physics plugin
pub const Config = struct {
    /// Gravity acceleration (default: -9.81 m/s^2)
    gravity: f32 = -9.81,
};

config: Config,

pub fn init(config: Config) Plugin {
    return Plugin{ .config = config };
}

pub fn build(plugin: *const Plugin, app: *phasor_ecs.App) !void {
    try app.insertResource(PhysicsConfig{ .gravity = plugin.config.gravity });
    try app.addSystem("Update", apply_gravity_system);
    try app.addSystem("Update", integrate_velocity_system);
    try app.addSystem("Update", box_collision_system);
    try app.addSystem("Update", capsule_collision_system);
}

const PhysicsConfig = struct {
    gravity: f32,
};

fn apply_gravity_system(
    q_bodies: phasor_ecs.Query(.{ RigidBody, Transform3d }),
    delta_time: phasor_ecs.Res(DeltaTime),
    config: phasor_ecs.Res(PhysicsConfig),
) !void {
    const dt = delta_time.ptr.seconds;

    var it = q_bodies.iterator();
    while (it.next()) |entity| {
        var body = entity.get(RigidBody).?;

        if (body.kinematic) continue;

        // Apply gravity
        body.velocity.y += config.ptr.gravity * body.gravity_scale * dt;
    }
}

fn integrate_velocity_system(
    q_bodies: phasor_ecs.Query(.{ RigidBody, Transform3d }),
    delta_time: phasor_ecs.Res(DeltaTime),
) !void {
    const dt = delta_time.ptr.seconds;

    var it = q_bodies.iterator();
    while (it.next()) |entity| {
        const body = entity.get(RigidBody).?;
        const transform = entity.get(Transform3d).?;

        if (body.kinematic) continue;

        // Integrate velocity to position
        transform.translation.x += body.velocity.x * dt;
        transform.translation.y += body.velocity.y * dt;
        transform.translation.z += body.velocity.z * dt;
    }
}

fn box_collision_system(
    q_dynamic: phasor_ecs.Query(.{ RigidBody, Transform3d, BoxCollider }),
    q_static: phasor_ecs.Query(.{ Transform3d, BoxCollider }),
) !void {
    var it_dynamic = q_dynamic.iterator();
    while (it_dynamic.next()) |entity_a| {
        var body_a = entity_a.get(RigidBody).?;
        const transform_a = entity_a.get(Transform3d).?;
        const collider_a = entity_a.get(BoxCollider).?;

        if (body_a.kinematic or collider_a.is_trigger) continue;

        // Check against all static colliders
        var it_static = q_static.iterator();
        while (it_static.next()) |entity_b| {
            // Skip self-collision
            if (entity_a.id == entity_b.id) continue;

            const transform_b = entity_b.get(Transform3d).?;
            const collider_b = entity_b.get(BoxCollider).?;

            if (collider_b.is_trigger) continue;

            // AABB collision detection and response
            const overlap = checkAABBOverlap(
                transform_a.translation,
                collider_a.half_extents,
                transform_b.translation,
                collider_b.half_extents,
            );

            if (overlap) |penetration| {
                // Resolve collision by moving out of penetration
                transform_a.translation.x += penetration.x;
                transform_a.translation.y += penetration.y;
                transform_a.translation.z += penetration.z;

                // Stop velocity in the direction of collision
                if (@abs(penetration.x) > 0.001) {
                    body_a.velocity.x = 0.0;
                }
                if (@abs(penetration.y) > 0.001) {
                    body_a.velocity.y = 0.0;
                }
                if (@abs(penetration.z) > 0.001) {
                    body_a.velocity.z = 0.0;
                }
            }
        }
    }
}

fn capsule_collision_system(
    q_dynamic: phasor_ecs.Query(.{ RigidBody, Transform3d, CapsuleCollider }),
    q_static: phasor_ecs.Query(.{ Transform3d, BoxCollider }),
) !void {
    var it_dynamic = q_dynamic.iterator();
    while (it_dynamic.next()) |entity_a| {
        var body_a = entity_a.get(RigidBody).?;
        const transform_a = entity_a.get(Transform3d).?;
        const capsule = entity_a.get(CapsuleCollider).?;

        if (body_a.kinematic or capsule.is_trigger) continue;

        // Check against all static box colliders
        var it_static = q_static.iterator();
        while (it_static.next()) |entity_b| {
            // Skip self-collision
            if (entity_a.id == entity_b.id) continue;

            const transform_b = entity_b.get(Transform3d).?;
            const box = entity_b.get(BoxCollider).?;

            if (box.is_trigger) continue;

            // Simplified capsule-box collision (treat capsule as sphere at center)
            const overlap = checkSphereBoxOverlap(
                transform_a.translation,
                capsule.radius,
                transform_b.translation,
                box.half_extents,
            );

            if (overlap) |penetration| {
                // Resolve collision
                transform_a.translation.x += penetration.x;
                transform_a.translation.y += penetration.y;
                transform_a.translation.z += penetration.z;

                // Stop velocity in the direction of collision
                if (@abs(penetration.x) > 0.001) {
                    body_a.velocity.x = 0.0;
                }
                if (@abs(penetration.y) > 0.001) {
                    body_a.velocity.y = 0.0;
                }
                if (@abs(penetration.z) > 0.001) {
                    body_a.velocity.z = 0.0;
                }
            }
        }
    }
}

fn checkAABBOverlap(
    pos_a: phasor_common.Vec3,
    half_a: phasor_common.Vec3,
    pos_b: phasor_common.Vec3,
    half_b: phasor_common.Vec3,
) ?phasor_common.Vec3 {
    const dx = pos_a.x - pos_b.x;
    const dy = pos_a.y - pos_b.y;
    const dz = pos_a.z - pos_b.z;

    const overlap_x = (half_a.x + half_b.x) - @abs(dx);
    const overlap_y = (half_a.y + half_b.y) - @abs(dy);
    const overlap_z = (half_a.z + half_b.z) - @abs(dz);

    // No overlap if any axis is separated
    if (overlap_x < 0 or overlap_y < 0 or overlap_z < 0) {
        return null;
    }

    // Find minimum penetration axis
    var penetration = phasor_common.Vec3{};

    if (overlap_x < overlap_y and overlap_x < overlap_z) {
        // X axis has minimum penetration
        penetration.x = if (dx > 0) overlap_x else -overlap_x;
    } else if (overlap_y < overlap_z) {
        // Y axis has minimum penetration
        penetration.y = if (dy > 0) overlap_y else -overlap_y;
    } else {
        // Z axis has minimum penetration
        penetration.z = if (dz > 0) overlap_z else -overlap_z;
    }

    return penetration;
}

fn checkSphereBoxOverlap(
    sphere_pos: phasor_common.Vec3,
    sphere_radius: f32,
    box_pos: phasor_common.Vec3,
    box_half: phasor_common.Vec3,
) ?phasor_common.Vec3 {
    // Find closest point on box to sphere center
    const closest_x = std.math.clamp(sphere_pos.x, box_pos.x - box_half.x, box_pos.x + box_half.x);
    const closest_y = std.math.clamp(sphere_pos.y, box_pos.y - box_half.y, box_pos.y + box_half.y);
    const closest_z = std.math.clamp(sphere_pos.z, box_pos.z - box_half.z, box_pos.z + box_half.z);

    // Calculate distance from closest point to sphere center
    const dx = sphere_pos.x - closest_x;
    const dy = sphere_pos.y - closest_y;
    const dz = sphere_pos.z - closest_z;
    const dist_sq = dx * dx + dy * dy + dz * dz;

    // Check if sphere overlaps with box
    if (dist_sq > sphere_radius * sphere_radius) {
        return null;
    }

    // Calculate penetration depth and direction
    const dist = @sqrt(dist_sq);
    if (dist < 0.0001) {
        // Sphere center is inside box, push along closest axis
        return phasor_common.Vec3{ .y = sphere_radius };
    }

    const penetration_depth = sphere_radius - dist;
    const normal_x = dx / dist;
    const normal_y = dy / dist;
    const normal_z = dz / dist;

    // Check if this is a slope (normal has significant Y component but also horizontal)
    // Slopes have upward-facing normals (normal_y > 0) with horizontal components
    const is_slope = normal_y > 0.3 and (normal_x * normal_x + normal_z * normal_z) > 0.1;

    if (is_slope) {
        // For slopes, push primarily upward to allow walking
        return phasor_common.Vec3{
            .x = 0.0,
            .y = penetration_depth / normal_y, // Adjust to walk up the slope
            .z = 0.0,
        };
    }

    return phasor_common.Vec3{
        .x = normal_x * penetration_depth,
        .y = normal_y * penetration_depth,
        .z = normal_z * penetration_depth,
    };
}
