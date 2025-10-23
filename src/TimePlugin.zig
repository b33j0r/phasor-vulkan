const TimePlugin = @This();

pub fn build(self: *TimePlugin, app: *App) !void {
    const timer = try std.time.Timer.start();

    try app.insertResource(DeltaTime{ .seconds = 0, .last_frame_ns = 0 });
    try app.insertResource(ElapsedTime{ .seconds = 0, .timer = timer });

    _ = self;
    try app.addSystem("Update", update);
}

fn update(
    time: ResMut(DeltaTime),
    elapsed: ResMut(ElapsedTime),
) void {
    const current_ns = elapsed.ptr.timer.read();
    const delta_ns = if (time.ptr.last_frame_ns == 0) 0 else current_ns - time.ptr.last_frame_ns;

    time.ptr.last_frame_ns = current_ns;
    time.ptr.seconds = @as(f32, @floatFromInt(delta_ns)) / std.time.ns_per_s;
    elapsed.ptr.seconds = @as(f32, @floatFromInt(current_ns)) / std.time.ns_per_s;
}

// Imports
const std = @import("std");

const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
const Res = phasor_ecs.Res;
const ResMut = phasor_ecs.ResMut;
const Query = phasor_ecs.Query;
const Commands = phasor_ecs.Commands;

pub const DeltaTime = struct {
    seconds: f32,
    last_frame_ns: u64,
};

pub const ElapsedTime = struct {
    seconds: f32,
    timer: std.time.Timer,
};
