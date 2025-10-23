const std = @import("std");
const phasor_ecs = @import("phasor-ecs");
const phasor_glfw = @import("phasor-glfw");
const phasor_vulkan = @import("phasor-vulkan");
const phasor_common = @import("phasor-common");
const phasor_phases = @import("phasor-phases");

const PhasePlugin = phasor_phases.PhasePlugin;
const PhaseContext = phasor_phases.PhaseContext;

// ============================================================================
// Game Assets
// ============================================================================

const GameAssets = struct {
    orbitron_font: phasor_vulkan.Font = .{
        .path = "examples/sprites/assets/fonts/Orbitron-VariableFont_wght.ttf",
        .font_height = 48.0,
        .atlas_width = 512,
        .atlas_height = 512,
    },
};

// ============================================================================
// Game State Resources
// ============================================================================

const GameState = struct {
    score: u32 = 0,
    lives: i32 = 3,
    level: u32 = 1,
    high_scores: [5]u32 = .{ 0, 0, 0, 0, 0 },
};

// ============================================================================
// Components
// ============================================================================

const Paddle = struct {
    width: f32 = 120.0,
    height: f32 = 20.0,
    speed: f32 = 500.0,
};

const Ball = struct {
    radius: f32 = 8.0,
    velocity_x: f32 = 0.0,
    velocity_y: f32 = 0.0,
    speed: f32 = 400.0,
    attached_to_paddle: bool = true,
};

const Brick = struct {
    width: f32 = 60.0,
    height: f32 = 20.0,
    hits_remaining: u32 = 1,
    points: u32 = 100,
};

const Wall = struct {};

const UIText = struct {
    text_type: TextType,
    buffer: [128]u8 = undefined,
};

const TextType = enum {
    Score,
    Lives,
    Title,
    Subtitle,
    GameOver,
    Victory,
    PauseMenu,
    HighScore,
};

// ============================================================================
// Phase Definitions
// ============================================================================

const GamePhases = union(enum) {
    MainMenu: MainMenu,
    InGame: InGame,
    HighScore: HighScore,

    pub fn enter(_: *GamePhases, _: *PhaseContext) !void {}
};

const MainMenu = struct {
    pub fn enter(_: *MainMenu, ctx: *PhaseContext) !void {
        try ctx.addEnterSystem(setup_main_menu);
        try ctx.addExitSystem(cleanup_main_menu);
        try ctx.addUpdateSystem(main_menu_input);
    }
};

const InGame = union(enum) {
    Playing: Playing,
    PauseMenu: PauseMenu,
    Loser: Loser,
    Winner: Winner,

    pub fn enter(_: *InGame, ctx: *PhaseContext) !void {
        try ctx.addEnterSystem(setup_game);
    }

    pub fn exit(_: *InGame, ctx: *PhaseContext) !void {
        try ctx.addExitSystem(cleanup_game);
    }
};

const Playing = struct {
    pub fn enter(_: *Playing, ctx: *PhaseContext) !void {
        try ctx.addUpdateSystem(paddle_control);
        try ctx.addUpdateSystem(ball_movement);
        try ctx.addUpdateSystem(ball_collision);
        try ctx.addUpdateSystem(brick_collision);
        try ctx.addUpdateSystem(check_win_lose);
        try ctx.addUpdateSystem(pause_input);
    }
};

const PauseMenu = struct {
    pub fn enter(_: *PauseMenu, ctx: *PhaseContext) !void {
        try ctx.addEnterSystem(setup_pause_menu);
        try ctx.addExitSystem(cleanup_pause_menu);
        try ctx.addUpdateSystem(pause_menu_input);
    }
};

const Loser = struct {
    pub fn enter(_: *Loser, ctx: *PhaseContext) !void {
        try ctx.addEnterSystem(setup_loser_screen);
        try ctx.addExitSystem(cleanup_loser_screen);
        try ctx.addUpdateSystem(loser_input);
    }
};

const Winner = struct {
    pub fn enter(_: *Winner, ctx: *PhaseContext) !void {
        try ctx.addEnterSystem(setup_winner_screen);
        try ctx.addExitSystem(cleanup_winner_screen);
        try ctx.addUpdateSystem(winner_input);
    }
};

