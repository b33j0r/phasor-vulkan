// Thin C wrapper for stb_image
// Single-file public domain image loader
// This module exposes the C API via @cImport.

pub const c = @cImport({
    @cInclude("stb_image.h");
});
