@tool
extends Node2D
class_name Character
## Персонаж в пошаговом режиме. Коллизий НЕТ:
## позиция = клетка сетки (grid_pos), движение — по карте NavManager.
## Движение возможно в 8 направлениях (включая диагонали).

signal health_changed(current: float, max_value: float)
signal died(attacker: Node2D)
signal turn_started
signal turn_finished
signal action_points_changed(current: int, max_value: int)

## ═══════════ ХОДОВАЯ СИСТЕМА ═══════════

## Очков действий на ход
const ACTIONS_PER_TURN := 3

## СТОИМОСТЬ ВСЕХ ДЕЙСТВИЙ (в очках действий)
## ВАЖНО: "attack" — БАЗОВАЯ стоимость (без оружия / кулаки).
## С оружием стоимость атаки = weapon.attack_speed (ОД), см. action_cost().
const ACTION_COST := {
	&"move": 1,       # шаг на 1 клетку (в т.ч. по диагонали)
	&"attack": 1,     # удар/выстрел БЕЗ оружия
	&"interact": 1,   # открыть сундук и т.п.
	&"use_item": 1,   # использовать предмет
	&"skip": 0,       # пропуск
}

## Доп. стоимость шага по сложному террейну
const TERRAIN_EXTRA_MOVE_COST := {
	WorldBuilder.TerrainType.WATER: 1,
	WorldBuilder.TerrainType.DEEP_WATER: 2,
	WorldBuilder.TerrainType.MUD: 1,
}

const MOVE_ANIM_TIME := 0.15
const FALLBACK_CELL := Vector2i(32, 32)

## ═══════════ ЭКСПОРТЫ ═══════════

@export_group("Статы из БД")
@export var Stats : CharacterStats

@export_group("Броня")
@export var phys_armor : float = 0.0
@export var magic_armor : float = 0.0
@export var fallback_health : float = 50.0

@export_group("Бой")
## Урон без оружия (дробящий)
@export var unarmed_damage : float = 5.0

@export_group("Оружие")
@export var base_weapons : Array[ItemWeapon]
@export var equipped_weapons : Array[ItemWeapon]

@export_group("Настройки параметров")
## Визуальный радиус (разлёт лута и т.п.), НЕ коллизия.
@export var collision_radius : float = 16.0

@export var sprite : Texture2D = preload("res://sprites/characters/debug.png"):
	set(v):
		sprite = v
		if sprite_node:
			sprite_node.texture = v
var sprite_node : Sprite2D

## ═══════════ РАНТАЙМ ═══════════

## Позиция на сетке
var grid_pos : Vector2i = Vector2i.ZERO
## Куда смотрит (= направление последнего шага)
var facing := Vector2.RIGHT
## Текущие очки действий (вне своего хода = 0)
var action_points : int = 0

## Мгновенный ход: без твинов и анимаций (для фоновых ИИ, ставит TurnManager)
var instant_turn : bool = false

## Бонусы экипировки (задаёт PlayerEquipment)
var bonus_max_health : float = 0.0
var bonus_speed_flat : float = 0.0
var bonus_speed_percent : float = 0.0

var _moving := false
var _nav : Node
var _hp : float  # если Stats == null

## ═══════════ ЖИЗНЕННЫЙ ЦИКЛ ═══════════

func _ready() -> void:
	_setup_sprite()
	if Engine.is_editor_hint(): return
	_setup_stats()
	sync_to_grid.call_deferred()

func _setup_stats() -> void:
	if Stats:
		Stats = Stats.duplicate(true)
		# FIX: в БД health может быть (0,0) — иначе персонаж "мёртв" с рождения
		# и урон по нему "не засчитывается" (клик по врагу шёл как ходьба).
		if Stats.health.y <= 0.0:
			Stats.health.y = fallback_health
		if Stats.health.x <= 0.0:
			Stats.health.x = Stats.health.y
	else:
		_hp = fallback_health

## ═══════════ ХОД ═══════════

