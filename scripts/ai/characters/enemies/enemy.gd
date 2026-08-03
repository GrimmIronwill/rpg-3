@tool
extends Character
class_name Enemy
## Пошаговый ИИ. На своём ходу тратит ACTIONS_PER_TURN очков:
## шаг / атака / ожидание. Смотрит туда, куда ходил в последний раз (facing).
## В режиме instant_turn (фоновый ИИ, ставит TurnManager) весь ход
## выполняется за один кадр: без пауз между действиями и без анимаций.

enum AIState { IDLE, ALERT, AGGRO, SEARCH }
const STATE_LABELS : PackedStringArray = ["Idle", "Alert", "Aggro", "Search"]

## Пауза между действиями в рамках одного хода (читаемость)
const ACT_DELAY := 0.15

@export_group("Восприятие")
@export var vision_range : float = 320.0
@export_range(10.0, 360.0) var vision_angle_deg : float = 120.0

@export_group("Память (в ходах)")
## Сколько ходов помнит цель, не видя её, прежде чем перейти в Search
@export var memory_turns : int = 3
## Сколько ходов ищет цель
@export var search_turns : int = 3
## Сколько ходов идёт на точку тревоги
@export var alert_turns : int = 3
## Насколько дальше идти по направлению движения цели при поиске (пиксели)
@export var overshoot : float = 160.0

@export_group("Поведение")
## Шанс сделать шаг в случайную сторону в Idle (за одно действие)
@export_range(0.0, 1.0) var wander_chance : float = 0.4
@export var alert_broadcast_radius : float = 250.0

@export_group("Дебаг")
@export var debug_draw : bool = false:
	set(value):
		debug_draw = value
		_update_debug_draw()

signal damaged(attacker: Node2D)

var state : AIState = AIState.IDLE
var target : Node2D
var last_known_pos := Vector2.ZERO
var last_known_dir := Vector2.ZERO
var alert_pos := Vector2.ZERO

var _can_see := false
var _memory := 0
var _search_left := 0
var _alert_left := 0
var _search_pos := Vector2.ZERO
var _player : Node2D
var _debug_node : EnemyDebugDraw
var _debug_path : PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	super()
	if Engine.is_editor_hint(): return
	add_to_group("enemies")
	died.connect(_on_died)
	_update_debug_draw()

func _on_died(_attacker: Node2D) -> void:
	remove_from_group("enemies")
	queue_free()

func state_name() -> String:
	return STATE_LABELS[state]

## ═══════════ ХОД ИИ ═══════════

func take_turn() -> void:
	if not is_alive():
		return
	start_turn()
	_perceive()
	_tick_state()

	var guard := 12   # защита от зацикливания
	while is_alive() and action_points > 0 and guard > 0:
		guard -= 1
		var acted : bool = await _take_action()
		if not acted:
			break
		_perceive()
		# Пауза для читаемости — только у АКТИВНЫХ (видимых) врагов.
		if not instant_turn and is_inside_tree():
			await get_tree().create_timer(ACT_DELAY).timeout

	end_turn()

## Счётчики состояний тикают один раз за ход.
func _tick_state() -> void:
	match state:
		AIState.AGGRO:
			if not _can_see:
				_memory -= 1
				if _memory <= 0:
					_enter_search()
		AIState.SEARCH:
			_search_left -= 1
			if _search_left <= 0:
				state = AIState.IDLE
		AIState.ALERT:
			_alert_left -= 1
			if _alert_left <= 0:
				state = AIState.IDLE

func _enter_search() -> void:
	state = AIState.SEARCH
	_search_left = search_turns
	var guess := last_known_pos + last_known_dir * overshoot
	var n := nav()
	if n and n.is_initialized() and not n.is_walkable_world(guess):
		guess = last_known_pos
	_search_pos = guess

## Одно действие. false = делать больше нечего (ход завершается).
func _take_action() -> bool:
	match state:
		AIState.AGGRO:
			return await _act_aggro()
		AIState.SEARCH:
			return await _act_goto(_search_pos)
		AIState.ALERT:
			return await _act_goto(alert_pos)
		_:
			return await _act_idle()

