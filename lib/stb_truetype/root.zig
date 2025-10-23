// Zig wrapper for stb_truetype
const c = @cImport({
    @cInclude("stb_truetype.h");
});

pub const stbtt = c;

// Font atlas for rendering text
pub const FontAtlas = struct {
    texture_width: u32,
    texture_height: u32,
    bitmap: []u8,
    font_info: c.stbtt_fontinfo,
    font_data: []const u8,
    scale: f32,
    baseline: f32,

    pub fn init(allocator: std.mem.Allocator, font_data: []const u8, font_height: f32, atlas_width: u32, atlas_height: u32) !FontAtlas {
        var font_info: c.stbtt_fontinfo = undefined;
        if (c.stbtt_InitFont(&font_info, font_data.ptr, 0) == 0) {
            return error.FontInitFailed;
        }

        const scale = c.stbtt_ScaleForPixelHeight(&font_info, font_height);

        var ascent: c_int = 0;
        var descent: c_int = 0;
        var line_gap: c_int = 0;
        c.stbtt_GetFontVMetrics(&font_info, &ascent, &descent, &line_gap);
        const baseline = @as(f32, @floatFromInt(ascent)) * scale;

        const bitmap = try allocator.alloc(u8, atlas_width * atlas_height);
        @memset(bitmap, 0);

        return .{
            .texture_width = atlas_width,
            .texture_height = atlas_height,
            .bitmap = bitmap,
            .font_info = font_info,
            .font_data = font_data,
            .scale = scale,
            .baseline = baseline,
        };
    }

    pub fn deinit(self: *FontAtlas, allocator: std.mem.Allocator) void {
        allocator.free(self.bitmap);
    }

    /// Bake ASCII characters into the atlas
    pub fn bakeASCII(self: *FontAtlas, first_char: u8, num_chars: u8) ![]CharData {
        const allocator = std.heap.page_allocator; // TODO: pass allocator
        const char_data = try allocator.alloc(CharData, num_chars);

        // Simple horizontal packing for now
        var x: u32 = 0;
        var y: u32 = 0;
        var row_height: u32 = 0;

        for (0..num_chars) |i| {
            const codepoint: c_int = first_char + @as(u8, @intCast(i));

            var width: c_int = 0;
            var height: c_int = 0;
            var xoff: c_int = 0;
            var yoff: c_int = 0;

            const glyph_bitmap = c.stbtt_GetCodepointBitmap(
                &self.font_info,
                0,
                self.scale,
                codepoint,
                &width,
                &height,
                &xoff,
                &yoff,
            );
            defer c.stbtt_FreeBitmap(glyph_bitmap, null);

            const w = @as(u32, @intCast(width));
            const h = @as(u32, @intCast(height));

            // Wrap to next row if needed
            if (x + w > self.texture_width) {
                x = 0;
                y += row_height + 1;
                row_height = 0;
            }

            if (y + h > self.texture_height) {
                return error.AtlasFull;
            }

            // Copy glyph bitmap to atlas
            for (0..h) |row| {
                const dst_offset = (y + row) * self.texture_width + x;
                const src_offset = row * w;
                @memcpy(
                    self.bitmap[dst_offset..][0..w],
                    glyph_bitmap[src_offset..][0..w],
                );
            }

            var advance: c_int = 0;
            var lsb: c_int = 0;
            c.stbtt_GetCodepointHMetrics(&self.font_info, codepoint, &advance, &lsb);

            char_data[i] = .{
                .x0 = @floatFromInt(x),
                .y0 = @floatFromInt(y),
                .x1 = @floatFromInt(x + w),
                .y1 = @floatFromInt(y + h),
                .xoff = @floatFromInt(xoff),
                .yoff = @floatFromInt(yoff),
                .xadvance = @as(f32, @floatFromInt(advance)) * self.scale,
            };

            x += w + 1;
            row_height = @max(row_height, h);
        }

        return char_data;
    }
};

pub const CharData = struct {
    x0: f32, // atlas position
    y0: f32,
    x1: f32,
    y1: f32,
    xoff: f32, // offset when rendering
    yoff: f32,
    xadvance: f32, // advance to next character
};

const std = @import("std");
