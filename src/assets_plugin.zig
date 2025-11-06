const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
const ResMut = phasor_ecs.ResMut;
const ResOpt = phasor_ecs.ResOpt;
const Res = phasor_ecs.Res;

const DeviceResource = @import("device/DevicePlugin.zig").DeviceResource;
const RenderResource = @import("render/RenderPlugin.zig").RenderResource;
const Allocator = @import("AllocatorPlugin.zig").Allocator;

/// Generic asset plugin that manages loading and unloading of asset resources
/// Usage: Define a struct with your asset fields, and the plugin will automatically
/// call load() and unload() on each field during the appropriate lifecycle phases.
pub fn AssetPlugin(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn build(_: *Self, app: *App) !void {
            try app.insertResource(T{});

            // Load assets after Vulkan is initialized
            try app.addSystem("VkInitEnd", Self.load);
            try app.addSystem("VkDeinitBegin", Self.unload);
        }

        pub fn load(r_assets: ResMut(T), r_device: ResOpt(DeviceResource), r_render: ResOpt(RenderResource), r_allocator: Res(Allocator)) !void {
            const assets = r_assets.ptr;
            const dev_res = r_device.ptr orelse return error.MissingDeviceResource;
            const render_res = r_render.ptr orelse return error.MissingRenderResource;
            const vkd = dev_res.device_proxy orelse return error.MissingDevice;
            const allocator = r_allocator.ptr.allocator;

            const fields = std.meta.fields(T);
            inline for (fields) |field| {
                const field_name = field.name;
                var field_ptr = &@field(assets, field_name);
                try field_ptr.load(vkd, dev_res, render_res, allocator);
            }
        }

        pub fn unload(r_assets: ResMut(T), r_device: ResOpt(DeviceResource), r_allocator: Res(Allocator)) !void {
            const assets = r_assets.ptr;
            const dev_res = r_device.ptr orelse return error.MissingDeviceResource;
            const vkd = dev_res.device_proxy orelse return error.MissingDevice;
            const allocator = r_allocator.ptr.allocator;

            const fields = std.meta.fields(T);
            inline for (fields) |field| {
                const field_name = field.name;
                var field_ptr = &@field(assets, field_name);
                try field_ptr.unload(vkd, allocator);
            }
        }
    };
}