func start_turn() -> void:
	action_points = ACTIONS_PER_TURN
	action_points_changed.emit(action_points, ACTIONS_PER_TURN)
	turn_started.emit()

func end_turn() -> void:
	action_points = 0
	action_points_changed.emit(action_points, ACTIONS_PER_TURN)

	if is_alive():
		_apply_turn_regeneration()

	turn_finished.emit()

func _apply_turn_regeneration() -> void:
	if Stats == null:
		return

	var health_amount := maxf(
		Stats.health_regen.x + max_health() * Stats.health_regen.y / 100.0,
		0.0
	)
	if health_amount > 0.0 and Stats.health.x < max_health():
		heal(health_amount)

	var stamina_max := maxf(Stats.stamina.y, 0.0)
	var stamina_amount := maxf(
		Stats.stamina_regen.x + stamina_max * Stats.stamina_regen.y / 100.0,
		0.0
	)
	if stamina_amount > 0.0 and Stats.stamina.x < stamina_max:
		Stats.stamina.x = minf(Stats.stamina.x + stamina_amount, stamina_max)

	var mana_max := maxf(Stats.mana.y, 0.0)
	var mana_amount := maxf(
		Stats.mana_regen.x + mana_max * Stats.mana_regen.y / 100.0,
		0.0
	)
	if mana_amount > 0.0 and Stats.mana.x < mana_max:
		Stats.mana.x = minf(Stats.mana.x + mana_amount, mana_max)

## Переопределяется наследниками (Player ждёт ввод, Enemy думает сам).
func take_turn() -> void:
	start_turn()
	await get_tree().process_frame
	end_turn()

## Стоимость действия в ОД.
## Атака: attack_speed оружия (ИНТ, = сколько ОД жрёт удар), иначе базовая.
func action_cost(action: StringName) -> int:
	if action == &"attack":
		var base_cost := int(ACTION_COST.get(&"attack", 1))
		var w := current_weapon()

		if w and w.attack_speed > 0:
			base_cost = w.attack_speed

		var speed_multiplier := maxf(
			1.0 - attack_speed_bonus_percent() / 100.0,
			0.0
		)
		return maxi(ceili(float(base_cost) * speed_multiplier), 1)

	return int(ACTION_COST.get(action, 1))

func attack_speed_bonus_percent() -> float:
	var w := current_weapon()
	return w.bonus_attack_speed if w else 0.0

func attack_stamina_cost_modifier() -> float:
	return 0.0


func attack_mana_cost_modifier() -> float:
	return 0.0


func attack_stamina_cost() -> float:
	var weapon := current_weapon()

	if weapon == null:
		return 0.0

	return maxf(
		weapon.stamina_cost + attack_stamina_cost_modifier(),
		0.0
	)


func attack_mana_cost() -> float:
	var weapon := current_weapon()

	if weapon == null:
		return 0.0

	return maxf(
		weapon.mana_cost + attack_mana_cost_modifier(),
		0.0
	)

func can_attack() -> bool:
	if not can_act(&"attack"):
		return false

	if Stats == null:
		return true

	if Stats.stamina.x < attack_stamina_cost():
		return false

	if Stats.mana.x < attack_mana_cost():
		return false

	return true

func spend_attack() -> bool:
	if not can_attack():
		return false

	if not spend(&"attack"):
		return false

	if Stats:
		Stats.stamina.x = maxf(
			Stats.stamina.x - attack_stamina_cost(),
			0.0
		)

		Stats.mana.x = maxf(
			Stats.mana.x - attack_mana_cost(),
			0.0
		)

	return true

func can_act(action: StringName) -> bool:
	return action_points >= action_cost(action)

func spend(action: StringName, extra := 0) -> bool:
	var cost := action_cost(action) + extra
	if action_points < cost:
		return false
	action_points -= cost
	action_points_changed.emit(action_points, ACTIONS_PER_TURN)
	return true

func is_my_turn() -> bool:
	var tm := get_node_or_null("/root/TurnManager")
	return tm != null and tm.current_actor == self

## ═══════════ ДВИЖЕНИЕ ПО СЕТКЕ ═══════════

