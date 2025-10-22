//! `InputPlugin` provides keyboard input handling for GLFW.
//! Uses events to communicate key presses, releases, and holds.

const InputPlugin = @This();

pub fn build(_: *InputPlugin, app: *App) !void {
    // Register keyboard events
    try app.registerEvent(KeyPressed, 32);
    try app.registerEvent(KeyReleased, 32);
    try app.registerEvent(KeyDown, 32);

    // Add update system after WindowUpdate but before Update
    _ = try app.addSchedule("InputUpdate");
    try app.scheduleAfter("InputUpdate", "WindowUpdate");
    try app.scheduleBefore("InputUpdate", "Update");
    try app.addSystem("InputUpdate", poll_keyboard);
}

// Event types
pub const KeyPressed = struct {
    key: Key,
};

pub const KeyReleased = struct {
    key: Key,
};

pub const KeyDown = struct {
    key: Key,
};

// List of keys to poll
const keys_to_poll = [_]Key{
    .space, .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
    .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z,
    .left, .right, .up, .down, .escape, .enter,
};

fn poll_keyboard(
    r_window: ResOpt(Window),
    pressed_writer: EventWriter(KeyPressed),
    released_writer: EventWriter(KeyReleased),
    down_writer: EventWriter(KeyDown),
    commands: *Commands,
) !void {
    if (r_window.ptr) |window_res| {
        if (window_res.handle) |handle| {
            // Track previous key states
            const prev_state = if (commands.getResource(KeyboardState)) |s| s.* else KeyboardState{};
            var new_state = KeyboardState{};

            for (keys_to_poll) |key| {
                const state = glfw.glfwGetKey(handle, key.toGlfwKey());
                const is_down = (state == glfw.GLFW_PRESS or state == glfw.GLFW_REPEAT);
                const was_down = prev_state.isKeyDown(key);

                if (is_down) {
                    new_state.setKeyDown(key);
                    try down_writer.send(.{ .key = key });

                    if (!was_down) {
                        try pressed_writer.send(.{ .key = key });
                    }
                } else if (was_down) {
                    try released_writer.send(.{ .key = key });
                }
            }

            try commands.insertResource(new_state);
        }
    }
}

// Internal state tracking
const KeyboardState = struct {
    keys: u128 = 0,

    fn isKeyDown(self: *const KeyboardState, key: Key) bool {
        const idx = keyToIndex(key);
        if (idx >= 128) return false;
        return (self.keys & (@as(u128, 1) << @intCast(idx))) != 0;
    }

    fn setKeyDown(self: *KeyboardState, key: Key) void {
        const idx = keyToIndex(key);
        if (idx >= 128) return;
        self.keys |= (@as(u128, 1) << @intCast(idx));
    }

    fn keyToIndex(key: Key) u8 {
        return switch (key) {
            .space => 0,
            .a => 1,
            .b => 2,
            .c => 3,
            .d => 4,
            .e => 5,
            .f => 6,
            .g => 7,
            .h => 8,
            .i => 9,
            .j => 10,
            .k => 11,
            .l => 12,
            .m => 13,
            .n => 14,
            .o => 15,
            .p => 16,
            .q => 17,
            .r => 18,
            .s => 19,
            .t => 20,
            .u => 21,
            .v => 22,
            .w => 23,
            .x => 24,
            .y => 25,
            .z => 26,
            .left => 27,
            .right => 28,
            .up => 29,
            .down => 30,
            .escape => 31,
            .enter => 32,
            else => 255,
        };
    }
};

// Key enum that wraps GLFW key constants
pub const Key = enum(c_int) {
    space = 32,
    apostrophe = 39,
    comma = 44,
    minus = 45,
    period = 46,
    slash = 47,
    zero = 48,
    one = 49,
    two = 50,
    three = 51,
    four = 52,
    five = 53,
    six = 54,
    seven = 55,
    eight = 56,
    nine = 57,
    semicolon = 59,
    equal = 61,
    a = 65,
    b = 66,
    c = 67,
    d = 68,
    e = 69,
    f = 70,
    g = 71,
    h = 72,
    i = 73,
    j = 74,
    k = 75,
    l = 76,
    m = 77,
    n = 78,
    o = 79,
    p = 80,
    q = 81,
    r = 82,
    s = 83,
    t = 84,
    u = 85,
    v = 86,
    w = 87,
    x = 88,
    y = 89,
    z = 90,
    left_bracket = 91,
    backslash = 92,
    right_bracket = 93,
    grave_accent = 96,
    escape = 256,
    enter = 257,
    tab = 258,
    backspace = 259,
    insert = 260,
    delete = 261,
    right = 262,
    left = 263,
    down = 264,
    up = 265,
    page_up = 266,
    page_down = 267,
    home = 268,
    end = 269,
    caps_lock = 280,
    scroll_lock = 281,
    num_lock = 282,
    print_screen = 283,
    pause = 284,
    f1 = 290,
    f2 = 291,
    f3 = 292,
    f4 = 293,
    f5 = 294,
    f6 = 295,
    f7 = 296,
    f8 = 297,
    f9 = 298,
    f10 = 299,
    f11 = 300,
    f12 = 301,
    left_shift = 340,
    left_control = 341,
    left_alt = 342,
    left_super = 343,
    right_shift = 344,
    right_control = 345,
    right_alt = 346,
    right_super = 347,

    pub fn toGlfwKey(self: Key) c_int {
        return @intFromEnum(self);
    }
};

// Imports
const std = @import("std");
const glfw = @import("glfw").c;

const phasor_ecs = @import("phasor-ecs");
const App = phasor_ecs.App;
const Commands = phasor_ecs.Commands;
const ResOpt = phasor_ecs.ResOpt;
const EventWriter = phasor_ecs.EventWriter;

const root = @import("root.zig");
const Window = @import("WindowPlugin.zig").Window;
