class_name PlayerAttack
extends Node
## Боевой модуль игрока. Дочерний узел Player.
## Больше НЕ ловит мышь сам: цель выбирает Player (умный клик)
## и вызывает attack(target). Здесь — расчёт урона (оружие, бонусы, крит)
## и трата ОД.

var player : Player
var last_attack_flash := 0.0   # для дебаг-отрисовки

func _ready() -> void:
	player = get_parent() as Player

func _process(delta: float) -> void:
	last_attack_flash = maxf(last_attack_flash - delta, 0.0)

## ═══════════ ПАРАМЕТРЫ ═══════════

func weapon() -> ItemWeapon:
	if player == null:
		return null
	return player.current_weapon()

func is_ranged() -> bool:
	var w := weapon()
	return w != null and w.weapon_range == GameEnums.WeaponRange.RANGED

func aim_dir() -> Vector2:
	if player == null: return Vector2.RIGHT
	var d := player.get_global_mouse_position() - player.global_position
	return d.normalized() if d.length_squared() > 1.0 else Vector2.RIGHT

## ═══════════ АТАКА ═══════════

## Атаковать конкретную цель. Тратит ОД. Проверки дистанции/линии — на вызывающем.
func attack(t: Node2D) -> bool:
	if player == null or not player.is_alive():
		return false
	if t == null or not is_instance_valid(t):
		return false
	if not t.has_method("take_damage"):
		return false
	if not player.spend_attack():
		return false

	last_attack_flash = 0.25
	t.take_damage(_damage_table(), player)
	return true

func _damage_table() -> Dictionary:
	var table: Dictionary = {}
	var current := weapon()

	if current != null and not current.damage_table.is_empty():
		for damage_type in current.damage_table:
			table[int(damage_type)] = float(current.damage_table[damage_type])
	else:
		table[GameEnums.DamageTypes.BLUNT] = player.unarmed_damage

	if player.equipment:
		table = player.equipment.modify_damage_table(table)

	var chance := 0.0
	var multiplier := 1.5

	if player.equipment:
		var crit := player.equipment.crit_params()
		chance = crit.x
		multiplier = maxf(crit.y, 1.0)
	elif current:
		chance = current.crit_chance
		multiplier = maxf(current.crit_multiplier, 1.0)

	if chance > 0.0 and randf() * 100.0 < chance:
		for damage_type in table:
			table[damage_type] = float(table[damage_type]) * multiplier

	return table