const HighScore = struct {
    pub fn enter(_: *HighScore, ctx: *PhaseContext) !void {
        try ctx.addEnterSystem(setup_high_score);
        try ctx.addExitSystem(cleanup_high_score);
        try ctx.addUpdateSystem(high_score_input);
    }
};

const GamePhasesPlugin = PhasePlugin(GamePhases, GamePhases{ .MainMenu = .{} });
const NextPhase = GamePhasesPlugin.NextPhase;
const CurrentPhase = GamePhasesPlugin.CurrentPhase;

// ============================================================================
// Main Menu Phase Systems
// ============================================================================

fn setup_main_menu(
    mut_commands: *phasor_ecs.Commands,
    r_assets: phasor_ecs.Res(GameAssets),
) !void {
    // Create camera
    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Camera3d{
            .Viewport = .{
                .mode = .Center,
            },
        },
        phasor_vulkan.Transform3d{},
    });

    // Title text
    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .Title },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -200.0, .y = -100.0, .z = 0.0 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "PHARKANOID",
            .color = .{ .r = 0.2, .g = 0.8, .b = 1.0, .a = 1.0 },
        },
    });

    // Subtitle text
    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .Subtitle },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -220.0, .y = 0.0, .z = 0.0 },
            .scale = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "Press SPACE to Start",
            .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        },
    });
}

fn cleanup_main_menu(mut_commands: *phasor_ecs.Commands, q_ui: phasor_ecs.Query(.{UIText})) !void {
    var it = q_ui.iterator();
    while (it.next()) |entity| {
        try mut_commands.removeEntity(entity.id);
    }
}

fn main_menu_input(
    key_events: phasor_ecs.EventReader(phasor_glfw.InputPlugin.KeyDown),
    commands: *phasor_ecs.Commands,
) !void {
    while (key_events.tryRecv()) |event| {
        if (event.key == .space) {
            try commands.insertResource(NextPhase{ .phase = GamePhases{ .InGame = .{ .Playing = .{} } } });
        }
    }
}

// ============================================================================
// InGame Phase Systems
// ============================================================================

