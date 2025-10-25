// ============================================================================
// Ball & Brick Physics Module
// ============================================================================
// A clean, ECS-oriented physics system for Pharkanoid.
// Separates physics logic from rendering to maintain proper collision detection
// independent of visual representation.

const std = @import("std");
const phasor_common = @import("phasor-common");

// ============================================================================
// Physics Components
// ============================================================================

/// Circle collider - represents circular collision bounds
pub const CircleCollider = struct {
    radius: f32,
};

/// AABB (Axis-Aligned Bounding Box) collider - represents rectangular collision bounds
pub const AABBCollider = struct {
    half_width: f32,
    half_height: f32,
};

/// Velocity component for moving entities
pub const Velocity = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
};

/// Collision result information
pub const CollisionResult = struct {
    collided: bool = false,
    normal_x: f32 = 0.0,
    normal_y: f32 = 0.0,
    overlap: f32 = 0.0,
};

// ============================================================================
// Collision Detection Functions
// ============================================================================

/// Test collision between a circle and an AABB
/// Returns collision information including normal and overlap distance
pub fn testCircleAABB(
    circle_x: f32,
    circle_y: f32,
    circle_radius: f32,
    aabb_x: f32,
    aabb_y: f32,
    aabb_half_width: f32,
    aabb_half_height: f32,
) CollisionResult {
    // Find the closest point on the AABB to the circle center
    const closest_x = @max(aabb_x - aabb_half_width, @min(circle_x, aabb_x + aabb_half_width));
    const closest_y = @max(aabb_y - aabb_half_height, @min(circle_y, aabb_y + aabb_half_height));

    // Calculate distance from circle center to closest point
    const dx = circle_x - closest_x;
    const dy = circle_y - closest_y;
    const distance_squared = dx * dx + dy * dy;
    const radius_squared = circle_radius * circle_radius;

    if (distance_squared >= radius_squared) {
        return .{ .collided = false };
    }

    // We have a collision
    const distance = @sqrt(distance_squared);
    const overlap = circle_radius - distance;

    // Calculate collision normal (direction to push circle out)
    var normal_x: f32 = 0.0;
    var normal_y: f32 = 0.0;

    if (distance > 0.0001) {
        // Normal case: normalize the vector from closest point to circle center
        normal_x = dx / distance;
        normal_y = dy / distance;
    } else {
        // Circle center is inside AABB - use penetration direction
        // Find which edge is closest
        const left_penetration = (aabb_x + aabb_half_width) - (circle_x - circle_radius);
        const right_penetration = (circle_x + circle_radius) - (aabb_x - aabb_half_width);
        const top_penetration = (aabb_y + aabb_half_height) - (circle_y - circle_radius);
        const bottom_penetration = (circle_y + circle_radius) - (aabb_y - aabb_half_height);

        const min_penetration = @min(
            @min(left_penetration, right_penetration),
            @min(top_penetration, bottom_penetration),
        );

        if (min_penetration == left_penetration) {
            normal_x = -1.0;
        } else if (min_penetration == right_penetration) {
            normal_x = 1.0;
        } else if (min_penetration == top_penetration) {
            normal_y = -1.0;
        } else {
            normal_y = 1.0;
        }
    }

    return .{
        .collided = true,
        .normal_x = normal_x,
        .normal_y = normal_y,
        .overlap = overlap,
    };
}

/// Reflect a velocity vector off a surface with the given normal
pub fn reflectVelocity(vel_x: f32, vel_y: f32, normal_x: f32, normal_y: f32) struct { x: f32, y: f32 } {
    // v_reflected = v - 2 * (v · n) * n
    const dot = vel_x * normal_x + vel_y * normal_y;
    return .{
        .x = vel_x - 2.0 * dot * normal_x,
        .y = vel_y - 2.0 * dot * normal_y,
    };
}

