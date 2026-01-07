#import "Basic";
#import "Math";
#import "SDL";

Entity :: struct {
    p: Vector2;
    dp: Vector2;

    radius: float;  // If the entity has a circular collision shape.

    grounded: bool;
    ground_normal: Vector2;
}

Segment :: struct {
    a: Vector2;
    b: Vector2;
}

Collision :: struct {
    normal: Vector2;
    depth: float;
}

Input :: struct {
    left, right, up, down: bool;
}

input: Input;

last_time: float64;
remaining_time: float64;
should_quit_game := false;
timestep: float : 1.0 / 480.0;  // This is the fixed timestep at which our physics simulation runs.
time_passage_rate : float64 = 1.0;  // @@ Maybe we should make this unsigned...

Level_Geometry :: struct {
    segments: [..] Segment;
}

level_geometries: [..] Level_Geometry;
current_level_index: int;

// segments: [..] Segment;
ball: Entity;

draw_velocity := false;
draw_normal := false;
gravity_enabled := true;
damping_enabled := false;

main :: () {
    ball.p = .{10, 10};
    ball.radius = 1.5;

    {
        level_one: Level_Geometry;

        array_add(*level_one.segments, .{.{-10, 10}, .{-10, 20}});
        array_add(*level_one.segments, .{.{-10, 10}, .{0, 0}});
        array_add(*level_one.segments, .{.{0, 0}, .{25, 0}});
        array_add(*level_one.segments, .{.{25, 0}, .{50, 10}});
        array_add(*level_one.segments, .{.{50, 10}, .{55, -10}});
        array_add(*level_one.segments, .{.{5, 5}, .{10, 5}});  // Floating platform

        array_add(*level_geometries, level_one);
    }

    {
        level_two: Level_Geometry;

        array_add(*level_two.segments, .{.{-10, 0}, .{52, 0}});

        array_add(*level_two.segments, .{.{15, 0}, .{15, 1.2}});
        array_add(*level_two.segments, .{.{15, 1.2}, .{20, 1.2}});
        array_add(*level_two.segments, .{.{20, 1.2}, .{20, 2.4}});
        array_add(*level_two.segments, .{.{20, 2.4}, .{25, 2.4}});
        array_add(*level_two.segments, .{.{25, 2.4}, .{25, 3.6}});
        array_add(*level_two.segments, .{.{25, 3.6}, .{30, 3.6}});
        array_add(*level_two.segments, .{.{30, 3.6}, .{30, 0}});

        array_add(*level_two.segments, .{.{5, 0}, .{5, 1.5}});
        array_add(*level_two.segments, .{.{5, 1.5}, .{-5, 1.5}});
        array_add(*level_two.segments, .{.{-5, 1.5}, .{-5, 3}});
        array_add(*level_two.segments, .{.{-5, 3}, .{-10, 3}});
        array_add(*level_two.segments, .{.{-10, 0}, .{-10, 3}});

        array_add(*level_two.segments, .{.{37, 3}, .{37, 4.5}});
        array_add(*level_two.segments, .{.{37, 4.5}, .{42, 4.5}});
        array_add(*level_two.segments, .{.{42, 4.5}, .{42, 3}});
        array_add(*level_two.segments, .{.{37, 3}, .{42, 3}});

        array_add(*level_geometries, level_two);
    }

    {
        level_three: Level_Geometry;

        array_add(*level_three.segments, .{.{-10, -10}, .{-10, 20}});
        array_add(*level_three.segments, .{.{-10, -10}, .{40, 20}});
        array_add(*level_three.segments, .{.{40, 20}, .{52, 20}});

        array_add(*level_geometries, level_three);
    }

    SDL_Init(.SDL_INIT_VIDEO);

    window := SDL_CreateWindow("Physics Demo", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 1280, 720, 0);
    renderer := SDL_CreateRenderer(window, 0, .ACCELERATED | .PRESENTVSYNC);

    last_time = seconds_since_init();

    while !should_quit_game {
        update_window_events();

        keys := SDL_GetKeyboardState(null);

        input.left = cast(bool) keys[SDL_SCANCODE_LEFT];
        input.right = cast(bool) keys[SDL_SCANCODE_RIGHT];
        input.down = cast(bool) keys[SDL_SCANCODE_DOWN];
        input.up = cast(bool) keys[SDL_SCANCODE_UP];

        current_time := seconds_since_init();
        delta_time := current_time - last_time;
        last_time = current_time;

        remaining_time += delta_time * time_passage_rate;
        while remaining_time >= timestep {
            simulate(timestep);
            remaining_time -= timestep;
        }

        draw_one_frame(renderer, xx delta_time);

        reset_temporary_storage();
    }
}

get_level_geometry :: inline () -> *Level_Geometry {
    return *level_geometries[current_level_index];
}

reset_ball_physics :: inline () {
    ball.p = .{10, 10};
    ball.dp = .{0, 0};
    ball.grounded = false;
}