fn setup_game(
    mut_commands: *phasor_ecs.Commands,
    r_assets: phasor_ecs.Res(GameAssets),
) !void {
    // Initialize or reset game state
    if (mut_commands.getResource(GameState)) |state| {
        state.score = 0;
        state.lives = 3;
        state.level = 1;
    } else {
        try mut_commands.insertResource(GameState{});
    }

    // Always create a new camera for the game
    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Camera3d{
            .Viewport = .{
                .mode = .Center,
            },
        },
        phasor_vulkan.Transform3d{},
    });

    // Create walls
    const wall_thickness: f32 = 20.0;
    const arena_width: f32 = 600.0;
    const arena_height: f32 = 600.0;

    // Top wall
    _ = try mut_commands.createEntity(.{
        Wall{},
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = -arena_height / 2.0, .z = 0.0 },
        },
        phasor_vulkan.Rectangle{
            .width = arena_width,
            .height = wall_thickness,
            .color = .{ .r = 0.3, .g = 0.3, .b = 0.3, .a = 1.0 },
        },
    });

    // Left wall
    _ = try mut_commands.createEntity(.{
        Wall{},
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -arena_width / 2.0, .y = 0.0, .z = 0.0 },
        },
        phasor_vulkan.Rectangle{
            .width = wall_thickness,
            .height = arena_height,
            .color = .{ .r = 0.3, .g = 0.3, .b = 0.3, .a = 1.0 },
        },
    });

    // Right wall
    _ = try mut_commands.createEntity(.{
        Wall{},
        phasor_vulkan.Transform3d{
            .translation = .{ .x = arena_width / 2.0, .y = 0.0, .z = 0.0 },
        },
        phasor_vulkan.Rectangle{
            .width = wall_thickness,
            .height = arena_height,
            .color = .{ .r = 0.3, .g = 0.3, .b = 0.3, .a = 1.0 },
        },
    });

    // Create paddle
    const paddle_y: f32 = 250.0;
    _ = try mut_commands.createEntity(.{
        Paddle{},
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = paddle_y, .z = 0.0 },
        },
        phasor_vulkan.Rectangle{
            .width = 120.0,
            .height = 20.0,
            .color = .{ .r = 0.2, .g = 1.0, .b = 0.2, .a = 1.0 },
        },
    });

    // Create ball
    _ = try mut_commands.createEntity(.{
        Ball{},
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 0.0, .y = paddle_y - 20.0, .z = 0.0 },
        },
        phasor_vulkan.Circle{
            .radius = 8.0,
            .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        },
    });

    // Create bricks
    const brick_rows: usize = 5;
    const brick_cols: usize = 8;
    const brick_width: f32 = 60.0;
    const brick_height: f32 = 20.0;
    const brick_spacing: f32 = 5.0;
    const start_x: f32 = -(brick_cols * (brick_width + brick_spacing)) / 2.0;
    const start_y: f32 = -250.0;

    var row: usize = 0;
    while (row < brick_rows) : (row += 1) {
        var col: usize = 0;
        while (col < brick_cols) : (col += 1) {
            const x = start_x + @as(f32, @floatFromInt(col)) * (brick_width + brick_spacing);
            const y = start_y + @as(f32, @floatFromInt(row)) * (brick_height + brick_spacing);

            // Color based on row
            const color = switch (row) {
                0 => phasor_vulkan.Color4{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
                1 => phasor_vulkan.Color4{ .r = 1.0, .g = 0.5, .b = 0.0, .a = 1.0 },
                2 => phasor_vulkan.Color4{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 },
                3 => phasor_vulkan.Color4{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 },
                else => phasor_vulkan.Color4{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
            };

            _ = try mut_commands.createEntity(.{
                Brick{},
                phasor_vulkan.Transform3d{
                    .translation = .{ .x = x, .y = y, .z = 0.0 },
                },
                phasor_vulkan.Rectangle{
                    .width = brick_width,
                    .height = brick_height,
                    .color = color,
                },
            });
        }
    }

    // Create UI text
    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .Score },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -380.0, .y = -280.0, .z = 0.0 },
            .scale = .{ .x = 0.4, .y = 0.4, .z = 0.4 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "Score: 0",
            .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        },
    });

    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .Lives },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = 200.0, .y = -280.0, .z = 0.0 },
            .scale = .{ .x = 0.4, .y = 0.4, .z = 0.4 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "Lives: 3",
            .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        },
    });
}

fn cleanup_game(
    mut_commands: *phasor_ecs.Commands,
    q_paddle: phasor_ecs.Query(.{Paddle}),
    q_ball: phasor_ecs.Query(.{Ball}),
    q_brick: phasor_ecs.Query(.{Brick}),
    q_wall: phasor_ecs.Query(.{Wall}),
    q_ui: phasor_ecs.Query(.{UIText}),
    q_camera: phasor_ecs.Query(.{phasor_vulkan.Camera3d}),
) !void {
    var it = q_paddle.iterator();
    while (it.next()) |entity| try mut_commands.removeEntity(entity.id);

    var it2 = q_ball.iterator();
    while (it2.next()) |entity| try mut_commands.removeEntity(entity.id);

    var it3 = q_brick.iterator();
    while (it3.next()) |entity| try mut_commands.removeEntity(entity.id);

    var it4 = q_wall.iterator();
    while (it4.next()) |entity| try mut_commands.removeEntity(entity.id);

    var it5 = q_ui.iterator();
    while (it5.next()) |entity| try mut_commands.removeEntity(entity.id);

    var it6 = q_camera.iterator();
    while (it6.next()) |entity| try mut_commands.removeEntity(entity.id);
}

// ============================================================================
// Playing Phase Systems
// ============================================================================

