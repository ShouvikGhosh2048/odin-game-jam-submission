// This file is compiled as part of the `odin.dll` file. It contains the
// procs that `game_hot_reload.exe` will call, such as:
//
// game_init: Sets up the game state
// game_update: Run once per frame
// game_shutdown: Shuts down game and frees memory
// game_memory: Run just before a hot reload, so game.exe has a pointer to the
//		game's memory.
// game_hot_reloaded: Run after a hot reload so that the `g_mem` global variable
//		can be set to whatever pointer it was in the old DLL.
//
// Note: When compiled as part of the release executable this whole package is imported as a normal
// odin package instead of a DLL.

package game

import "core:math/linalg"
import "core:fmt"
import "core:math/rand"
import "core:math"
import rl "vendor:raylib"

GRID_WIDTH :: 7
GRID_HEIGHT :: 150
GRID_CELL_SIZE :: 100.0
PLAYER_RADIUS :: 1.0
X_MIN :: f32((-GRID_WIDTH / 2) * GRID_CELL_SIZE) + 1
X_MAX :: f32((GRID_WIDTH - 1 - GRID_WIDTH / 2) * GRID_CELL_SIZE) - 1
Z_MIN :: f32((-GRID_HEIGHT / 2) * GRID_CELL_SIZE) + 1
Z_MAX :: f32((GRID_HEIGHT - 1 - GRID_HEIGHT / 2) * GRID_CELL_SIZE) - 1

Game_Memory :: struct {
	position: rl.Vector3,
	velocity: rl.Vector3,
	heights: [dynamic]f32,
	time: u32,
	air_time: u32,
	won: bool,
}

g_mem: ^Game_Memory

grid_height_and_normal :: proc(x, z: f32) -> (f32, [3]f32) {
	clamp_x := clamp(x, X_MIN, X_MAX)
	clamp_z := clamp(z, Z_MIN, Z_MAX)
	i := i32(math.floor(clamp_x / GRID_CELL_SIZE)) + GRID_WIDTH / 2
	j := i32(math.floor(clamp_z / GRID_CELL_SIZE)) + GRID_HEIGHT / 2
	assert(0 <= i && i < GRID_WIDTH - 1 && 0 <= j && j < GRID_HEIGHT - 1)

	z_amount := clamp_z / GRID_CELL_SIZE - f32(i32(math.floor(clamp_z / GRID_CELL_SIZE)))
	x_amount := clamp_x / GRID_CELL_SIZE - f32(i32(math.floor(clamp_x / GRID_CELL_SIZE)))

	v1 := [3]f32 { f32(i - GRID_WIDTH / 2) * GRID_CELL_SIZE, g_mem.heights[GRID_HEIGHT * i + j], f32(j - GRID_HEIGHT / 2) * GRID_CELL_SIZE }
	v2 := [3]f32 { f32(i + 1 - GRID_WIDTH / 2) * GRID_CELL_SIZE, g_mem.heights[GRID_HEIGHT * (i + 1) + j], f32(j - GRID_HEIGHT / 2) * GRID_CELL_SIZE }
	v3 := [3]f32 { f32(i - GRID_WIDTH / 2) * GRID_CELL_SIZE, g_mem.heights[GRID_HEIGHT * i + j + 1], f32(j + 1 - GRID_HEIGHT / 2) * GRID_CELL_SIZE }
	v4 := [3]f32 { f32(i + 1 - GRID_WIDTH / 2) * GRID_CELL_SIZE, g_mem.heights[GRID_HEIGHT * (i + 1) + j + 1], f32(j + 1 - GRID_HEIGHT / 2) * GRID_CELL_SIZE }

	if (z_amount + x_amount < 1.0) {
		return v1.y + z_amount * (v3.y - v1.y) + x_amount * (v2.y - v1.y), linalg.normalize0(linalg.vector_cross3(v3 - v1, v2 - v1))
	} else {
		return v4.y + (1 - x_amount) * (v3.y - v4.y) + (1 - z_amount) * (v2.y - v4.y), linalg.normalize0(linalg.vector_cross3(v4 - v3, v2 - v3))
	}
}