/// Resolve a circle-AABB collision by moving the circle out and reflecting velocity
pub fn resolveCircleAABB(
    circle_x: *f32,
    circle_y: *f32,
    vel: *Velocity,
    collision: CollisionResult,
) void {
    if (!collision.collided) return;

    // Move circle out of collision
    circle_x.* += collision.normal_x * collision.overlap;
    circle_y.* += collision.normal_y * collision.overlap;

    // Reflect velocity
    const reflected = reflectVelocity(vel.x, vel.y, collision.normal_x, collision.normal_y);
    vel.x = reflected.x;
    vel.y = reflected.y;
}

// ============================================================================
// Specialized Collision Functions
// ============================================================================

/// Test and resolve collision between a ball and a paddle with spin mechanics
/// Returns true if collision occurred
pub fn resolveBallPaddleCollision(
    ball_x: *f32,
    ball_y: *f32,
    ball_radius: f32,
    ball_vel: *Velocity,
    ball_speed: f32,
    paddle_x: f32,
    paddle_y: f32,
    paddle_half_width: f32,
    paddle_half_height: f32,
) bool {
    const collision = testCircleAABB(
        ball_x.*,
        ball_y.*,
        ball_radius,
        paddle_x,
        paddle_y,
        paddle_half_width,
        paddle_half_height,
    );

    if (!collision.collided) return false;

    // Only respond to collisions where ball is moving toward paddle
    const velocity_toward_paddle = ball_vel.x * collision.normal_x + ball_vel.y * collision.normal_y;
    if (velocity_toward_paddle >= 0) return false;

    // Move ball out of collision
    ball_x.* += collision.normal_x * collision.overlap;
    ball_y.* += collision.normal_y * collision.overlap;

    // Add spin based on where ball hits paddle (horizontal collisions only)
    if (@abs(collision.normal_y) > 0.5) {
        // Hit top or bottom of paddle
        const hit_position = (ball_x.* - paddle_x) / paddle_half_width; // -1 to 1
        const spin_strength = 0.7;

        ball_vel.x = hit_position * ball_speed * spin_strength;
        ball_vel.y = -@abs(ball_vel.y); // Ensure ball bounces upward

        // Normalize velocity to maintain constant speed
        const current_speed = @sqrt(ball_vel.x * ball_vel.x + ball_vel.y * ball_vel.y);
        if (current_speed > 0.0001) {
            ball_vel.x = (ball_vel.x / current_speed) * ball_speed;
            ball_vel.y = (ball_vel.y / current_speed) * ball_speed;
        }
    } else {
        // Hit side of paddle - simple reflection
        const reflected = reflectVelocity(ball_vel.x, ball_vel.y, collision.normal_x, collision.normal_y);
        ball_vel.x = reflected.x;
        ball_vel.y = reflected.y;
    }

    return true;
}

/// Test and resolve collision between a ball and a brick
/// Returns true if collision occurred
pub fn resolveBallBrickCollision(
    ball_x: *f32,
    ball_y: *f32,
    ball_radius: f32,
    ball_vel: *Velocity,
    brick_x: f32,
    brick_y: f32,
    brick_half_width: f32,
    brick_half_height: f32,
) bool {
    const collision = testCircleAABB(
        ball_x.*,
        ball_y.*,
        ball_radius,
        brick_x,
        brick_y,
        brick_half_width,
        brick_half_height,
    );

    if (!collision.collided) return false;

    // Resolve collision
    resolveCircleAABB(ball_x, ball_y, ball_vel, collision);
    return true;
}

/// Test and resolve collision between a ball and a wall
/// Returns true if collision occurred
pub fn resolveBallWallCollision(
    ball_x: *f32,
    ball_y: *f32,
    ball_radius: f32,
    ball_vel: *Velocity,
    wall_x: f32,
    wall_y: f32,
    wall_half_width: f32,
    wall_half_height: f32,
) bool {
    const collision = testCircleAABB(
        ball_x.*,
        ball_y.*,
        ball_radius,
        wall_x,
        wall_y,
        wall_half_width,
        wall_half_height,
    );

    if (!collision.collided) return false;

    // Resolve collision
    resolveCircleAABB(ball_x, ball_y, ball_vel, collision);
    return true;
}