fn paddle_control(
    key_events: phasor_ecs.EventReader(phasor_glfw.InputPlugin.KeyDown),
    q_paddle: phasor_ecs.Query(.{ Paddle, phasor_vulkan.Transform3d }),
    delta_time: phasor_ecs.Res(phasor_vulkan.DeltaTime),
) !void {
    const dt = delta_time.ptr.seconds;

    var move_left = false;
    var move_right = false;

    while (key_events.tryRecv()) |event| {
        switch (event.key) {
            .a, .left => move_left = true,
            .d, .right => move_right = true,
            else => {},
        }
    }

    var it = q_paddle.iterator();
    if (it.next()) |entity| {
        const paddle = entity.get(Paddle).?;
        const transform = entity.get(phasor_vulkan.Transform3d).?;

        if (move_left) {
            transform.translation.x -= paddle.speed * dt;
        }
        if (move_right) {
            transform.translation.x += paddle.speed * dt;
        }

        // Clamp paddle position
        const half_width = paddle.width / 2.0;
        const arena_half_width: f32 = 290.0;
        if (transform.translation.x - half_width < -arena_half_width) {
            transform.translation.x = -arena_half_width + half_width;
        }
        if (transform.translation.x + half_width > arena_half_width) {
            transform.translation.x = arena_half_width - half_width;
        }
    }
}

fn ball_movement(
    q_ball: phasor_ecs.Query(.{ Ball, phasor_vulkan.Transform3d }),
    q_paddle: phasor_ecs.Query(.{ Paddle, phasor_vulkan.Transform3d }),
    key_events: phasor_ecs.EventReader(phasor_glfw.InputPlugin.KeyDown),
    delta_time: phasor_ecs.Res(phasor_vulkan.DeltaTime),
) !void {
    const dt = delta_time.ptr.seconds;

    var launch = false;
    while (key_events.tryRecv()) |event| {
        if (event.key == .space) {
            launch = true;
        }
    }

    var ball_it = q_ball.iterator();
    if (ball_it.next()) |ball_entity| {
        var ball = ball_entity.get(Ball).?;
        const ball_transform = ball_entity.get(phasor_vulkan.Transform3d).?;

        if (ball.attached_to_paddle) {
            // Follow paddle
            var paddle_it = q_paddle.iterator();
            if (paddle_it.next()) |paddle_entity| {
                const paddle = paddle_entity.get(Paddle).?;
                const paddle_transform = paddle_entity.get(phasor_vulkan.Transform3d).?;
                ball_transform.translation.x = paddle_transform.translation.x;
                ball_transform.translation.y = paddle_transform.translation.y - paddle.height / 2.0 - ball.radius - 5.0;
            }

            // Launch ball
            if (launch) {
                ball.attached_to_paddle = false;
                ball.velocity_x = ball.speed * 0.5;
                ball.velocity_y = -ball.speed;
            }
        } else {
            // Move ball
            ball_transform.translation.x += ball.velocity_x * dt;
            ball_transform.translation.y += ball.velocity_y * dt;
        }
    }
}

