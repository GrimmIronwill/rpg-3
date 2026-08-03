class_name PlayerDebugDraw
extends Node2D
## Дебаг пошагового боя: радиус атаки в клетках, клетка под курсором, ОД.

var player : Player

const COL_ZONE  := Color(1.0, 0.55, 0.1, 0.12)
const COL_EDGE  := Color(1.0, 0.55, 0.1, 0.8)
const COL_FLASH := Color(1.0, 0.15, 0.15, 0.25)
const COL_OK    := Color(0.3, 1.0, 0.3, 0.9)
const COL_BAD   := Color(1.0, 0.3, 0.3, 0.9)
const COL_AIM   := Color(1, 1, 1, 0.4)

func _ready() -> void:
	z_index = 100

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if player == null or player.attack_node == null: return
	var atk = player.attack_node
	var cell := player.cell_size_px()
	var rng := (player.attack_range_cells() + 0.5) * cell.x

	# --- Радиус атаки ---
	draw_circle(Vector2.ZERO, rng, COL_FLASH if atk.last_attack_flash > 0.0 else COL_ZONE)
	draw_arc(Vector2.ZERO, rng, 0, TAU, 48, COL_EDGE, 1.5)

	# --- Клетка под курсором: зелёная = можно атаковать ---
	var mcell : Vector2i = player.world_to_cell(player.get_global_mouse_position())
	var ok := Character.chebyshev(player.grid_pos, mcell) <= player.attack_range_cells() \
		and player.line_clear_to_cell(mcell)
	var rect_pos := to_local(player.cell_to_world(mcell)) - cell * 0.5
	draw_rect(Rect2(rect_pos, cell), COL_OK if ok else COL_BAD, false, 2.0)

	# --- Прицел ---
	draw_line(Vector2.ZERO, atk.aim_dir() * 20.0, COL_AIM, 1.0)

	# --- ОД + оружие ---
	var w = atk.weapon()
	var wname : String = w.name if w else "кулаки"
	draw_string(ThemeDB.fallback_font, Vector2(-40, -38),
		"ОД: %d/%d" % [player.action_points, Character.ACTIONS_PER_TURN],
		HORIZONTAL_ALIGNMENT_CENTER, 80, 10, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(-40, -24), wname,
		HORIZONTAL_ALIGNMENT_CENTER, 80, 10, Color.WHITE)
