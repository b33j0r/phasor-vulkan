const ParentPlugin = @This();

const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_common = @import("phasor-common");
const components = @import("components.zig");

const App = phasor_ecs.App;
const Query = phasor_ecs.Query;
const Entity = phasor_ecs.Entity;
const Transform3d = components.Transform3d;
const Vec3 = phasor_common.Vec3;

/// Parent component that references another entity by ID
pub const Parent = struct {
    id: Entity.Id,
};

/// Local transform relative to parent
/// Entities with this component will have their Transform3d computed from parent + local
pub const LocalTransform3d = struct {
    translation: Vec3 = .{},
    rotation: Vec3 = .{},
    scale: Vec3 = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
};

pub fn build(_: *const ParentPlugin, app: *App) !void {
    // Run parent transform updates after Update but before Render
    // This ensures physics and controller updates happen first
    _ = try app.addSchedule("ParentUpdate");
    try app.scheduleBetween("ParentUpdate", "Update", "Render");
    try app.addSystem("ParentUpdate", sys_update_child_transforms);
}

/// Compose parent and local transforms to produce world transform
fn compose(parent: *const Transform3d, local: *const LocalTransform3d) Transform3d {
    // Component-wise scale
    const scale = Vec3{
        .x = parent.scale.x * local.scale.x,
        .y = parent.scale.y * local.scale.y,
        .z = parent.scale.z * local.scale.z,
    };

    // Rotation add (Euler angles)
    const rotation = Vec3{
        .x = parent.rotation.x + local.rotation.x,
        .y = parent.rotation.y + local.rotation.y,
        .z = parent.rotation.z + local.rotation.z,
    };

    // Apply parent's rotation to local translation
    // Order: Yaw (Y) -> Pitch (X) -> Roll (Z)
    const sy = @sin(parent.rotation.y);
    const cy = @cos(parent.rotation.y);
    const sx = @sin(parent.rotation.x);
    const cx = @cos(parent.rotation.x);
    const sz = @sin(parent.rotation.z);
    const cz = @cos(parent.rotation.z);

    // Scale local translation by parent scale
    const lx = local.translation.x * parent.scale.x;
    const ly = local.translation.y * parent.scale.y;
    const lz = local.translation.z * parent.scale.z;

    // Rotate local translation by parent rotation (YXZ order)
    // This is a simplified rotation - for full accuracy would need proper matrix multiplication
    // But for FPS controller purposes (mainly Y-axis yaw), this should work well
    const temp_x = lx * cy + lz * sy;
    const temp_y = ly;
    const temp_z = -lx * sy + lz * cy;

    // Apply pitch (X rotation)
    const rx = temp_x;
    const ry = temp_y * cx - temp_z * sx;
    const rz = temp_y * sx + temp_z * cx;

    // Apply roll (Z rotation) - usually not needed for FPS
    const final_x = rx * cz - ry * sz;
    const final_y = rx * sz + ry * cz;
    const final_z = rz;

    const translation = Vec3{
        .x = parent.translation.x + final_x,
        .y = parent.translation.y + final_y,
        .z = parent.translation.z + final_z,
    };

    return .{
        .translation = translation,
        .scale = scale,
        .rotation = rotation,
    };
}

/// System that updates child transforms based on their parent and local transform
fn sys_update_child_transforms(q: Query(.{ Parent, LocalTransform3d, Transform3d })) void {
    var it = q.iterator();
    while (it.next()) |e| {
        const parent_comp = e.get(Parent).?;
        const child_local = e.get(LocalTransform3d).?;
        const child_world = e.get(Transform3d).?;

        // Resolve parent entity by stored Id
        if (e.database.getEntity(parent_comp.id)) |parent_entity| {
            if (parent_entity.get(Transform3d)) |parent_world| {
                const composed = compose(parent_world, child_local);
                child_world.* = composed;
            }
        }
        // If parent lacks a Transform3d, leave child as-is
    }
}