draw_one_frame :: (renderer: *SDL_Renderer, dt: float) {
    SDL_SetRenderDrawColor(renderer, 0x18, 0x18, 0x18, 0xff);
    SDL_RenderClear(renderer);

    // This just transforms the world position so we can see it on the screen easier.
    transform :: (v: Vector2) -> SDL_Point {
        r: SDL_Point;

        scale :: 20.0;
        r.x = cast(s32) (220 + v.x * scale);
        r.y = cast(s32) (500 - v.y * scale);

        return r;
    }

    direction :: inline (angle: float) -> Vector2 {
        return .{cos(angle), sin(angle)};
    }

    // Draw a circle at the player's position
    {
        SDL_SetRenderDrawColor(renderer, 24, 210, 240, 255);

        prev := transform(ball.p + direction(0) * ball.radius);

        segments :: 32;
        for 1..segments {
            a := transform(ball.p + direction(it * 2 * PI / segments) * ball.radius);
            SDL_RenderDrawLine(renderer, prev.x, prev.y, a.x, a.y);
            prev = a;
        }
    }

    if draw_normal && ball.grounded {
        SDL_SetRenderDrawColor(renderer, 0xff, 0, 0, 0xff);
        p := transform(ball.p);
        np := transform(ball.p + normalize(ball.ground_normal) * ball.radius);
        SDL_RenderDrawLine(renderer, p.x, p.y, np.x, np.y);
    }

    if draw_velocity {
        SDL_SetRenderDrawColor(renderer, 0, 0xff, 0, 0xff);
        p := transform(ball.p);
        np := transform(ball.p + normalize(ball.dp) * ball.radius);
        SDL_RenderDrawLine(renderer, p.x, p.y, np.x, np.y);
    }

    SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff);

    level := get_level_geometry();
    for level.segments {
        a := transform(it.a);
        b := transform(it.b);

        SDL_RenderDrawLine(renderer, a.x, a.y, b.x, b.y);

        rect: SDL_Rect = .{ a.x - 2, a.y - 2, 4, 4 };
        SDL_RenderDrawRect(renderer, *rect);
        rect = .{ b.x - 2, b.y - 2, 4, 4 };
        SDL_RenderDrawRect(renderer, *rect);
    }

    SDL_SetRenderDrawColor(renderer, 0xff, 0, 0, 0xff);

    // Debug display

    if gravity_enabled {
        SDL_RenderDrawLine(renderer, 20, 20, 20, 40);
        SDL_RenderDrawLine(renderer, 20, 40, 15, 35);
        SDL_RenderDrawLine(renderer, 20, 40, 25 , 35);
    }

    if damping_enabled {
        SDL_RenderDrawLine(renderer, 15, 20, 25, 20);
    }

    SDL_RenderPresent(renderer);
}

update_window_events :: () {
    event: SDL_Event = ---;

    while SDL_PollEvent(*event) {
        if event.type == .SDL_QUIT  should_quit_game = true;

        if event.type == .SDL_KEYDOWN {
            if event.key.keysym.sym == {
              case .SDLK_j;
                time_passage_rate *= 2;
                if time_passage_rate > MAX_TIME_PASSAGE_RATE then time_passage_rate = MAX_TIME_PASSAGE_RATE;
                print("Time rate: %\n", time_passage_rate);
              case .SDLK_k;
                time_passage_rate /= 2;
                print("Time rate: %\n", time_passage_rate);
              case .SDLK_r;
                reset_ball_physics();
              case .SDLK_v;
                draw_velocity = !draw_velocity;
              case .SDLK_n;
                draw_normal = !draw_normal;
              case .SDLK_g;
                gravity_enabled = !gravity_enabled;
              case .SDLK_l;
                damping_enabled = !damping_enabled;
              case .SDLK_1;
                reset_ball_physics();
                current_level_index = 0;
              case .SDLK_2;
                reset_ball_physics();
                current_level_index = 1;
              case .SDLK_3;
                reset_ball_physics();
                current_level_index = 2;
            }
        }
    }
}

TERMINAL_VELOCITY :: 90;  // Taken from here: https://en.wikipedia.org/wiki/Terminal_velocity
UP :: Vector2.{0, 1};
GRAVITY :: -49;
MAX_SLOPE_ANGLE_DEGREES :: 80;
MOVEMENT_SPEED :: 12.0;
JUMP_VELOCITY :: 16;
DAMPING_FACTOR :: 2.5;
MAX_TIME_PASSAGE_RATE :: 64;  // Must be a power of two... Well not actually, but we only increment by powers of two.

