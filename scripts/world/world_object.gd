@tool
class_name WorldObject
extends Node2D
## Разрушаемый статичный объект мира (сундук, бочка, ящик и т.п.).
## Коллизий НЕТ: блокирует движение и линию атаки через ячейку A* (NavManager).
## Урон считает общий DamageSystem.

signal health_changed(current: float, max_value: float)
signal destroyed(attacker: Node2D)

@export_group("Здоровье / броня")
@export var max_health : float = 30.0
@export var phys_armor : float = 0.0
@export var magic_armor : float = 0.0
## X = флат-броня против типа, Y = % резиста (как у CharacterStats)
@export var resistances : Dictionary[GameEnums.DamageTypes, Vector2] = {}

@export_group("Настройки параметров")
## Визуальный радиус (разлёт лута), НЕ коллизия.
@export var collision_radius : float = 14.0

@export var sprite : Texture2D = preload("res://sprites/characters/debug.png"):
	set(v):
		sprite = v
		if sprite_node:
			sprite_node.texture = v

## Помечать ячейку под объектом непроходимой для A* (и снимать при разрушении)
@export var block_navigation : bool = true

var sprite_node : Sprite2D
var _hp : float

func _ready() -> void:
	_setup_sprite()
	if Engine.is_editor_hint(): return
	_hp = max_health
	add_to_group("destructibles")   # по этой группе PlayerAttack находит цели
	if block_navigation:
		_set_nav_solid.call_deferred(true)   # ждём инициализации NavManager
	_snap_to_grid.call_deferred()

## Привязка к центру клетки, чтобы попадать под клеточное прицеливание.
func _snap_to_grid() -> void:
	var nav := get_node_or_null("/root/NavManager")
	if nav and nav.is_initialized():
		global_position = nav.cell_to_world(nav.world_to_cell(global_position))

## ═══════════ УРОН / РАЗРУШЕНИЕ ═══════════

## Совместим с Character.take_damage: Dictionary[DamageTypes, float] или float.
func take_damage(damage, attacker: Node2D = null) -> float:
	if not is_alive():
		return 0.0
	var table : Dictionary
	if damage is Dictionary:
		table = damage
	else:
		table = { GameEnums.DamageTypes.BLUNT: float(damage) }

	var res := {}
	for t in resistances:
		res[t] = resistances[t]

	var final := DamageSystem.calculate(table, phys_armor, magic_armor, res)
	if final <= 0.0:
		return 0.0
	_hp = maxf(_hp - final, 0.0)
	health_changed.emit(_hp, max_health)
	if _hp <= 0.0:
		_die(attacker)
	return final

func is_alive() -> bool:
	return _hp > 0.0

func current_health() -> float:
	return _hp

func _die(attacker: Node2D) -> void:
	if block_navigation:
		_set_nav_solid(false)   # освобождаем ячейку A*
	destroyed.emit(attacker)
	_on_destroyed(attacker)
	queue_free()

## Виртуальный хук для наследников (Chest высыпает лут).
func _on_destroyed(_attacker: Node2D) -> void:
	pass

func _set_nav_solid(solid: bool) -> void:
	var nav := get_node_or_null("/root/NavManager")
	if nav:
		nav.set_solid_world(global_position, solid)

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