func _act_aggro() -> bool:
	var p := _get_player()
	if p == null or not is_instance_valid(p) or not p.is_alive():
		state = AIState.IDLE
		return false

	if _can_see:
		var pcell := world_to_cell(p.global_position)
		# В радиусе атаки и линия свободна -> бьём.
		if Character.chebyshev(grid_pos, pcell) <= attack_range_cells() \
		and line_clear_to_cell(pcell):
			if spend(&"attack"):
				attack_target(p)
				return true
			return false   # на удар не хватило ОД
		return await _step_towards(p.global_position)

	# Цель не видна: идём к последней известной точке.
	if world_to_cell(last_known_pos) == grid_pos:
		return false   # стоим, память тикает по ходам
	return await _step_towards(last_known_pos)

func _act_goto(pos: Vector2) -> bool:
	if world_to_cell(pos) == grid_pos:
		state = AIState.IDLE   # дошли
		return false
	return await _step_towards(pos)

func _act_idle() -> bool:
	if randf() >= wander_chance:
		return false
	var dirs := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	dirs.shuffle()
	for d in dirs:
		if is_cell_free(grid_pos + d) and action_points >= move_cost_to(grid_pos + d):
			return await step(d)
	return false

## Шаг по A*-пути к точке. false = пройти нельзя / не хватило ОД.
func _step_towards(world_pos: Vector2) -> bool:
	var next := grid_pos
	var n := nav()
	if n and n.is_initialized():
		var path : PackedVector2Array = n.get_path_world(global_position, world_pos)
		_debug_path = path
		if path.size() >= 2:
			next = n.world_to_cell(path[1])
	else:
		var tc := world_to_cell(world_pos)
		next = grid_pos + Vector2i(signi(tc.x - grid_pos.x), signi(tc.y - grid_pos.y))

	var dir := next - grid_pos
	if dir == Vector2i.ZERO:
		return false
	return await step(dir)   # facing выставит step()

## ═══════════ ВОСПРИЯТИЕ ═══════════

func _perceive() -> void:
	var p := _get_player()
	_can_see = _check_vision(p)
	if _can_see:
		target = p
		last_known_pos = p.global_position
		# игрок тоже смотрит туда, куда ходил — используем это как направление
		last_known_dir = p.facing if p is Character else Vector2.ZERO
		state = AIState.AGGRO
		_memory = memory_turns

func can_see_target() -> bool:
	return _can_see

func _check_vision(p: Node2D) -> bool:
	if p == null or not is_instance_valid(p):
		return false
	var to := p.global_position - global_position
	if to.length_squared() > vision_range * vision_range:
		return false
	if vision_angle_deg < 360.0 and to.length_squared() > 1.0:
		if absf(facing.angle_to(to)) > deg_to_rad(vision_angle_deg * 0.5):
			return false
	return line_clear_to_cell(world_to_cell(p.global_position))

func _get_player() -> Node2D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player

## ═══════════ УРОН / ТРЕВОГА ═══════════

func take_damage(damage, attacker: Node2D = null) -> float:
	var dealt := super(damage, attacker)
	damaged.emit(attacker)
	# Нас ударили — мы знаем, откуда.
	if attacker and is_instance_valid(attacker):
		target = attacker
		last_known_pos = attacker.global_position
		last_known_dir = Vector2.ZERO
		state = AIState.AGGRO
		_memory = memory_turns
	# Оповещаем сородичей в радиусе.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not (e is Enemy): continue
		if global_position.distance_squared_to(e.global_position) \
		<= alert_broadcast_radius * alert_broadcast_radius:
			(e as Enemy).notify_ally_attacked(self, attacker)
	return dealt

func notify_ally_attacked(victim: Node2D, _attacker: Node2D) -> void:
	if state != AIState.IDLE:
		return
	state = AIState.ALERT
	alert_pos = victim.global_position
	_alert_left = alert_turns

## ═══════════ ДЕБАГ ═══════════

func _update_debug_draw() -> void:
	if Engine.is_editor_hint() or not is_inside_tree(): return
	if debug_draw and _debug_node == null:
		_debug_node = EnemyDebugDraw.new()
		_debug_node.enemy = self
		add_child(_debug_node)
	elif not debug_draw and _debug_node:
		_debug_node.queue_free()
		_debug_node = null