simulate :: (dt: float) {
    input_dir := cast(s32) input.right - cast(s32) input.left;
    target_speed := input_dir * MOVEMENT_SPEED;

    a := ifx input_dir != 0 then 0.8 else 0.999;
    if !ball.grounded  a *= 0.5;  // It's harder to turn in the air.

    if ball.grounded {
        tangent := normalize(Vector2.{ball.ground_normal.y, -ball.ground_normal.x});
        ball.dp = lerp(ball.dp, target_speed * tangent, MOVEMENT_SPEED * a * dt);
    } else {
        ball.dp.x = lerp(ball.dp.x, target_speed, MOVEMENT_SPEED * a * dt);
    }

    if gravity_enabled && !ball.grounded  ball.dp.y += GRAVITY * dt;

    if ball.grounded && input.up {
        ball.dp.y = JUMP_VELOCITY;
    }

    if damping_enabled  ball.dp += -DAMPING_FACTOR * ball.dp * dt;

    level := get_level_geometry();
    ball.p, ball.dp = move_and_collide(ball.p, ball.dp, dt, ball.radius, level.segments);

    max_slope_dot := cos(MAX_SLOPE_ANGLE_DEGREES * PI / 180);  // @@ Calculate this statically...

    ball.grounded = false;
    for segment: level.segments {
        closest := closest_point_on_segment(ball.p, segment);
        if closest.y > ball.p.y  continue;

        delta := ball.p - closest;
        distance := length(delta);

        if abs(distance - ball.radius) <= 0.01 {
            normal := delta * (1 / distance);

            slope_dot := dot(normal, UP);

            if slope_dot >= max_slope_dot {
                ball.grounded = true;
                ball.ground_normal = normal;
            }
        }
    }
}

move_and_collide :: (p: Vector2, dp: Vector2, dt: float, radius: float, segments: [] Segment) -> np: Vector2, ndp: Vector2 {
    np := p + dp * dt;
    ndp := dp;

    for 1..5 {
        collision := collide_with_segments(np, radius, segments);
        if collision.depth == 0  break;

        np += collision.normal * collision.depth;
        ndp = ndp - dot(ndp, collision.normal) * collision.normal;
    }

    return np, ndp;
}

closest_point_on_segment :: (p: Vector2, segment: Segment) -> Vector2 {
    tangent := segment.b - segment.a;

    point_vector := p - segment.a;

    projection_length := dot(point_vector, tangent);
    tangent_length_squared := dot(tangent, tangent);

    t := projection_length / tangent_length_squared;
    Clamp(*t, 0, 1);

    closest_point := segment.a + tangent * t;

    return closest_point;
}

collide_disk_with_segment :: (center: Vector2, radius: float, segment: Segment) -> Collision {
    delta := center - closest_point_on_segment(center, segment);

    if dot(delta, delta) > radius * radius  return .{};  // Too far away! No collision.

    distance := length(delta);
    n := delta * (1 / distance);

    return .{n, radius - distance};
}

collide_with_segments :: (p: Vector2, radius: float, segments: [] Segment) -> Collision {
    deepest: Collision;

    for segments {
        collision := collide_disk_with_segment(p, radius, it);

        if collision.depth > deepest.depth  deepest = collision;
    }

    return deepest;
}

rotate_left :: inline (v: Vector2) -> Vector2 {
    return .{-v.y, v.x};
}

move_toward :: (a: float, b: float, amount_increasing: float, amount_decreasing := -1.0) -> float {
    if a > b {
        if amount_decreasing == -1  amount_decreasing = amount_increasing;

        a -= amount_decreasing;

        if a < b  a = b;
    } else {
        a += amount_increasing;
        if a > b  a = b;
    }

    return a;
}

move_toward :: (a_pointer: *float, target: float, dt: float, rate_up: float, rate_down: float = -1.0) {
    a := a_pointer.*;

    if a > target {
        if rate_down == -1 rate_down = rate_up;
        a -= dt * rate_down;
        if a < target  a = target;
        a_pointer.* = a;
    } else if a < target {
        a += dt * rate_up;
        if a > target  a = target;
        a_pointer.* = a;
    }
}

    // radius_squared := ball.radius*ball.radius;
    // ball.p += ball.dp * dt;

    // ball.grounded = false;
    // for segment: segments {
    //     a := segment.a;
    //     b := segment.b;
    //     p := ball.p;

    //     ap := p - a;
    //     ab := b - a;
    //     t := clamp(dot(ap, ab) / dot(ab, ab), 0, 1);
    //     closest := a + ab * t;
    //     cp := p - closest;
    //     normal := normalize(cp);
    //     distance_squared := dot(cp, cp);

    //     if distance_squared < radius_squared {
    //         ball.p += normal * (ball.radius - sqrt(distance_squared));

    //         slope_dot := dot(normal, UP);
    //         max_slope_dot := cos(MAX_SLOPE_ANGLE_DEGREES * PI / 180);

    //         if slope_dot >= max_slope_dot {
    //             // ball.grounded = true;
    //             // ball.ground_normal = normal;

    //             velocity_normal := dot(ball.dp, normal);
    //             if velocity_normal < 0 {
    //                 ball.dp -= normal * velocity_normal;
    //             }
    //         } else {
    //             velocity_normal := dot(ball.dp, normal);
    //             ball.dp -= normal * (velocity_normal * (1 + BOUNCE));
    //         }
    //     }
    // }
