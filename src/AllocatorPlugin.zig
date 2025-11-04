const AllocatorPlugin = @This();

pub const Allocator = struct {
    allocator: std.mem.Allocator,
};

allocator: std.mem.Allocator,

pub fn build(self: *AllocatorPlugin, app: *App) !void {
    try app.insertResource(Allocator{
        .allocator = self.allocator,
    });
}

// ─────────────────────────────────────────────
// Imports
// ─────────────────────────────────────────────
const std = @import("std");

const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