update :: proc() {
	input: rl.Vector3

	if rl.IsKeyDown(.UP) {
		input.z -= 1.0
	}
	if rl.IsKeyDown(.DOWN) {
		input.z += 1.0
	}
	if rl.IsKeyDown(.LEFT){
		input.x -= 1.0
	}
	if rl.IsKeyDown(.RIGHT) {
		input.x += 1.0
	}

	input = linalg.normalize0(input)

	for _ in 0..<10 {
		current_grid_height, current_grid_normal := grid_height_and_normal(g_mem.position.x, g_mem.position.z)
		on_ground := abs(g_mem.position.y - current_grid_height - PLAYER_RADIUS) < 0.1

		// Gravity
		g_mem.velocity.y -= 0.001
		// User input
		if on_ground {
			input_tangent := linalg.normalize0(input - linalg.vector_dot(input, current_grid_normal) * current_grid_normal)
			g_mem.velocity += 0.01 * input_tangent
		}
		// Normal forces
		if on_ground {
			g_mem.velocity -= linalg.vector_dot(g_mem.velocity, current_grid_normal) * current_grid_normal
		}
		// Drag
		if on_ground {
			g_mem.velocity -= 0.001 * g_mem.velocity
		}
		if linalg.length(g_mem.velocity) > 3.0 {
			g_mem.velocity = 3.0 * linalg.normalize0(g_mem.velocity)
		}

		g_mem.position += g_mem.velocity / 10.0
		g_mem.position.x = clamp(g_mem.position.x, X_MIN, X_MAX)
		g_mem.position.z = clamp(g_mem.position.z, Z_MIN, Z_MAX)

		new_grid_height, _ := grid_height_and_normal(g_mem.position.x, g_mem.position.z)
		if new_grid_height + PLAYER_RADIUS > g_mem.position.y {
			g_mem.position.y = new_grid_height + PLAYER_RADIUS
		}
	}

	current_grid_height, _ := grid_height_and_normal(g_mem.position.x, g_mem.position.z)
	on_ground := abs(g_mem.position.y - current_grid_height - PLAYER_RADIUS) < 0.1

	if g_mem.position.z < Z_MIN + 100.0 {
		g_mem.won = true
	}
	if !g_mem.won {
		if !on_ground {
			g_mem.air_time += 1
		}
		g_mem.time += 1
	}

	if rl.IsKeyPressed(.R) {
		g_mem.velocity = {}
		clear(&g_mem.heights)
		g_mem.time = 0
		g_mem.air_time = 0
		g_mem.won = false
		for _ in 0..< GRID_WIDTH {
			for j in 0..< GRID_HEIGHT {
				if j == 30 {
					append(&g_mem.heights, 100)
				} else {
					append(&g_mem.heights, 50.0 * rand.float32())
				}
			}
		}
	
		g_mem.position = rl.Vector3{ 0.0, 0.0, Z_MAX - 10.0 }
		g_mem.position.y, _ = grid_height_and_normal(g_mem.position.x, g_mem.position.z)
		g_mem.position.y += PLAYER_RADIUS
	}
}

