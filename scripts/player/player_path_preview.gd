class_name PlayerPathPreview
extends Node2D
## Кругляшки по центрам клеток пути игрока. Рисуются ВСЕГДА (не дебаг).
## Наведение мышью -> предпросмотр пути до клетки под курсором.
## Во время исполнения клика -> оставшийся путь.
## Яркие точки — шаги, на которые хватает ОД в этот ход, тусклые — дальше.

var player : Player

const DOT_R := 3.5
const COL_OK   := Color(1.0, 1.0, 1.0, 0.85)
const COL_FAR  := Color(1.0, 1.0, 1.0, 0.30)
const COL_GOAL := Color(1.0, 0.8, 0.2, 0.95)

func _ready() -> void:
	z_index = 90

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if player == null or not is_instance_valid(player) or not player.is_alive():
		return

	var path := _current_path()
	if path.size() < 2:
		return

	var ap : int = player.action_points
	var cum := 0
	for i in range(1, path.size()):
		var cell : Vector2i = player.world_to_cell(path[i])
		cum += player.move_cost_to(cell)
		var col := COL_OK if (ap > 0 and cum <= ap) else COL_FAR
		var p := to_local(path[i])
		draw_circle(p, DOT_R, col)
		if i == path.size() - 1:
			draw_arc(p, DOT_R + 3.5, 0.0, TAU, 20, COL_GOAL, 1.5)

func _current_path() -> PackedVector2Array:
	# Исполняем клик — показываем оставшийся путь.
	if player.is_busy() or player.is_moving():
		return player.get_planned_path()
	return _hover_path()

func _hover_path() -> PackedVector2Array:
	var n := player.nav()
	if n == null or not n.is_initialized():
		return PackedVector2Array()
	var mouse := player.get_global_mouse_position()
	if player.world_to_cell(mouse) == player.grid_pos:
		return PackedVector2Array()
	return n.get_path_world(player.global_position, mouse)
