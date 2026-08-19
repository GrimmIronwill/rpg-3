class_name PlayerEquipment
extends Node
## Кукла экипировки. Дочерний узел Player (Character).
## Хранит надетые предметы по слотам EquipSlot и применяет их статы к персонажу:
## оружие → equipped_weapons, резисты → extra_resistances(), HP/скорость → бонусы Character.

signal changed

const ES = GameEnums.EquipSlot
const EC = GameEnums.EquipCategory

## Категория предмета → допустимые слоты куклы.
const SLOTS_BY_CATEGORY := {
	EC.HELMET:           [ES.HEAD_PRIMARY],
	EC.HOOD:             [ES.HEAD_SECONDARY],
	EC.MASK:             [ES.HEAD_SECONDARY],
	EC.CHEST_ARMOR:      [ES.TORSO_PRIMARY],
	EC.UNDERARMOR:       [ES.TORSO_SECONDARY],
	EC.ARM_GUARD:        [ES.ARMS],
	EC.LEG_ARMOR:        [ES.LEGS_PRIMARY],
	EC.LEG_LIGHT:        [ES.LEGS_SECONDARY],
	EC.BOOTS:            [ES.FEET],
	EC.GLOVES:           [ES.GLOVES],
	EC.CLOAK:            [ES.BACK],
	EC.BACKPACK:         [ES.BODY_SLOT_1, ES.BODY_SLOT_2],
	EC.HOLSTER:          [ES.BODY_SLOT_1, ES.BODY_SLOT_2],
	EC.QUIVER:           [ES.BODY_SLOT_1, ES.BODY_SLOT_2],
	EC.POTION_BELT:      [ES.BELT],
	EC.BELT:             [ES.BELT],
	EC.WEAPON:           [ES.HAND_1, ES.HAND_2],
	EC.SHIELD:           [ES.HAND_2],
	EC.AMULET:           [ES.AMULET],
	EC.RING:             [ES.RING_1, ES.RING_2, ES.RING_3, ES.RING_4],
	EC.CONSUMABLE_QUICK: [ES.POCKET_1, ES.POCKET_2],
}

var slots : Dictionary = {}   # int(EquipSlot) -> ItemEquipment
var character : Character

func _ready() -> void:
	character = get_parent() as Character
	_apply_all()

func current_weapon() -> ItemWeapon:
	for slot_id in [ES.HAND_1, ES.HAND_2]:
		var item = slots.get(slot_id)
		if item is ItemWeapon:
			return item as ItemWeapon
	return null

func get_item(slot: int) -> Item:
	return slots.get(slot)

## Все слоты, куда может лечь предмет.
## valid_equip_slots в БД — это КОНКРЕТНЫЕ слоты (EquipSlot).
## Если предмет их задаёт — используем их, иначе берём слоты по категории.
func allowed_slots(item: Item) -> Array:
	var eq := item as ItemEquipment
	if eq == null: return []
	var out : Array = []
	for s in eq.valid_equip_slots:
		if not out.has(int(s)): out.append(int(s))
	if out.is_empty():
		for s in SLOTS_BY_CATEGORY.get(eq.equipment_category, []):
			out.append(s)
	return out


func can_equip(item: Item) -> bool:
	if not (item is ItemEquipment): return false
	if allowed_slots(item).is_empty(): return false
	return _requirements_met(item)

func _requirements_met(item: ItemEquipment) -> bool:
	if character == null or character.Stats == null: return true
	for attr in item.requirements:
		if _attr_value(int(attr)) < int(item.requirements[attr]):
			return false
	return true

func _attr_value(attr: int) -> int:
	var s := character.Stats
	match attr:
		GameEnums.Attribute.STRENGTH: return s.strength
		GameEnums.Attribute.DEXTERITY: return s.dexterity
		GameEnums.Attribute.BODY: return s.body
		GameEnums.Attribute.INTELLIGENCE: return s.intelligence
		GameEnums.Attribute.PERCEPTION: return s.perception
	return 0