triangle_color :: proc(v1, v2, v3: rl.Vector3, color1, color2: rl.Color) -> rl.Color {
	normal_dot := linalg.vector_dot(
		linalg.normalize0(linalg.vector_cross3(v2 - v1, v3 - v1)),
		linalg.normalize0([3]f32 {1.0, 1.0, 1.0}),
	)
	avg_coeff := (1.0 + normal_dot) / 2.0
	return rl.Color{
		u8(f32(color1.r) * avg_coeff + f32(color2.r) * (1 - avg_coeff)),
		u8(f32(color1.g) * avg_coeff + f32(color2.g) * (1 - avg_coeff)),
		u8(f32(color1.b) * avg_coeff + f32(color2.b) * (1 - avg_coeff)),
		255,
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	game_camera := rl.Camera {
		position = g_mem.position + {0, 30.0, 45.0},
		target = g_mem.position + {0, 0.0, 0.0},
		up = linalg.normalize0([3]f32{0, 1, 0}),
		fovy = 60,
	}

	rl.BeginMode3D(game_camera)
	for i in 0..<GRID_WIDTH-1 {
		for j in 0..<GRID_HEIGHT-1 {
			v1 := [3]f32 { f32(i - GRID_WIDTH / 2) * GRID_CELL_SIZE, g_mem.heights[GRID_HEIGHT * i + j], f32(j - GRID_HEIGHT / 2) * GRID_CELL_SIZE }
			v2 := [3]f32 { f32(i + 1 - GRID_WIDTH / 2) * GRID_CELL_SIZE, g_mem.heights[GRID_HEIGHT * (i + 1) + j], f32(j - GRID_HEIGHT / 2) * GRID_CELL_SIZE }
			v3 := [3]f32 { f32(i - GRID_WIDTH / 2) * GRID_CELL_SIZE, g_mem.heights[GRID_HEIGHT * i + j + 1], f32(j + 1 - GRID_HEIGHT / 2) * GRID_CELL_SIZE }
			v4 := [3]f32 { f32(i + 1 - GRID_WIDTH / 2) * GRID_CELL_SIZE, g_mem.heights[GRID_HEIGHT * (i + 1) + j + 1], f32(j + 1 - GRID_HEIGHT / 2) * GRID_CELL_SIZE }

			rl.DrawTriangle3D(v1, v3, v2, triangle_color(v1, v3, v2, rl.WHITE, rl.BLACK))
			rl.DrawTriangle3D(v3, v4, v2, triangle_color(v3, v4, v2, rl.WHITE, rl.BLACK))
		}
	}
	grid_height, _ := grid_height_and_normal(g_mem.position.x, g_mem.position.z)
	rl.DrawSphere({g_mem.position.x, grid_height - 0.2, g_mem.position.z}, PLAYER_RADIUS, rl.BLACK)
	rl.DrawSphere(g_mem.position, PLAYER_RADIUS, rl.ORANGE)
	rl.DrawCube({0, 0, Z_MAX }, X_MAX - X_MIN + 10.0, 200.0, 50.0, rl.Color { 0, 0, 255, 100 })
	rl.DrawCube({0, 0, Z_MIN }, X_MAX - X_MIN + 10.0, 200.0, 50.0, rl.Color { 0, 0, 255, 100 })
	rl.EndMode3D()

	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), 20, rl.BLACK)
	rl.DrawText(fmt.ctprintf("Time: {} Air time: {}", g_mem.time / 60, g_mem.air_time / 60), 0, 0, 20, rl.WHITE)
	if g_mem.won {
		rl.DrawRectangle(rl.GetScreenWidth() / 2 - 100.0, rl.GetScreenHeight() / 2 - 100.0, 200.0, 200.0, rl.BLACK)
		rl.DrawText("WON", rl.GetScreenWidth() / 2 - 20.0, rl.GetScreenHeight() / 2 - 50.0, 20.0, rl.WHITE)
		score_text := fmt.ctprintf("Score: {}", 500 - i32(g_mem.time) + 3 * i32(g_mem.air_time))
		rl.DrawText(score_text, rl.GetScreenWidth() / 2 - rl.MeasureText(score_text, 20.0) / 2.0, rl.GetScreenHeight() / 2, 20.0, rl.WHITE)
		reset_text := fmt.ctprintf("Press R to reset")
		rl.DrawText(reset_text, rl.GetScreenWidth() / 2 - rl.MeasureText(reset_text, 20.0) / 2.0, rl.GetScreenHeight() / 2 + 50.0, 20.0, rl.WHITE)
	}
	rl.EndDrawing()
}

@(export)
game_update :: proc() -> bool {
	update()
	draw()
	return !rl.WindowShouldClose()
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Odin + Raylib + Hot Reload template!")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(60)
}

@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	g_mem^ = Game_Memory {}
	for _ in 0..< GRID_WIDTH {
		for j in 0..< GRID_HEIGHT {
			if j == 30 {
				append(&g_mem.heights, 100)
			} else {
				append(&g_mem.heights, 50.0 * rand.float32())
			}
		}
	}

	g_mem.position = rl.Vector3{ 0.0, 0.0, Z_MAX - 10.0 }
	g_mem.position.y, _ = grid_height_and_normal(g_mem.position.x, g_mem.position.z)
	g_mem.position.y += PLAYER_RADIUS

	game_hot_reloaded(g_mem)
}

@(export)
game_shutdown :: proc() {
	delete(g_mem.heights)
	free(g_mem)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g_mem
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g_mem = (^Game_Memory)(mem)
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}
