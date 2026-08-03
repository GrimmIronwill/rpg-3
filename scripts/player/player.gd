@tool
class_name Player
extends Character
## Пошаговое управление:
## WASD/стрелки — шаг на клетку, УДЕРЖАНИЕ = непрерывное движение,
## зажатие двух клавиш = шаг по диагонали.
## ЛКМ — УМНЫЙ клик по клетке:
##   враг         -> атаковать (или подойти на дистанцию атаки и атаковать);
##   интерактив   -> открыть, стоя вплотную (или подойти и открыть);
##   разрушаемое  -> атаковать (или подойти);
##   пустая клетка -> идти туда по A*, пока хватает ОД.
## Space/Enter — закончить ход, E — взаимодействие, F3 — дебаг.

## Грейс на первый шаг: успеть зажать вторую клавишу для диагонали.
const KB_FIRST_STEP_DELAY := 0.06

@export var equipment : PlayerEquipment
@export var attack_node : PlayerAttack

@export var debug_draw : bool = false:
	set(value):
		debug_draw = value
		_update_debug_draw()

var _debug_node : PlayerDebugDraw
var _path_preview : PlayerPathPreview
var _turn_active := false
## Выполняется серия действий по клику (движение/атака/взаимодействие)
var _busy := false
## Текущий исполняемый путь (для отрисовки кругляшков)
var _planned_path : PackedVector2Array = PackedVector2Array()
## Сколько уже удерживаются клавиши движения
var _kb_hold := 0.0

func _ready() -> void:
	super()
	if Engine.is_editor_hint(): return
	add_to_group("player")
	died.connect(_on_died)
	if equipment == null:
		for c in get_children():
			if c is PlayerEquipment:
				equipment = c
				break
	if attack_node == null:
		for c in get_children():
			if c is PlayerAttack:
				attack_node = c
				break
	# Кругляшки пути — ВСЕГДА, не только в дебаге.
	_path_preview = PlayerPathPreview.new()
	_path_preview.player = self
	add_child(_path_preview)
	_update_debug_draw()

func _on_died(_attacker: Node2D) -> void:
	_planned_path = PackedVector2Array()
	if _turn_active:
		end_turn()

## ═══════════ ХОД ИГРОКА ═══════════

func take_turn() -> void:
	if not is_alive():
		return
	start_turn()
	_turn_active = true
	await turn_finished
	_turn_active = false

func is_my_turn() -> bool:
	return _turn_active

func is_busy() -> bool:
	return _busy

func get_planned_path() -> PackedVector2Array:
	return _planned_path

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if not _turn_active or _busy or is_moving(): return

	# ОД закончились — ход завершается сам.
	if action_points <= 0:
		_finish_turn()
		return

	# FIX: движение по УДЕРЖАНИЮ клавиш (раньше — только just_pressed,
	# приходилось жать заново на каждый шаг). Троттлинг даёт анимация шага.
	var dir := _dir_input()
	if dir == Vector2i.ZERO:
		_kb_hold = 0.0
		return
	_kb_hold += delta
	if _kb_hold < KB_FIRST_STEP_DELAY:
		return   # маленький грейс, чтобы поймать диагональ
	step(dir)   # facing = направление шага; ОД тратит step()

func _finish_turn() -> void:
	if _turn_active:
		end_turn()

## Направление с клавиатуры (по удержанию). Две перпендикулярные
## клавиши = диагональ (оси суммируются).
func _dir_input() -> Vector2i:
	var pre := "move_" if InputMap.has_action("move_left") else "ui_"
	var d := Vector2i.ZERO
	d.x = int(Input.is_action_pressed(pre + "right")) - int(Input.is_action_pressed(pre + "left"))
	d.y = int(Input.is_action_pressed(pre + "down")) - int(Input.is_action_pressed(pre + "up"))
	return d

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return

	# F3 — общий дебаг
	if event is InputEventKey and event.pressed and not event.echo \
	and event.keycode == KEY_F3:
		debug_draw = not debug_draw
		for e in get_tree().get_nodes_in_group("enemies"):
			if e is Enemy:
				e.debug_draw = debug_draw
		get_viewport().set_input_as_handled()
		return

	if not _turn_active or _busy or is_moving():
		return

	# Space/Enter — закончить ход
	if event is InputEventKey and event.pressed and not event.echo:
		var key : Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if key == KEY_SPACE or key == KEY_ENTER:
			_finish_turn()
			get_viewport().set_input_as_handled()
			return

	# ЛКМ — умный клик по клетке
	if event is InputEventMouseButton and event.pressed \
	and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(get_global_mouse_position())
		get_viewport().set_input_as_handled()

## ═══════════ УМНЫЙ КЛИК ═══════════