## Надеть предмет. slot = -1 → авто (первый свободный из допустимых).
## Возвращает массив СНЯТЫХ предметов (их надо вернуть в инвентарь).
func equip(item: ItemEquipment, slot: int = -1) -> Array:
	var removed : Array = []
	if item == null: return removed
	var targets := allowed_slots(item)
	if targets.is_empty(): return removed

	if slot == -1:
		slot = targets[0]
		for s in targets:
			if not slots.has(s):
				slot = s
				break
	elif not targets.has(slot):
		return removed

	var two_handed := item is ItemWeapon \
		and (item as ItemWeapon).grip == GameEnums.WeaponGrip.TWO_HANDED

	# Двуручное занимает обе руки.
	if two_handed:
		slot = ES.HAND_1
		if slots.has(ES.HAND_2):
			removed.append(unequip(ES.HAND_2, false))
	# Кладём во вторую руку, а в первой двуручное — снимаем его.
	if slot == ES.HAND_2 and _is_two_handed_in_hand1():
		removed.append(unequip(ES.HAND_1, false))

	if slots.has(slot):
		removed.append(unequip(slot, false))

	slots[slot] = item
	_apply_all()
	changed.emit()

	var out : Array = []
	for r in removed:
		if r != null: out.append(r)
	return out

## Снять предмет из слота. Возвращает предмет или null.
func unequip(slot: int, apply: bool = true) -> Item:
	if not slots.has(slot): return null
	var it : Item = slots[slot]
	slots.erase(slot)
	if apply:
		_apply_all()
		changed.emit()
	return it

func _is_two_handed_in_hand1() -> bool:
	var w = slots.get(ES.HAND_1)
	return w is ItemWeapon and (w as ItemWeapon).grip == GameEnums.WeaponGrip.TWO_HANDED

## ═══════════ ПРИМЕНЕНИЕ СТАТОВ ═══════════

func _apply_all() -> void:
	if character == null: return

	# Оружие в руках → equipped_weapons персонажа (HAND_1 приоритетнее).
	var weapons : Array[ItemWeapon] = []
	for s in [ES.HAND_1, ES.HAND_2]:
		var it = slots.get(s)
		if it is ItemWeapon:
			weapons.append(it)
	character.equipped_weapons = weapons

	# HP / скорость (Vector2: X = ед., Y = %).
	var base_hp := character.Stats.health.y if character.Stats else character.fallback_health
	var hp_flat := 0.0
	var hp_pct := 0.0
	var sp_flat := 0.0
	var sp_pct := 0.0
	for s in slots:
		var it : ItemEquipment = slots[s]
		hp_flat += it.bonus_health.x
		hp_pct += it.bonus_health.y
		sp_flat += it.speed_bonus.x
		sp_pct += it.speed_bonus.y

	character.bonus_speed_flat = sp_flat
	character.bonus_speed_percent = sp_pct
	character.set_bonus_max_health(hp_flat + base_hp * hp_pct / 100.0)

## Резисты всей брони. Оружие в руках пропускаем —
## его уже считает Character.total_resistances() через equipped_weapons.
func total_resistances() -> Dictionary:
	var res := {}
	for s in slots:
		if (s == ES.HAND_1 or s == ES.HAND_2) and slots[s] is ItemWeapon:
			continue
		var it : ItemEquipment = slots[s]
		for t in it.resistances:
			res[t] = res.get(t, Vector2.ZERO) + it.resistances[t]
	return res

## Модификация таблицы урона бонусами экипировки
## (damage_bonuses: X = ед., Y = %; global_damage_percent — общий %).
func modify_damage_table(base: Dictionary) -> Dictionary:
	var out := {}
	for t in base:
		out[t] = float(base[t])
	var global_pct := 0.0
	for s in slots:
		var it : ItemEquipment = slots[s]
		global_pct += it.global_damage_percent
		for t in it.damage_bonuses:
			var b : Vector2 = it.damage_bonuses[t]
			out[t] = float(out.get(t, 0.0)) * (1.0 + b.y / 100.0) + b.x
	if global_pct != 0.0:
		for t in out:
			out[t] = float(out[t]) * (1.0 + global_pct / 100.0)
	return out

## X = суммарный шанс крита (%), Y = множитель крита.
func crit_params() -> Vector2:
	var chance := 0.0
	var mult := 1.5
	for s in slots:
		var it : ItemEquipment = slots[s]
		chance += it.crit_chance
		mult = maxf(mult, it.crit_multiplier)
	return Vector2(chance, mult)

## Суммарный бонус к скорости атаки (%).
func attack_speed_bonus() -> float:
	var b := 0.0
	for s in slots:
		b += (slots[s] as ItemEquipment).bonus_attack_speed
	return b

func stamina_cost_modifier() -> float:
	var modifier := 0.0

	for slot_id in slots:
		var item := slots[slot_id] as ItemEquipment

		if item:
			modifier += item.stamina_cost_modifier

	return modifier


func mana_cost_modifier() -> float:
	var modifier := 0.0

	for slot_id in slots:
		var item := slots[slot_id] as ItemEquipment

		if item:
			modifier += item.mana_cost_modifier

	return modifier