fn ball_collision(
    q_ball: phasor_ecs.Query(.{ Ball, phasor_vulkan.Transform3d }),
    q_paddle: phasor_ecs.Query(.{ Paddle, phasor_vulkan.Transform3d }),
    q_walls: phasor_ecs.Query(.{ Wall, phasor_vulkan.Transform3d, phasor_vulkan.Rectangle }),
    commands: *phasor_ecs.Commands,
    r_state: phasor_ecs.ResMut(GameState),
) !void {
    var ball_it = q_ball.iterator();
    if (ball_it.next()) |ball_entity| {
        var ball = ball_entity.get(Ball).?;
        const ball_transform = ball_entity.get(phasor_vulkan.Transform3d).?;

        if (ball.attached_to_paddle) return;

        // Check wall collisions
        var wall_it = q_walls.iterator();
        while (wall_it.next()) |wall_entity| {
            const wall_transform = wall_entity.get(phasor_vulkan.Transform3d).?;
            const wall_rect = wall_entity.get(phasor_vulkan.Rectangle).?;

            const ball_x = ball_transform.translation.x;
            const ball_y = ball_transform.translation.y;
            const wall_x = wall_transform.translation.x;
            const wall_y = wall_transform.translation.y;

            const ball_left = ball_x - ball.radius;
            const ball_right = ball_x + ball.radius;
            const ball_top = ball_y - ball.radius;
            const ball_bottom = ball_y + ball.radius;

            const wall_left = wall_x - wall_rect.width / 2.0;
            const wall_right = wall_x + wall_rect.width / 2.0;
            const wall_top = wall_y - wall_rect.height / 2.0;
            const wall_bottom = wall_y + wall_rect.height / 2.0;

            if (ball_right > wall_left and ball_left < wall_right and
                ball_bottom > wall_top and ball_top < wall_bottom)
            {
                // Determine collision side
                const overlap_left = ball_right - wall_left;
                const overlap_right = wall_right - ball_left;
                const overlap_top = ball_bottom - wall_top;
                const overlap_bottom = wall_bottom - ball_top;

                const min_overlap = @min(@min(overlap_left, overlap_right), @min(overlap_top, overlap_bottom));

                if (min_overlap == overlap_left or min_overlap == overlap_right) {
                    ball.velocity_x = -ball.velocity_x;
                } else {
                    ball.velocity_y = -ball.velocity_y;
                }
            }
        }

        // Check paddle collision
        var paddle_it = q_paddle.iterator();
        if (paddle_it.next()) |paddle_entity| {
            const paddle = paddle_entity.get(Paddle).?;
            const paddle_transform = paddle_entity.get(phasor_vulkan.Transform3d).?;

            const ball_x = ball_transform.translation.x;
            const ball_y = ball_transform.translation.y;
            const paddle_x = paddle_transform.translation.x;
            const paddle_y = paddle_transform.translation.y;

            const ball_bottom = ball_y + ball.radius;
            const paddle_top = paddle_y - paddle.height / 2.0;
            const paddle_bottom = paddle_y + paddle.height / 2.0;
            const paddle_left = paddle_x - paddle.width / 2.0;
            const paddle_right = paddle_x + paddle.width / 2.0;

            if (ball_bottom >= paddle_top and ball_y < paddle_bottom and
                ball_x >= paddle_left and ball_x <= paddle_right and ball.velocity_y > 0)
            {
                ball.velocity_y = -@abs(ball.velocity_y);

                // Add spin based on where the ball hits the paddle
                const hit_pos = (ball_x - paddle_x) / (paddle.width / 2.0);
                ball.velocity_x = hit_pos * ball.speed * 0.7;

                // Normalize velocity
                const speed = @sqrt(ball.velocity_x * ball.velocity_x + ball.velocity_y * ball.velocity_y);
                ball.velocity_x = (ball.velocity_x / speed) * ball.speed;
                ball.velocity_y = (ball.velocity_y / speed) * ball.speed;
            }
        }

        // Check if ball fell off bottom
        if (ball_transform.translation.y > 320.0) {
            r_state.ptr.lives -= 1;
            ball.attached_to_paddle = true;
            ball.velocity_x = 0.0;
            ball.velocity_y = 0.0;

            if (r_state.ptr.lives <= 0) {
                try commands.insertResource(NextPhase{ .phase = GamePhases{ .InGame = .{ .Loser = .{} } } });
            }
        }
    }
}

fn brick_collision(
    q_ball: phasor_ecs.Query(.{ Ball, phasor_vulkan.Transform3d }),
    q_bricks: phasor_ecs.Query(.{ Brick, phasor_vulkan.Transform3d, phasor_vulkan.Rectangle }),
    commands: *phasor_ecs.Commands,
    r_state: phasor_ecs.ResMut(GameState),
) !void {
    var ball_it = q_ball.iterator();
    if (ball_it.next()) |ball_entity| {
        var ball = ball_entity.get(Ball).?;
        const ball_transform = ball_entity.get(phasor_vulkan.Transform3d).?;

        if (ball.attached_to_paddle) return;

        const ball_x = ball_transform.translation.x;
        const ball_y = ball_transform.translation.y;

        var brick_it = q_bricks.iterator();
        while (brick_it.next()) |brick_entity| {
            var brick = brick_entity.get(Brick).?;
            const brick_transform = brick_entity.get(phasor_vulkan.Transform3d).?;
            const brick_rect = brick_entity.get(phasor_vulkan.Rectangle).?;

            const brick_x = brick_transform.translation.x;
            const brick_y = brick_transform.translation.y;

            const ball_left = ball_x - ball.radius;
            const ball_right = ball_x + ball.radius;
            const ball_top = ball_y - ball.radius;
            const ball_bottom = ball_y + ball.radius;

            const brick_left = brick_x - brick_rect.width / 2.0;
            const brick_right = brick_x + brick_rect.width / 2.0;
            const brick_top = brick_y - brick_rect.height / 2.0;
            const brick_bottom = brick_y + brick_rect.height / 2.0;

            if (ball_right > brick_left and ball_left < brick_right and
                ball_bottom > brick_top and ball_top < brick_bottom)
            {
                // Hit brick
                brick.hits_remaining -= 1;
                if (brick.hits_remaining == 0) {
                    r_state.ptr.score += brick.points;
                    try commands.removeEntity(brick_entity.id);
                }

                // Bounce ball
                const overlap_left = ball_right - brick_left;
                const overlap_right = brick_right - ball_left;
                const overlap_top = ball_bottom - brick_top;
                const overlap_bottom = brick_bottom - ball_top;

                const min_overlap = @min(@min(overlap_left, overlap_right), @min(overlap_top, overlap_bottom));

                if (min_overlap == overlap_left or min_overlap == overlap_right) {
                    ball.velocity_x = -ball.velocity_x;
                } else {
                    ball.velocity_y = -ball.velocity_y;
                }

                break;
            }
        }
    }
}

