// GLTF Asset - integrates with AssetPlugin for lifecycle management
const std = @import("std");
const vk = @import("vulkan");
const types = @import("types.zig");
const GltfImporter = @import("GltfImporter.zig").GltfImporter;
const GltfSceneBuilder = @import("GltfSceneBuilder.zig").GltfSceneBuilder;
const DeviceResource = @import("../device/DevicePlugin.zig").DeviceResource;
const assets = @import("../assets.zig");
const phasor_ecs = @import("phasor-ecs");

const GltfScene = types.GltfScene;
const Commands = phasor_ecs.Commands;

pub const GltfAsset = struct {
    path: [:0]const u8,
    scene: ?GltfScene = null,
    allocator: ?std.mem.Allocator = null,

    pub fn load(self: *GltfAsset, vkd: anytype, dev_res: *const DeviceResource) !void {
        _ = vkd;
        _ = dev_res;

        std.debug.print("Loading GLTF asset from: {s}\n", .{self.path});

        // Use a persistent allocator (will be freed in unload)
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        self.allocator = allocator;

        // Load GLTF scene
        var importer = GltfImporter.init(allocator);
        const scene = try importer.loadScene(self.path);

        std.debug.print("GLTF scene loaded: {} nodes, {} meshes\n", .{ scene.nodes.len, scene.meshes.len });

        // TODO: Load textures referenced by the scene
        // For now, textures array remains null

        self.scene = scene;
    }

    pub fn unload(self: *GltfAsset, vkd: anytype) !void {
        _ = vkd;

        if (self.scene) |*scene| {
            scene.deinit();
            self.scene = null;
        }

        // Note: GPA deinit is not called here because we need to keep the allocator
        // alive for the scene data. In a production system, we'd use an arena allocator
        // or a proper memory pool.
    }

    /// Spawn the loaded scene into the ECS
    pub fn spawn(self: *const GltfAsset, commands: *Commands, allocator: std.mem.Allocator) !void {
        if (self.scene == null) return error.SceneNotLoaded;

        var builder = GltfSceneBuilder.init(allocator);
        const roots = try builder.spawnScene(commands, &self.scene.?);
        defer allocator.free(roots);
    }
};
