class_name EnemyDebugDraw
extends Node2D

var enemy : Enemy

const COL_VISION      := Color(1, 1, 0, 0.10)
const COL_VISION_EDGE := Color(1, 1, 0, 0.5)
const COL_VISION_SEE  := Color(1, 0, 0, 0.18)
const COL_ATTACK      := Color(1, 0.3, 0.2, 0.6)
const COL_ALERT       := Color(0.4, 0.7, 1, 0.25)
const COL_FACING      := Color(0, 1, 0, 0.9)
const COL_PATH        := Color(0.2, 0.9, 1, 0.8)
const COL_TARGET      := Color(1, 0, 1, 0.9)
const COL_LKP         := Color(1, 0.6, 0, 0.9)

func _ready() -> void:
	z_index = 100
	top_level = false

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if enemy == null: return

	# --- Конус/круг обзора (от facing = направление последнего шага) ---
	var see := enemy.can_see_target()
	var fill := COL_VISION_SEE if see else COL_VISION
	var facing : Vector2 = enemy.facing
	if enemy.vision_angle_deg >= 360.0:
		draw_circle(Vector2.ZERO, enemy.vision_range, fill)
		draw_arc(Vector2.ZERO, enemy.vision_range, 0, TAU, 48, COL_VISION_EDGE, 1.0)
	else:
		var half := deg_to_rad(enemy.vision_angle_deg * 0.5)
		var base := facing.angle()
		var pts := PackedVector2Array([Vector2.ZERO])
		var steps := 24
		for i in range(steps + 1):
			var a := base - half + (half * 2.0) * i / steps
			pts.append(Vector2.from_angle(a) * enemy.vision_range)
		draw_colored_polygon(pts, fill)
		draw_arc(Vector2.ZERO, enemy.vision_range, base - half, base + half, steps, COL_VISION_EDGE, 1.0)
		draw_line(Vector2.ZERO, Vector2.from_angle(base - half) * enemy.vision_range, COL_VISION_EDGE, 1.0)
		draw_line(Vector2.ZERO, Vector2.from_angle(base + half) * enemy.vision_range, COL_VISION_EDGE, 1.0)

	# --- Радиус атаки (в клетках) и радиус тревоги ---
	var cell := enemy.cell_size_px().x
	draw_arc(Vector2.ZERO, (enemy.attack_range_cells() + 0.5) * cell, 0, TAU, 32, COL_ATTACK, 1.5)
	draw_arc(Vector2.ZERO, enemy.alert_broadcast_radius, 0, TAU, 48, COL_ALERT, 1.0)

	# --- Направление взгляда ---
	var tip := facing * 20.0
	draw_line(Vector2.ZERO, tip, COL_FACING, 2.0)
	draw_line(tip, tip + facing.rotated(2.6) * 6.0, COL_FACING, 2.0)
	draw_line(tip, tip + facing.rotated(-2.6) * 6.0, COL_FACING, 2.0)

	# --- Линия до цели ---
	if see and enemy.target and is_instance_valid(enemy.target):
		draw_line(Vector2.ZERO, to_local(enemy.target.global_position), COL_TARGET, 1.0)

	# --- Last known pos + направление ---
	if enemy.last_known_pos != Vector2.ZERO:
		var lkp := to_local(enemy.last_known_pos)
		draw_circle(lkp, 3.0, COL_LKP)
		draw_line(lkp, lkp + enemy.last_known_dir * 16.0, COL_LKP, 1.0)

	# --- Последний A*-путь ---
	var path := enemy._debug_path
	for i in range(path.size()):
		var p := to_local(path[i])
		draw_circle(p, 2.0, COL_PATH)
		if i > 0:
			draw_line(to_local(path[i - 1]), p, COL_PATH, 1.0)

	# --- Стейт + очки действий ---
	draw_string(ThemeDB.fallback_font, Vector2(-30, -24),
		"%s  ОД:%d" % [enemy.state_name(), enemy.action_points],
		HORIZONTAL_ALIGNMENT_CENTER, 60, 10, Color.WHITE)
