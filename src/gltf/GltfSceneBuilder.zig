// GLTF Scene Builder - converts GLTF data to ECS entities
const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_common = @import("phasor-common");
const types = @import("types.zig");
const components = @import("../components.zig");
const ParentPlugin = @import("../ParentPlugin.zig");

const Commands = phasor_ecs.Commands;
const Entity = phasor_ecs.Entity;
const GltfScene = types.GltfScene;

pub const GltfSceneBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GltfSceneBuilder {
        return .{
            .allocator = allocator,
        };
    }

    /// Spawns a GLTF scene as entities in the ECS
    /// Returns the root entity IDs (top-level nodes)
    pub fn spawnScene(
        self: *GltfSceneBuilder,
        commands: *Commands,
        scene: *const GltfScene,
    ) ![]Entity.Id {

        // Create entity for each node
        var node_entities = try self.allocator.alloc(Entity.Id, scene.nodes.len);
        defer self.allocator.free(node_entities);

        // First pass: create all entities with MeshNode component (required for ECS)
        for (scene.nodes, 0..) |node, i| {
            // Scale up the transform to compensate for tiny GLTF models (Sponza has 0.01 scale)
            var scaled_transform = node.transform;
            scaled_transform.scale.x *= 100.0;
            scaled_transform.scale.y *= 100.0;
            scaled_transform.scale.z *= 100.0;

            const entity_id = try commands.createEntity(.{
                components.MeshNode{
                    .name = node.name,
                    .parent = null, // Will be set in second pass
                    .local_transform = scaled_transform,
                },
            });
            node_entities[i] = entity_id;
        }

        // Second pass: add components and set up hierarchy
        for (scene.nodes, 0..) |node, i| {
            const entity_id = node_entities[i];

            // Add transform component with scaled-up scale
            var render_scale = node.transform.scale;
            render_scale.x *= 100.0;
            render_scale.y *= 100.0;
            render_scale.z *= 100.0;

            if (node.parent == null) {
                // Root nodes get Transform3d directly
                try commands.addComponent(entity_id, components.Transform3d{
                    .translation = node.transform.translation,
                    .rotation = node.transform.rotation,
                    .scale = render_scale,
                });
            } else {
                // Child nodes get LocalTransform3d + Parent component
                try commands.addComponent(entity_id, ParentPlugin.LocalTransform3d{
                    .translation = node.transform.translation,
                    .rotation = node.transform.rotation,
                    .scale = render_scale,
                });
                try commands.addComponent(entity_id, components.Transform3d{});

                // Add parent reference
                const parent_id = node_entities[node.parent.?];
                try commands.addComponent(entity_id, ParentPlugin.Parent{
                    .id = parent_id,
                });
            }

            // Add mesh component if node has a mesh
            if (node.mesh_index) |mesh_idx| {
                const mesh = scene.meshes[mesh_idx];
                try commands.addComponent(entity_id, components.Mesh{
                    .vertices = mesh.vertices,
                    .indices = mesh.indices,
                });

                // Add material if available (from mesh, not node)
                if (mesh.material_index) |mat_idx| {
                    const material = scene.materials[mat_idx];

                    var mat_component = components.Material{
                        .color = material.base_color,
                    };

                    // Set texture if available
                    if (material.base_color_texture) |tex_idx| {
                        if (tex_idx < scene.textures.len) {
                            if (scene.textures[tex_idx]) |texture| {
                                mat_component.texture = texture;
                            }
                        }
                    }

                    try commands.addComponent(entity_id, mat_component);
                } else {
                    // Default white material
                    try commands.addComponent(entity_id, components.Material{
                        .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
                    });
                }
            }
        }

        // Create entities for meshes not referenced by any node
        // This handles GLTF files where a single mesh has multiple primitives
        var referenced_meshes = try self.allocator.alloc(bool, scene.meshes.len);
        defer self.allocator.free(referenced_meshes);
        for (referenced_meshes) |*ref| ref.* = false;

        for (scene.nodes) |node| {
            if (node.mesh_index) |idx| {
                referenced_meshes[idx] = true;
            }
        }

        // Create entities for unreferenced meshes
        for (scene.meshes, 0..) |mesh, mesh_idx| {
            if (!referenced_meshes[mesh_idx]) {
                const entity_id = try commands.createEntity(.{
                    components.Transform3d{
                        .scale = .{ .x = 100.0, .y = 100.0, .z = 100.0 }, // Scale up 100x to compensate for 0.01 GLTF scale
                    },
                    components.MeshNode{
                        .name = mesh.name,
                        .parent = null,
                        .local_transform = .{},
                    },
                });

                try commands.addComponent(entity_id, components.Mesh{
                    .vertices = mesh.vertices,
                    .indices = mesh.indices,
                });

                // Add material if available
                if (mesh.material_index) |mat_idx| {
                    if (mat_idx < scene.materials.len) {
                        const material = scene.materials[mat_idx];
                        try commands.addComponent(entity_id, components.Material{
                            .color = material.base_color,
                        });
                    }
                } else {
                    try commands.addComponent(entity_id, components.Material{
                        .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
                    });
                }
            }
        }

        // Collect root node entities
        var root_count: usize = 0;
        for (scene.nodes) |node| {
            if (node.parent == null) root_count += 1;
        }

        var roots = try self.allocator.alloc(Entity.Id, root_count);
        var root_idx: usize = 0;
        for (scene.nodes, 0..) |node, i| {
            if (node.parent == null) {
                roots[root_idx] = node_entities[i];
                root_idx += 1;
            }
        }

        return roots;
    }
};
