@tool
class_name ItemTooltip
extends RefCounted
## Сборка текста тултипа предмета: имя, редкость и все значимые статы.

const RARITY_RU : PackedStringArray = [
	"Обычный", "Необычный", "Редкий", "Эпический",
	"Легендарный", "Божественный", "Уникальный",
]

const DMG_RU := {
	GameEnums.DamageTypes.SLASH: "рубящий",
	GameEnums.DamageTypes.SLICE: "режущий",
	GameEnums.DamageTypes.PIERCE: "колющий",
	GameEnums.DamageTypes.BLUNT: "дробящий",
	GameEnums.DamageTypes.FIRE: "огонь",
	GameEnums.DamageTypes.COLD: "холод",
	GameEnums.DamageTypes.POISON: "яд",
	GameEnums.DamageTypes.LIGHTNING: "молния",
	GameEnums.DamageTypes.HOLY: "свет",
	GameEnums.DamageTypes.DARK: "тьма",
}

const ATTR_RU := {
	GameEnums.Attribute.STRENGTH: "Сила",
	GameEnums.Attribute.DEXTERITY: "Ловкость",
	GameEnums.Attribute.BODY: "Телосложение",
	GameEnums.Attribute.INTELLIGENCE: "Интеллект",
	GameEnums.Attribute.PERCEPTION: "Восприятие",
}

const SPEC_RU := {
	GameEnums.Specialization.WARFARE: "Воинское дело",
	GameEnums.Specialization.ASSASSIN: "Ассасин",
	GameEnums.Specialization.RANGED_COMBAT: "Стрельба",
	GameEnums.Specialization.SORCERY: "Колдовство",
	GameEnums.Specialization.ALCHEMY: "Алхимия",
	GameEnums.Specialization.SURVIVAL: "Выживание",
}


static func build(item: Item) -> String:
	if item == null:
		return ""
	var l : PackedStringArray = []
	l.append(item.name if item.name != "" else "Безымянный предмет")
	if item.rarity >= 0 and item.rarity < RARITY_RU.size():
		l.append(RARITY_RU[item.rarity])

	if item is ItemWeapon:
		_weapon(item, l)
	if item is ItemEquipment:
		_equipment(item, l)
	if item is ItemConsumable:
		_consumable(item, l)

	if item.weight > 0.0:
		l.append("Вес: " + _num(item.weight))
	if item.cost_money > 0.0:
		l.append("Цена: " + _num(item.cost_money))
	return "\n".join(l)


static func _weapon(w: ItemWeapon, l: PackedStringArray) -> void:
	for t in w.damage_table:
		var v := float(w.damage_table[t])
		if v != 0.0:
			l.append("Урон (%s): %s" % [DMG_RU.get(t, str(t)), _num(v)])
	# attack_speed = сколько ОД тратит один удар
	if w.attack_speed > 0:
		l.append("Стоимость атаки: %d ОД" % w.attack_speed)
	# Дальности — в КЛЕТКАХ
	if w.weapon_range == GameEnums.WeaponRange.RANGED:
		if w.ranged_distance > 0:
			l.append("Дальность: %d кл." % w.ranged_distance)
	elif w.melee_range > 0:
		l.append("Дальность: %d кл." % w.melee_range)
	if w.grip == GameEnums.WeaponGrip.TWO_HANDED:
		l.append("Двуручное")
	if w.stamina_cost > 0.0:
		l.append("Стамина за удар: " + _num(w.stamina_cost))
	if w.mana_cost > 0.0:
		l.append("Мана за удар: " + _num(w.mana_cost))


static func _equipment(e: ItemEquipment, l: PackedStringArray) -> void:
	for t in e.resistances:
		var s := _v2(e.resistances[t])
		if s != "":
			l.append("Защита (%s): %s" % [DMG_RU.get(t, str(t)), s])
	for t in e.damage_bonuses:
		var s := _v2(e.damage_bonuses[t])
		if s != "":
			l.append("Бонус урона (%s): %s" % [DMG_RU.get(t, str(t)), s])
	if e.global_damage_percent != 0.0:
		l.append("Весь урон: %s%%" % _sign(e.global_damage_percent))
	if e.bonus_attack_speed != 0.0:
		l.append("Скорость атаки: %s%%" % _sign(e.bonus_attack_speed))

	for a in e.attribute_bonuses:
		var s := _v2(e.attribute_bonuses[a])
		if s != "":
			l.append("%s: %s" % [ATTR_RU.get(int(a), str(a)), s])
	for sp in e.specialization_bonuses:
		var s := _v2(e.specialization_bonuses[sp])
		if s != "":
			l.append("%s: %s" % [SPEC_RU.get(int(sp), str(sp)), s])

	_kv2(l, "Здоровье", e.bonus_health)
	_kv2(l, "Стамина", e.bonus_stamina)
	_kv2(l, "Мана", e.bonus_mana)
	_kv2(l, "Скорость", e.speed_bonus)
	_kv2(l, "Уклонение", e.evasion)
	_kv2(l, "Меткость", e.accuracy)

	if e.crit_chance != 0.0:
		l.append("Шанс крита: %s%%" % _sign(e.crit_chance))
	if e.crit_multiplier > 0.0:
		l.append("Множитель крита: x" + _num(e.crit_multiplier))
	if e.max_durability > 0:
		l.append("Прочность: %d/%d" % [e.durability, e.max_durability])

	if not e.requirements.is_empty():
		var req : PackedStringArray = []
		for a in e.requirements:
			req.append("%s %d" % [ATTR_RU.get(int(a), str(a)), int(e.requirements[a])])
		l.append("Требуется: " + ", ".join(req))


static func _consumable(c: ItemConsumable, l: PackedStringArray) -> void:
	if c.bonus_health.x > 0.0:
		l.append("Лечит: %s HP" % _num(c.bonus_health.x))
	if c.bonus_health.y > 0.0:
		l.append("Лечит: %s%% макс. HP" % _num(c.bonus_health.y))
	if c.effect_duration > 0.0:
		l.append("Длительность: %s сек" % _num(c.effect_duration))


## ── Хелперы форматирования ──

static func _num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(int(roundf(x)))
	return "%.1f" % x

static func _sign(x: float) -> String:
	return ("+" if x >= 0.0 else "") + _num(x)

## Vector2: X = ед., Y = %
static func _v2(v: Vector2) -> String:
	var parts : PackedStringArray = []
	if v.x != 0.0: parts.append(_sign(v.x))
	if v.y != 0.0: parts.append(_sign(v.y) + "%")
	return " ".join(parts)

static func _kv2(l: PackedStringArray, label: String, v: Vector2) -> void:
	var s := _v2(v)
	if s != "":
		l.append("%s: %s" % [label, s])