fn check_win_lose(
    q_bricks: phasor_ecs.Query(.{Brick}),
    commands: *phasor_ecs.Commands,
    r_state: phasor_ecs.Res(GameState),
) !void {
    // Check if all bricks are destroyed
    var brick_it = q_bricks.iterator();
    if (brick_it.next() == null) {
        // No bricks left - player wins!

        // Update high scores
        if (commands.getResourceMut(GameState)) |state| {
            var inserted = false;
            for (&state.high_scores, 0..) |*high_score, i| {
                if (r_state.ptr.score > high_score.*) {
                    // Shift scores down
                    var j = state.high_scores.len - 1;
                    while (j > i) : (j -= 1) {
                        state.high_scores[j] = state.high_scores[j - 1];
                    }
                    high_score.* = r_state.ptr.score;
                    inserted = true;
                    break;
                }
            }
            
        }

        try commands.insertResource(NextPhase{ .phase = GamePhases{ .InGame = .{ .Winner = .{} } } });
    }
}

fn pause_input(
    key_events: phasor_ecs.EventReader(phasor_glfw.InputPlugin.KeyDown),
    commands: *phasor_ecs.Commands,
) !void {
    while (key_events.tryRecv()) |event| {
        if (event.key == .escape) {
            try commands.insertResource(NextPhase{ .phase = GamePhases{ .InGame = .{ .PauseMenu = .{} } } });
        }
    }
}

// ============================================================================
// Pause Menu Phase Systems
// ============================================================================

fn setup_pause_menu(
    mut_commands: *phasor_ecs.Commands,
    r_assets: phasor_ecs.Res(GameAssets),
) !void {
    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .PauseMenu },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -100.0, .y = -50.0, .z = 1.0 },
            .scale = .{ .x = 0.6, .y = 0.6, .z = 0.6 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "PAUSED",
            .color = .{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 },
        },
    });

    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .Subtitle },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -200.0, .y = 20.0, .z = 1.0 },
            .scale = .{ .x = 0.35, .y = 0.35, .z = 0.35 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "ESC: Resume  Q: Quit",
            .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        },
    });
}

fn cleanup_pause_menu(
    mut_commands: *phasor_ecs.Commands,
    q_ui: phasor_ecs.Query(.{UIText}),
) !void {
    var it = q_ui.iterator();
    while (it.next()) |entity| {
        const ui = entity.get(UIText).?;
        if (ui.text_type == .PauseMenu or ui.text_type == .Subtitle) {
            try mut_commands.removeEntity(entity.id);
        }
    }
}

fn pause_menu_input(
    key_events: phasor_ecs.EventReader(phasor_glfw.InputPlugin.KeyDown),
    commands: *phasor_ecs.Commands,
) !void {
    while (key_events.tryRecv()) |event| {
        switch (event.key) {
            .escape => {
                try commands.insertResource(NextPhase{ .phase = GamePhases{ .InGame = .{ .Playing = .{} } } });
            },
            .q => {
                try commands.insertResource(NextPhase{ .phase = GamePhases{ .MainMenu = .{} } });
            },
            else => {},
        }
    }
}