func _handle_click(world_pos: Vector2) -> void:
	if _busy or not _turn_active or not is_alive():
		return
	_busy = true

	var mcell := world_to_cell(world_pos)
	var enemy := _actor_in_group_at(&"enemies", mcell)
	var inter := _interactable_at(mcell)
	var destr := _actor_in_group_at(&"destructibles", mcell)

	if enemy != null:
		await _attack_or_approach(enemy)
	elif inter != null:
		await _interact_or_approach(inter)
	elif destr != null:
		await _attack_or_approach(destr)
	elif mcell != grid_pos:
		await _walk_to(mcell)

	_planned_path = PackedVector2Array()
	_busy = false

## Живой объект группы в клетке (или null).
func _actor_in_group_at(group: StringName, cell: Vector2i) -> Node2D:
	for n in get_tree().get_nodes_in_group(group):
		if not (n is Node2D): continue
		if n == self: continue
		if n.has_method("is_alive") and not n.is_alive(): continue
		if world_to_cell(n.global_position) == cell:
			return n
	return null

## Интерактивный объект в клетке (без проверки дистанции — подойдём сами).
func _interactable_at(cell: Vector2i) -> Node2D:
	for n in get_tree().get_nodes_in_group("interactables"):
		if not (n is Node2D): continue
		if not n.has_method("interact"): continue
		if n.has_method("is_alive") and not n.is_alive(): continue
		if world_to_cell(n.global_position) == cell:
			return n
	return null

## Атаковать цель; если далеко — идти к ней, пока хватает ОД. Одна атака за клик.
func _attack_or_approach(t: Node2D) -> void:
	var guard := 64
	while _turn_active and is_alive() and action_points > 0 and guard > 0:
		guard -= 1
		if t == null or not is_instance_valid(t): return
		if t.has_method("is_alive") and not t.is_alive(): return

		var tcell := world_to_cell(t.global_position)
		if chebyshev(grid_pos, tcell) <= attack_range_cells() and line_clear_to_cell(tcell):
			if not can_act(&"attack"):
				return   # на удар (attack_speed ОД) не хватает
			if attack_node:
				attack_node.attack(t)
			elif spend(&"attack"):
				attack_target(t)
			return   # одна атака за клик — дальше решает игрок

		if not await _step_towards_world(t.global_position):
			return   # пройти нельзя / не хватило ОД

## Открыть объект, стоя ВПЛОТНУЮ (соседняя клетка, вкл. диагональ);
## если далеко — подойти и открыть.
func _interact_or_approach(obj: Node2D) -> void:
	var guard := 64
	while _turn_active and is_alive() and action_points > 0 and guard > 0:
		guard -= 1
		if obj == null or not is_instance_valid(obj): return
		if obj.has_method("is_alive") and not obj.is_alive(): return

		var tcell := world_to_cell(obj.global_position)
		if chebyshev(grid_pos, tcell) <= 1:
			if not can_act(&"interact"):
				return
			if obj.has_method("can_interact") and not obj.can_interact(self):
				return
			if spend(&"interact"):
				obj.interact(self)
			return

		if not await _step_towards_world(obj.global_position):
			return

## Идти в клетку по A*, пока хватает ОД.
func _walk_to(cell: Vector2i) -> void:
	var guard := 256
	while _turn_active and is_alive() and action_points > 0 \
	and grid_pos != cell and guard > 0:
		guard -= 1
		if not await _step_towards_world(cell_to_world(cell)):
			return

## Один шаг по A*-пути к мировой точке. false = дальше идти нельзя.
func _step_towards_world(world_pos: Vector2) -> bool:
	var next := grid_pos
	var n := nav()
	if n and n.is_initialized():
		var path : PackedVector2Array = n.get_path_world(global_position, world_pos)
		_planned_path = path
		if path.size() >= 2:
			next = n.world_to_cell(path[1])
	else:
		var tc := world_to_cell(world_pos)
		next = grid_pos + Vector2i(signi(tc.x - grid_pos.x), signi(tc.y - grid_pos.y))

	var dir := next - grid_pos
	if dir == Vector2i.ZERO:
		return false
	return await step(dir)

## Резисты брони с куклы вливаются в общий расчёт урона Character.
func extra_resistances() -> Dictionary:
	return equipment.total_resistances() if equipment else {}

func _update_debug_draw() -> void:
	if Engine.is_editor_hint() or not is_inside_tree(): return
	if debug_draw and _debug_node == null:
		_debug_node = PlayerDebugDraw.new()
		_debug_node.player = self
		add_child(_debug_node)
	elif not debug_draw and _debug_node:
		_debug_node.queue_free()
		_debug_node = null
