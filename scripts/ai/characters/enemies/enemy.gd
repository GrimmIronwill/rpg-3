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

	# Состояние фиксируется после первичного восприятия.
	# Если враг сменит состояние посреди хода, счётчик нового состояния
	# начнёт уменьшаться только со следующего хода.
	var state_at_turn_start := state

	var guard := 12
	while is_alive() and action_points > 0 and guard > 0:
		guard -= 1

		var acted: bool = await _take_action()
		if not acted:
			break

		_perceive()

		if not instant_turn and is_inside_tree():
			await get_tree().create_timer(ACT_DELAY).timeout

	_tick_state(state_at_turn_start)
	end_turn()

## Счётчики состояний тикают один раз за ход.
func _tick_state(state_at_turn_start: AIState) -> void:
	# Не уменьшаем таймер состояния, в которое враг вошёл посреди хода.
	if state != state_at_turn_start:
		return

	match state:
		AIState.AGGRO:
			if _can_see:
				_memory = maxi(memory_turns, 1)
			else:
				_memory = maxi(_memory - 1, 0)
				if _memory <= 0:
					_enter_search()

		AIState.SEARCH:
			_search_left = maxi(_search_left - 1, 0)
			if _search_left <= 0:
				_enter_idle()

		AIState.ALERT:
			_alert_left = maxi(_alert_left - 1, 0)
			if _alert_left <= 0:
				last_known_pos = alert_pos
				last_known_dir = Vector2.ZERO
				_enter_search()

func _enter_idle() -> void:
	state = AIState.IDLE
	target = null
	_can_see = false
	_memory = 0
	_search_left = 0
	_alert_left = 0
	_search_pos = Vector2.ZERO
	_debug_path = PackedVector2Array()

func _enter_aggro(
	new_target: Node2D,
	known_pos: Vector2,
	known_dir: Vector2 = Vector2.ZERO
) -> void:
	if new_target == null or not is_instance_valid(new_target):
		return

	state = AIState.AGGRO
	target = new_target
	last_known_pos = known_pos
	last_known_dir = known_dir.normalized() \
		if known_dir.length_squared() > 0.001 \
		else Vector2.ZERO

	_memory = maxi(memory_turns, 1)
	_search_left = 0
	_alert_left = 0
	_search_pos = Vector2.ZERO

func _enter_search() -> void:
	state = AIState.SEARCH
	_search_left = maxi(search_turns, 1)
	_alert_left = 0
	_can_see = false

	var origin := last_known_pos
	if origin == Vector2.ZERO:
		origin = global_position
		last_known_pos = origin

	var guess := origin + last_known_dir * overshoot
	var n := nav()

	if n and n.is_initialized() and not n.is_walkable_world(guess):
		guess = origin

	_search_pos = guess

## Одно действие. false = делать больше нечего (ход завершается).
func _take_action() -> bool:
	match state:
		AIState.AGGRO:
			return await _act_aggro()

		AIState.SEARCH:
			return await _act_search()

		AIState.ALERT:
			return await _act_alert()

		_:
			return await _act_idle()

func _act_aggro() -> bool:
	if not _target_is_alive(target):
		var player := _get_player()

		if not _target_is_alive(player):
			_enter_idle()
			return false

		target = player

	var current_target := target
	if current_target == null:
		_enter_idle()
		return false

	if _can_see:
		last_known_pos = current_target.global_position
		last_known_dir = current_target.facing \
			if current_target is Character \
			else Vector2.ZERO

		var target_cell := world_to_cell(current_target.global_position)
		var to_target := current_target.global_position - global_position

		if to_target.length_squared() > 1.0:
			facing = to_target.normalized()

		if Character.chebyshev(grid_pos, target_cell) <= attack_range_cells() \
		and line_clear_to_cell(target_cell):
			if not spend_attack():
				return false

			attack_target(current_target)
			return true

		return await _step_towards(current_target.global_position)

	# Враг дошёл до последней известной позиции, но цель там не обнаружил.
	# Вместо мгновенного успокоения начинает полноценный поиск.
	if world_to_cell(last_known_pos) == grid_pos:
		_enter_search()
		return await _act_search()

	return await _step_towards(last_known_pos)


func _act_search() -> bool:
	if world_to_cell(_search_pos) != grid_pos:
		return await _act_goto(_search_pos)

	# Дошли до предполагаемой позиции цели — осматриваем соседние клетки,
	# а не мгновенно переходим в Idle.
	if not _pick_search_destination():
		return false

	return await _act_goto(_search_pos)