// ============================================================================
// Loser Phase Systems
// ============================================================================

fn setup_loser_screen(
    mut_commands: *phasor_ecs.Commands,
    r_assets: phasor_ecs.Res(GameAssets),
    r_state: phasor_ecs.Res(GameState),
) !void {
    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .GameOver },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -150.0, .y = -80.0, .z = 1.0 },
            .scale = .{ .x = 0.7, .y = 0.7, .z = 0.7 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "GAME OVER",
            .color = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        },
    });

    // Show final score
    var buf: [64:0]u8 = undefined;
    const score_text = try std.fmt.bufPrintZ(&buf, "Final Score: {d}", .{r_state.ptr.score});

    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .Subtitle },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -180.0, .y = 0.0, .z = 1.0 },
            .scale = .{ .x = 0.4, .y = 0.4, .z = 0.4 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = score_text,
            .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        },
    });

    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .Subtitle },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -280.0, .y = 50.0, .z = 1.0 },
            .scale = .{ .x = 0.35, .y = 0.35, .z = 0.35 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "SPACE: Menu  H: High Scores",
            .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        },
    });
}

fn cleanup_loser_screen(
    mut_commands: *phasor_ecs.Commands,
    q_ui: phasor_ecs.Query(.{UIText}),
) !void {
    var it = q_ui.iterator();
    while (it.next()) |entity| {
        const ui = entity.get(UIText).?;
        if (ui.text_type == .GameOver or ui.text_type == .Subtitle) {
            try mut_commands.removeEntity(entity.id);
        }
    }
}

fn loser_input(
    key_events: phasor_ecs.EventReader(phasor_glfw.InputPlugin.KeyDown),
    commands: *phasor_ecs.Commands,
) !void {
    while (key_events.tryRecv()) |event| {
        switch (event.key) {
            .space => {
                try commands.insertResource(NextPhase{ .phase = GamePhases{ .MainMenu = .{} } });
            },
            .h => {
                try commands.insertResource(NextPhase{ .phase = GamePhases{ .HighScore = .{} } });
            },
            else => {},
        }
    }
}

// ============================================================================
// Winner Phase Systems
// ============================================================================

fn setup_winner_screen(
    mut_commands: *phasor_ecs.Commands,
    r_assets: phasor_ecs.Res(GameAssets),
    r_state: phasor_ecs.Res(GameState),
) !void {
    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .Victory },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -180.0, .y = -80.0, .z = 1.0 },
            .scale = .{ .x = 0.7, .y = 0.7, .z = 0.7 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "YOU WIN!",
            .color = .{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 },
        },
    });

    // Show final score
    var buf: [64:0]u8 = undefined;
    const score_text = try std.fmt.bufPrintZ(&buf, "Final Score: {d}", .{r_state.ptr.score});

    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .Subtitle },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -180.0, .y = 0.0, .z = 1.0 },
            .scale = .{ .x = 0.4, .y = 0.4, .z = 0.4 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = score_text,
            .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        },
    });

    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .Subtitle },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -280.0, .y = 50.0, .z = 1.0 },
            .scale = .{ .x = 0.35, .y = 0.35, .z = 0.35 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "SPACE: Menu  H: High Scores",
            .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        },
    });
}

fn cleanup_winner_screen(
    mut_commands: *phasor_ecs.Commands,
    q_ui: phasor_ecs.Query(.{UIText}),
) !void {
    var it = q_ui.iterator();
    while (it.next()) |entity| {
        const ui = entity.get(UIText).?;
        if (ui.text_type == .Victory or ui.text_type == .Subtitle) {
            try mut_commands.removeEntity(entity.id);
        }
    }
}

fn winner_input(
    key_events: phasor_ecs.EventReader(phasor_glfw.InputPlugin.KeyDown),
    commands: *phasor_ecs.Commands,
) !void {
    while (key_events.tryRecv()) |event| {
        switch (event.key) {
            .space => {
                try commands.insertResource(NextPhase{ .phase = GamePhases{ .MainMenu = .{} } });
            },
            .h => {
                try commands.insertResource(NextPhase{ .phase = GamePhases{ .HighScore = .{} } });
            },
            else => {},
        }
    }
}

