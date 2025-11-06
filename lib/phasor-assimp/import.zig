const std = @import("std");
const assimp = @import("assimp");
const common = @import("phasor-vulkan-common");
const conv = @import("conversion.zig");

const c = assimp.c;

pub const Error = error{
    FileNotFound,
    ImportFailed,
    NoMeshes,
};

pub fn loadFile(allocator: std.mem.Allocator, path: [:0]const u8) !common.ModelData {
    // Assimp expects a C-string path.
    const flags: c_uint = c.aiProcess_Triangulate |
        c.aiProcess_GenNormals |
        c.aiProcess_JoinIdenticalVertices |
        c.aiProcess_ImproveCacheLocality |
        c.aiProcess_SortByPType |
        c.aiProcess_GenUVCoords |
        c.aiProcess_TransformUVCoords |
        c.aiProcess_CalcTangentSpace |
        c.aiProcess_ValidateDataStructure |
        c.aiProcess_OptimizeMeshes |
        c.aiProcess_FlipUVs; // Vulkan-style UV origin

    const scene = c.aiImportFile(path, flags);
    if (scene == null) return Error.ImportFailed;
    defer c.aiReleaseImport(scene);

    if (scene.*.mNumMeshes == 0) return Error.NoMeshes;

    return try conv.sceneToModelData(allocator, scene.*);
}
