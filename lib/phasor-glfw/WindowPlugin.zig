const WindowPlugin = @This();

// ─────────────────────────────────────────────
// SETTINGS & FLAGS
// ─────────────────────────────────────────────

pub const WindowSettings = struct {
    width: u32 = 800,
    height: u32 = 450,
    title: []const u8 = "Phasor GLFW",
    target_fps: i32 = 60,
    flags: u32 = WindowFlags.Resizable | WindowFlags.HighDPI,
};

pub const WindowFlags = struct {
    pub const Resizable: u32 = 1 << 0;
    pub const HighDPI: u32 = 1 << 1;
};

pub const PrimaryWindow = struct {};

pub const Window = struct {
    handle: ?*glfw.GLFWwindow = null,
    title: []const u8,
    flags: u32,
};

// store settings provided by init()
settings: WindowSettings = .{},

pub fn init(settings: WindowSettings) WindowPlugin {
    return .{ .settings = settings };
}

pub fn build(self: *WindowPlugin, app: *App) !void {
    // Make settings available to systems
    g_settings = self.settings;

    // Insert "WindowInit" schedule between "PreStartup" and "Startup"
    _ = try app.addScheduleBetween("WindowInit", "PreStartup", "Startup");
    // Insert "WindowDeinit" schedule between "Shutdown" and "PostShutdown"
    _ = try app.addScheduleBetween("WindowDeinit", "Shutdown", "PostShutdown");
    // Insert "WindowUpdate" schedule in the main loop after "BeginFrame" and before "Update"
    _ = try app.addScheduleBetween("WindowUpdate", "BeginFrame", "Update");

    try app.addSystem("WindowInit", init_system);
    try app.addSystem("WindowUpdate", update);
    try app.addSystem("WindowDeinit", shutdown);

    // Ensure schedules exist
    _ = try app.addSchedule("LoadAssets");
    try app.scheduleAfter("LoadAssets", "WindowInit");
    try app.scheduleBefore("LoadAssets", "Startup");

    _ = try app.addSchedule("UnloadAssets");
    try app.scheduleAfter("UnloadAssets", "PreShutdown");
    try app.scheduleBefore("UnloadAssets", "WindowDeinit");
}

// Global fallback settings used by systems if no ECS resource exists
var g_settings: WindowSettings = .{};

// ─────────────────────────────────────────────
// SYSTEMS
// ─────────────────────────────────────────────

fn init_system(commands: *Commands, r_settings: ResOpt(WindowSettings)) !void {
    const settings = if (r_settings.ptr) |s| s.* else g_settings;

    if (glfw.glfwInit() == 0)
        return error.InitFailed;

    // Disable OpenGL (use Vulkan)
    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
    if ((settings.flags & WindowFlags.Resizable) != 0) {
        glfw.glfwWindowHint(glfw.GLFW_RESIZABLE, 1);
    } else {
        glfw.glfwWindowHint(glfw.GLFW_RESIZABLE, 0);
    }

    const window = glfw.glfwCreateWindow(
        @intCast(settings.width),
        @intCast(settings.height),
        settings.title.ptr,
        null,
        null,
    );
    if (window == null)
        return error.CreateFailed;

    const window_res = Window{
        .handle = window,
        .title = settings.title,
        .flags = settings.flags,
    };

    const window_bounds = WindowBounds{
        .width = @intCast(settings.width),
        .height = @intCast(settings.height),
    };

    const render_bounds = RenderBounds{
        .width = @floatFromInt(settings.width),
        .height = @floatFromInt(settings.height),
    };

    const target_fps = TargetFps{ .value = settings.target_fps };

    try commands.insertResource(window_res);
    try commands.insertResource(window_bounds);
    try commands.insertResource(render_bounds);
    try commands.insertResource(target_fps);

    std.log.info("GLFW window initialized ({d}x{d})", .{ settings.width, settings.height });
}

fn update(commands: *Commands, r_window: ResOpt(Window)) !void {
    if (r_window.ptr) |window_res| {
        const handle = window_res.handle orelse return;
        if (glfw.glfwWindowShouldClose(handle) != 0) {
            try commands.insertResource(Exit{ .code = 0 });
            return;
        }

        glfw.glfwPollEvents();

        var w: i32 = 0;
        var h: i32 = 0;
        glfw.glfwGetFramebufferSize(handle, &w, &h);

        if (w > 0 and h > 0) {
            try commands.insertResource(WindowBounds{
                .width = @intCast(w),
                .height = @intCast(h),
            });
            try commands.insertResource(RenderBounds{
                .width = @floatFromInt(w),
                .height = @floatFromInt(h),
            });
        }
    }
}

fn shutdown(r_window: ResOpt(Window)) !void {
    if (r_window.ptr) |w| {
        if (w.handle) |h| glfw.glfwDestroyWindow(h);
    }
    glfw.glfwTerminate();
    std.log.info("GLFW window closed", .{});
}

// ─────────────────────────────────────────────
// IMPORTS
// ─────────────────────────────────────────────

const std = @import("std");
const glfw = @import("glfw").c;

const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
const Exit = phasor_ecs.Exit;
const ResOpt = phasor_ecs.ResOpt;
const Commands = phasor_ecs.Commands;

const phasor_common = @import("phasor-common");
const TargetFps = phasor_common.TargetFps;
const RenderBounds = phasor_common.RenderBounds;
const WindowBounds = phasor_common.WindowBounds;

const root = @import("root.zig");
