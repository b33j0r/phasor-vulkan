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

        // First pass: create all entities
        for (scene.nodes, 0..) |_, i| {
            const entity_id = commands.spawn(.{});
            node_entities[i] = entity_id;
        }

        // Second pass: add components and set up hierarchy
        for (scene.nodes, 0..) |node, i| {
            const entity_id = node_entities[i];

            // Add transform component
            if (node.parent == null) {
                // Root nodes get Transform3d directly
                commands.addComponent(entity_id, components.Transform3d{
                    .translation = node.transform.translation,
                    .rotation = node.transform.rotation,
                    .scale = node.transform.scale,
                });
            } else {
                // Child nodes get LocalTransform3d + Parent component
                commands.addComponent(entity_id, ParentPlugin.LocalTransform3d{
                    .translation = node.transform.translation,
                    .rotation = node.transform.rotation,
                    .scale = node.transform.scale,
                });
                commands.addComponent(entity_id, components.Transform3d{});

                // Add parent reference
                const parent_id = node_entities[node.parent.?];
                commands.addComponent(entity_id, ParentPlugin.Parent{
                    .id = parent_id,
                });
            }

            // Add mesh component if node has a mesh
            if (node.mesh_index) |mesh_idx| {
                const mesh = scene.meshes[mesh_idx];
                commands.addComponent(entity_id, components.Mesh{
                    .vertices = mesh.vertices,
                    .indices = mesh.indices,
                });

                // Add material if available
                if (node.material_index) |mat_idx| {
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

                    commands.addComponent(entity_id, mat_component);
                } else {
                    // Default white material
                    commands.addComponent(entity_id, components.Material{
                        .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
                    });
                }
            }

            // Add MeshNode component for metadata
            commands.addComponent(entity_id, components.MeshNode{
                .name = node.name,
                .parent = if (node.parent) |p| node_entities[p] else null,
                .local_transform = node.transform,
            });
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
