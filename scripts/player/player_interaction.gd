class_name PlayerInteraction
extends Node
## Взаимодействие с объектами мира (группа "interactables"). Дочерний узел Player.
## E -> interact() у объекта в СОСЕДНЕЙ клетке (вплотную, вкл. диагональ).
## Работает только в свой ход, тратит ACTION_COST["interact"].

var player : Player

func _ready() -> void:
	player = get_parent() as Player

func _unhandled_input(event: InputEvent) -> void:
	if player == null: return
	if InputMap.has_action("interact"):
		if event.is_action_pressed("interact"):
			_try_interact()
			get_viewport().set_input_as_handled()
		return
	# Fallback: физическая клавиша E
	if event is InputEventKey and event.pressed and not event.echo:
		var key : Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if key == KEY_E:
			_try_interact()
			get_viewport().set_input_as_handled()

func _try_interact() -> void:
	if not player.is_my_turn() or player.is_moving() or player.is_busy(): return
	if not player.can_act(&"interact"): return

	var best : Node2D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("interactables"):
		if not (n is Node2D): continue
		if not n.has_method("interact"): continue
		# Только вплотную: соседняя клетка (Chebyshev <= 1).
		var tcell : Vector2i = player.world_to_cell(n.global_position)
		if Character.chebyshev(player.grid_pos, tcell) > 1: continue
		if n.has_method("can_interact") and not n.can_interact(player): continue
		var d : float = player.global_position.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	if best:
		if player.spend(&"interact"):
			best.interact(player)