func is_moving() -> bool:
	return _moving

## Шаг на соседнюю клетку (8 направлений). Тратит ОД, ставит facing. true = успех.
func step(dir: Vector2i) -> bool:
	if _moving or dir == Vector2i.ZERO:
		return false
	dir.x = clampi(dir.x, -1, 1)
	dir.y = clampi(dir.y, -1, 1)
	var target := grid_pos + dir
	if not is_cell_free(target):
		return false
	# Диагональ: нельзя "срезать угол", если обе смежные ортогональные
	# клетки заняты/непроходимы (как AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE).
	if dir.x != 0 and dir.y != 0:
		if not is_cell_free(grid_pos + Vector2i(dir.x, 0)) \
		and not is_cell_free(grid_pos + Vector2i(0, dir.y)):
			return false
	var cost := move_cost_to(target)
	if action_points < cost:
		return false
	action_points -= cost
	action_points_changed.emit(action_points, ACTIONS_PER_TURN)

	grid_pos = target
	facing = Vector2(dir).normalized()   # смотрим туда, куда пошли

	# Мгновенный режим (фоновый ИИ): телепорт без твина, ноль кадров ожидания.
	if instant_turn:
		global_position = cell_to_world(target)
		return true

	_moving = true
	var tw := create_tween()
	tw.tween_property(self, "global_position", cell_to_world(target), MOVE_ANIM_TIME)
	await tw.finished
	_moving = false
	return true

## Стоимость шага в клетку (базовая + террейн)
func move_cost_to(cell: Vector2i) -> int:
	var cost := int(ACTION_COST.get(&"move", 1))
	var n := nav()
	if n and n.is_initialized():
		cost += int(TERRAIN_EXTRA_MOVE_COST.get(n.get_terrain_world(cell_to_world(cell)), 0))
	return cost

## Клетка проходима по карте и не занята другим персонажем.
func is_cell_free(cell: Vector2i) -> bool:
	var n := nav()
	if n and n.is_initialized():
		if not n.is_walkable_world(n.cell_to_world(cell)):
			return false
	var tm := get_node_or_null("/root/TurnManager")
	if tm and tm.is_cell_occupied(cell, self):
		return false
	return true

## Привязка к центру клетки (после генерации мира).
func sync_to_grid() -> void:
	grid_pos = world_to_cell(global_position)
	global_position = cell_to_world(grid_pos)

## ═══════════ СЕТКА / НАВИГАЦИЯ ═══════════

func nav() -> Node:
	if _nav == null or not is_instance_valid(_nav):
		_nav = get_node_or_null("/root/NavManager")
	return _nav

func world_to_cell(p: Vector2) -> Vector2i:
	var n := nav()
	if n and n.is_initialized():
		return n.world_to_cell(p)
	return Vector2i(floori(p.x / FALLBACK_CELL.x), floori(p.y / FALLBACK_CELL.y))

func cell_to_world(c: Vector2i) -> Vector2:
	var n := nav()
	if n and n.is_initialized():
		return n.cell_to_world(c)
	return Vector2(c * FALLBACK_CELL) + Vector2(FALLBACK_CELL) * 0.5

func cell_size_px() -> Vector2:
	var n := nav()
	if n and n.is_initialized():
		return Vector2(n.cell_size)
	return Vector2(FALLBACK_CELL)

## Линия обзора/выстрела свободна (по клеткам карты, без физики).
func line_clear_to_cell(to_cell: Vector2i) -> bool:
	var n := nav()
	if n == null or not n.is_initialized():
		return true
	var cells := bresenham(grid_pos, to_cell)
	for i in range(1, cells.size() - 1):   # концы не проверяем
		if not n.is_walkable_world(n.cell_to_world(cells[i])):
			return false
	return true

static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

