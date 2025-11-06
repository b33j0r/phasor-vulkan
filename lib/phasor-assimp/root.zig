// High-level GLTF/GLB loading via Assimp
// Produces neutral ModelData (lib/common) suitable for conversion by the engine.
const std = @import("std");
const assimp = @import("assimp");
const common = @import("phasor-model-common");

pub const ModelData = common.ModelData;

pub fn loadGlbData(allocator: std.mem.Allocator, path: [:0]const u8) !ModelData {
    return @import("import.zig").loadFile(allocator, path);
}

pub fn loadGltfData(allocator: std.mem.Allocator, path: [:0]const u8) !ModelData {
    return @import("import.zig").loadFile(allocator, path);
}