// ============================================================================
// High Score Phase Systems
// ============================================================================

fn setup_high_score(
    mut_commands: *phasor_ecs.Commands,
    r_assets: phasor_ecs.Res(GameAssets),
    r_state: phasor_ecs.Res(GameState),
) !void {
    // Always create a new camera
    _ = try mut_commands.createEntity(.{
        phasor_vulkan.Camera3d{
            .Viewport = .{
                .mode = .Center,
            },
        },
        phasor_vulkan.Transform3d{},
    });

    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .HighScore },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -200.0, .y = -150.0, .z = 0.0 },
            .scale = .{ .x = 0.6, .y = 0.6, .z = 0.6 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "HIGH SCORES",
            .color = .{ .r = 1.0, .g = 0.8, .b = 0.0, .a = 1.0 },
        },
    });

    // Display high scores
    for (r_state.ptr.high_scores, 0..) |score, i| {
        var buf: [64:0]u8 = undefined;
        const score_text = try std.fmt.bufPrintZ(&buf, "{d}. {d}", .{ i + 1, score });

        _ = try mut_commands.createEntity(.{
            UIText{ .text_type = .HighScore },
            phasor_vulkan.Transform3d{
                .translation = .{ .x = -100.0, .y = -50.0 + @as(f32, @floatFromInt(i)) * 40.0, .z = 0.0 },
                .scale = .{ .x = 0.4, .y = 0.4, .z = 0.4 },
            },
            phasor_vulkan.Text{
                .font = &r_assets.ptr.orbitron_font,
                .text = score_text,
                .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
            },
        });
    }

    _ = try mut_commands.createEntity(.{
        UIText{ .text_type = .Subtitle },
        phasor_vulkan.Transform3d{
            .translation = .{ .x = -200.0, .y = 200.0, .z = 0.0 },
            .scale = .{ .x = 0.35, .y = 0.35, .z = 0.35 },
        },
        phasor_vulkan.Text{
            .font = &r_assets.ptr.orbitron_font,
            .text = "Press SPACE to return",
            .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        },
    });
}

fn cleanup_high_score(
    mut_commands: *phasor_ecs.Commands,
    q_ui: phasor_ecs.Query(.{UIText}),
    q_camera: phasor_ecs.Query(.{phasor_vulkan.Camera3d}),
) !void {
    var it = q_ui.iterator();
    while (it.next()) |entity| {
        try mut_commands.removeEntity(entity.id);
    }

    var it2 = q_camera.iterator();
    while (it2.next()) |entity| {
        try mut_commands.removeEntity(entity.id);
    }
}

fn high_score_input(
    key_events: phasor_ecs.EventReader(phasor_glfw.InputPlugin.KeyDown),
    commands: *phasor_ecs.Commands,
) !void {
    while (key_events.tryRecv()) |event| {
        if (event.key == .space) {
            try commands.insertResource(NextPhase{ .phase = GamePhases{ .MainMenu = .{} } });
        }
    }
}

// ============================================================================
// Main Entry Point
// ============================================================================

pub fn main() !u8 {
    var app = try phasor_ecs.App.default(std.heap.page_allocator);
    defer app.deinit();

    const window_plugin = phasor_glfw.WindowPlugin.init(.{
        .title = "Pharkanoid - Phasor Arkanoid",
        .width = 800,
        .height = 600,
    });
    try app.addPlugin(&window_plugin);

    var input_plugin = phasor_glfw.InputPlugin{};
    try app.addPlugin(&input_plugin);

    const vk_plugin = phasor_vulkan.VulkanPlugin.init(.{});
    try app.addPlugin(&vk_plugin);

    var time_plugin = phasor_vulkan.TimePlugin{};
    try app.addPlugin(&time_plugin);

    var asset_plugin = phasor_vulkan.AssetPlugin(GameAssets){};
    try app.addPlugin(&asset_plugin);

    // Add Phase Plugin
    var phase_plugin = GamePhasesPlugin{ .allocator = std.heap.page_allocator };
    try app.addPlugin(&phase_plugin);

    return try app.run();
}