static func bresenham(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var pts : Array[Vector2i] = []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var c := a
	while true:
		pts.append(c)
		if c == b: break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			c.x += sx
		if e2 <= dx:
			err += dx
			c.y += sy
	return pts

## ═══════════ ОРУЖИЕ / БОЙ ═══════════

func current_weapon() -> ItemWeapon:
	for w in equipped_weapons:
		if w: return w
	for w in base_weapons:
		if w: return w
	return null

## Дальность атаки в КЛЕТКАХ (ИНТ). melee_range / ranged_distance
## в БД теперь заданы В КЛЕТКАХ. Без оружия — 1 клетка.
func attack_range_cells() -> int:
	var w := current_weapon()
	if w:
		if w.weapon_range == GameEnums.WeaponRange.RANGED and w.ranged_distance > 0:
			return maxi(w.ranged_distance, 1)
		if w.melee_range > 0:
			return maxi(w.melee_range, 1)
	return 1

## Стоимость атаки в ОД (= attack_speed оружия).
func attack_cost() -> int:
	return action_cost(&"attack")

## Нанести урон цели актуальным оружием (ОД тратит вызывающий).
func attack_target(t: Node2D) -> void:
	if t == null or not t.has_method("take_damage"):
		return
	var w := current_weapon()
	if w and not w.damage_table.is_empty():
		t.take_damage(w.damage_table, self)
	else:
		t.take_damage({ GameEnums.DamageTypes.BLUNT: unarmed_damage }, self)

## Принимает Dictionary[DamageTypes, float] ИЛИ float.
func take_damage(damage, attacker: Node2D = null) -> float:
	var table : Dictionary
	if damage is Dictionary:
		table = damage
	else:
		table = { GameEnums.DamageTypes.BLUNT: float(damage) }

	var final := DamageSystem.calculate(table, phys_armor, magic_armor, total_resistances())
	_apply_health_loss(final, attacker)
	return final

func _apply_health_loss(amount: float, attacker: Node2D) -> void:
	if amount <= 0.0: return
	if Stats:
		Stats.health.x = maxf(Stats.health.x - amount, 0.0)
		health_changed.emit(Stats.health.x, max_health())
		if Stats.health.x <= 0.0:
			died.emit(attacker)
	else:
		_hp = maxf(_hp - amount, 0.0)
		health_changed.emit(_hp, max_health())
		if _hp <= 0.0:
			died.emit(attacker)

func heal(amount: float) -> void:
	if amount <= 0.0: return
	if Stats:
		Stats.health.x = minf(Stats.health.x + amount, max_health())
		health_changed.emit(Stats.health.x, max_health())
	else:
		_hp = minf(_hp + amount, max_health())
		health_changed.emit(_hp, max_health())

func max_health() -> float:
	return (Stats.health.y if Stats else fallback_health) + bonus_max_health

func current_health() -> float:
	return Stats.health.x if Stats else _hp

func set_bonus_max_health(v: float) -> void:
	bonus_max_health = v
	if Stats:
		Stats.health.x = minf(Stats.health.x, max_health())
		health_changed.emit(Stats.health.x, max_health())
	else:
		_hp = minf(_hp, max_health())
		health_changed.emit(_hp, max_health())

func is_alive() -> bool:
	return (Stats.health.x if Stats else _hp) > 0.0

func total_resistances() -> Dictionary:
	var res := {}
	if Stats:
		for t in Stats.resistances:
			res[t] = Stats.resistances[t]
	for w in equipped_weapons:
		if w == null: continue
		for t in w.resistances:
			res[t] = res.get(t, Vector2.ZERO) + w.resistances[t]
	var extra := extra_resistances()
	for t in extra:
		res[t] = res.get(t, Vector2.ZERO) + extra[t]
	return res

## Виртуальный хук: Player возвращает резисты брони с куклы.
func extra_resistances() -> Dictionary:
	return {}

## ═══════════ АВТОСБОРКА СПРАЙТА ═══════════

func _setup_sprite() -> void:
	for child in get_children():
		if child is Sprite2D:
			sprite_node = child
			return
	sprite_node = Sprite2D.new()
	sprite_node.name = "Sprite"
	sprite_node.texture = sprite
	add_child(sprite_node)
	sprite_node.owner = get_tree().edited_scene_root