func _act_alert() -> bool:
	if world_to_cell(alert_pos) != grid_pos:
		return await _act_goto(alert_pos)

	# В точке тревоги враг не успокаивается, а начинает искать нарушителя.
	last_known_pos = alert_pos
	last_known_dir = Vector2.ZERO
	_enter_search()

	return await _act_search()


func _act_goto(pos: Vector2) -> bool:
	if world_to_cell(pos) == grid_pos:
		return false

	return await _step_towards(pos)

func _pick_search_destination() -> bool:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(-1, 1),
		Vector2i(1, -1),
		Vector2i(-1, -1),
	]
	dirs.shuffle()

	var center_cell := world_to_cell(last_known_pos)
	var cell_width := maxf(cell_size_px().x, 1.0)
	var search_radius_cells := maxi(ceili(overshoot / cell_width), 2)

	for dir in dirs:
		var candidate := grid_pos + dir

		if Character.chebyshev(center_cell, candidate) > search_radius_cells:
			continue

		if not is_cell_free(candidate):
			continue

		if action_points < move_cost_to(candidate):
			continue

		_search_pos = cell_to_world(candidate)
		return true

	return false

func _target_is_alive(candidate: Node2D) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false

	if candidate.has_method("is_alive"):
		return candidate.is_alive()

	return true

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
	var candidate := target

	if not _target_is_alive(candidate):
		candidate = _get_player()

	if not _target_is_alive(candidate):
		_can_see = false
		return

	_can_see = _check_vision(candidate)

	if not _can_see:
		return

	var direction = candidate.facing \
		if candidate is Character \
		else Vector2.ZERO

	_enter_aggro(
		candidate,
		candidate.global_position,
		direction
	)

func effective_vision_angle_deg() -> float:
	# Во время активного боя враг контролирует всё окружение.
	# Заход за спину больше не сбрасывает агрессию и видимость цели.
	if state == AIState.AGGRO:
		return 360.0

	return vision_angle_deg

func can_see_target() -> bool:
	return _can_see

func _check_vision(candidate: Node2D) -> bool:
	if not _target_is_alive(candidate):
		return false

	var to_target := candidate.global_position - global_position

	if to_target.length_squared() > vision_range * vision_range:
		return false

	var angle := effective_vision_angle_deg()

	if angle < 360.0 and to_target.length_squared() > 1.0:
		if absf(facing.angle_to(to_target)) > deg_to_rad(angle * 0.5):
			return false

	return line_clear_to_cell(world_to_cell(candidate.global_position))

func _get_player() -> Node2D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player

## ═══════════ УРОН / ТРЕВОГА ═══════════

func take_damage(damage, attacker: Node2D = null) -> float:
	var dealt := super(damage, attacker)
	damaged.emit(attacker)

	# Реакция происходит даже при полном поглощении урона бронёй:
	# сам факт направленной атаки считается обнаружением угрозы.
	if attacker and is_instance_valid(attacker):
		var attacker_dir = attacker.facing \
			if attacker is Character \
			else Vector2.ZERO

		_enter_aggro(
			attacker,
			attacker.global_position,
			attacker_dir
		)

		# _enter_aggro сначала включает круговой боевой обзор,
		# поэтому атакующий корректно обнаруживается и за спиной.
		_can_see = _check_vision(attacker)

	# Оповещаем ближайших союзников даже при смертельном ударе.
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self or not (node is Enemy):
			continue

		var ally := node as Enemy

		if global_position.distance_squared_to(ally.global_position) \
		<= alert_broadcast_radius * alert_broadcast_radius:
			ally.notify_ally_attacked(self, attacker)

	return dealt

func notify_ally_attacked(victim: Node2D, attacker: Node2D) -> void:
	if state == AIState.AGGRO:
		return

	# Если союзник лично видит атакующего, он сразу вступает в бой.
	if _target_is_alive(attacker) and _check_vision(attacker):
		var attacker_dir = attacker.facing \
			if attacker is Character \
			else Vector2.ZERO

		_can_see = true
		_enter_aggro(
			attacker,
			attacker.global_position,
			attacker_dir
		)
		return

	# Иначе идёт к месту нападения и затем начинает поиск.
	if victim == null or not is_instance_valid(victim):
		return

	state = AIState.ALERT
	target = attacker if _target_is_alive(attacker) else null
	alert_pos = victim.global_position
	last_known_pos = alert_pos
	last_known_dir = Vector2.ZERO
	_alert_left = maxi(alert_turns, 1)
	_search_left = 0
	_can_see = false

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
