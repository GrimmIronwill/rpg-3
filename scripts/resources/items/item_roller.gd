class_name ItemRoller
extends RefCounted
## Берёт базовую строку из БД + её random_profile и выдаёт случайный предмет.

#region Использование (пример)
## var roller := ItemRoller.new(DB)          # DB — autoload DBAccess
## var sword  := roller.roll("Weapons", "weapons_0009")
## var loot   := roller.roll_any("Equipment")
#endregion

const PROFILE_FIELD := "random_profile"

var db: DBAccess
var rng := RandomNumberGenerator.new()

func _init(p_db: DBAccess, p_seed: int = 0) -> void:
	db = p_db
	if p_seed != 0:
		rng.seed = p_seed   # детерминизм для сейвов/сети
	else:
		rng.randomize()

## Случайная версия конкретного предмета.
func roll(table: String, entry_id: String) -> Dictionary:
	var item := db.get_row(table, entry_id)
	if item.is_empty():
		return {}
	var profile := db.get_ref_row(table, entry_id, PROFILE_FIELD)
	if profile.is_empty():
		return item   # профиль не задан → предмет «как в базе»
	return _apply(item, profile)

## Случайный предмет из всей таблицы (простейший лут).
func roll_any(table: String) -> Dictionary:
	var ids := db.get_ids(table)
	if ids.is_empty():
		return {}
	return roll(table, ids[rng.randi_range(0, ids.size() - 1)])

# ──────────────────────────────────────────────────────────────

func _apply(item: Dictionary, p: Dictionary) -> Dictionary:
	# У Weapons статы лежат в equipment_data, у Equipment/Consumables — сверху.
	var stats: Dictionary = item
	if not item.has("level") and item.get("equipment_data") is Dictionary:
		stats = item["equipment_data"]
	var item_data: Dictionary = stats["item_data"] if stats.get("item_data") is Dictionary else {}

	# 1. Уровень
	var level := _ri(p.get("level_range", Vector2.ONE))
	stats["level"] = level

	# 2. Редкость (взвешенно) + множитель силы
	var rarity := _weighted(p.get("rarity_weights", {}))
	if rarity >= 0 and item_data.has("rarity"):
		item_data["rarity"] = rarity
	var power: float = _dictf(p.get("rarity_power", {}), rarity, 1.0) \
		* (1.0 + 0.1 * (level - 1))   # лёгкий рост от уровня, подстрой под себя

	# 3. Урон (Weapons: damage_table = float, Equipment: damage_bonuses = Vector2)
	var spread: Vector2 = p.get("damage_spread", Vector2.ONE)
	if item.get("damage_table") is Dictionary:
		_scale_damage(item["damage_table"], spread, power)
	if stats.get("damage_bonuses") is Dictionary:
		_scale_damage(stats["damage_bonuses"], spread, power)

	# 3.5 Гарантированные бонусы (ключ enum → Vector2(min, max))
	_apply_guaranteed(p.get("guaranteed_attrs", {}), stats, "attribute_bonuses",
			power, level, float(p.get("req_per_level", 0.0)))
	_apply_guaranteed(p.get("guaranteed_specs", {}), stats, "specialization_bonuses",
			power, 0, 0.0)

	# 4. Случайные бонусы атрибутов + требования к ним же
	var attrs := db.get_enum_values("Enums", "Attribute")
	var n := _ri(p.get("attr_bonus_count", Vector2.ZERO))
	if n > 0 and stats.get("attribute_bonuses") is Dictionary:
		var taken: Array = stats["attribute_bonuses"].keys()
		for idx in _pick_distinct_excluding(attrs.size(), n, taken):
			var val := roundf(_rf(p.get("attr_bonus_value", Vector2(1, 3))) * power)
			stats["attribute_bonuses"][idx] = Vector2(val, 0.0)  # X = ед.
			var req := int(ceil(level * float(p.get("req_per_level", 0.0))))
			if req > 0 and stats.get("requirements") is Dictionary:
				stats["requirements"][idx] = req

	# 5. Случайные бонусы специализаций
	var specs := db.get_enum_values("Enums", "Specialization")
	n = _ri(p.get("spec_bonus_count", Vector2.ZERO))
	if n > 0 and stats.get("specialization_bonuses") is Dictionary:
		for idx in _pick_distinct(specs.size(), n):
			var val := roundf(_rf(p.get("spec_bonus_value", Vector2(1, 2))) * power)
			stats["specialization_bonuses"][idx] = Vector2(val, 0.0)

	# 6. Прочность
	if p.get("durability_range") is Vector2 and stats.has("max_durability"):
		var dur := int(roundf(_ri(p["durability_range"]) * power))
		stats["max_durability"] = dur
		stats["durability"] = dur

	# 7. Цена
	if item_data.has("cost_money"):
		item_data["cost_money"] = snappedf(
			float(item_data["cost_money"]) * _rf(p.get("cost_spread", Vector2.ONE)) * power, 0.01)

	return item

## Гарантированные бонусы: ключи — int-индексы enum, значения — Vector2(min, max).
func _apply_guaranteed(guaranteed: Dictionary, stats: Dictionary, field: String,
		power: float, level: int, req_per_level: float) -> void:
	if guaranteed.is_empty() or not (stats.get(field) is Dictionary):
		return
	for key in guaranteed:
		var range_v: Variant = guaranteed[key]
		if not (range_v is Vector2):
			continue
		var val := roundf(_rf(range_v) * power)
		if val <= 0.0:
			continue   # выпал 0 → бонуса нет (трюк с min=0)
		var old: Vector2 = stats[field].get(int(key), Vector2.ZERO)
		stats[field][int(key)] = Vector2(old.x + val, old.y)
		## stats[field][int(key)] = Vector2(val, 0.0)   # X = ед.
		# Требование к атрибуту, если предмет вообще их использует
		if req_per_level > 0.0 and stats.get("requirements") is Dictionary:
			var req := int(ceil(level * req_per_level))
			if req > 0:
				stats["requirements"][int(key)] = req

# ── Хелперы ───────────────────────────────────────────────────

func _rf(v: Vector2) -> float:
	return rng.randf_range(minf(v.x, v.y), maxf(v.x, v.y))

func _ri(v: Vector2) -> int:
	return rng.randi_range(int(minf(v.x, v.y)), int(maxf(v.x, v.y)))

## Взвешенный выбор: ключи словаря — индексы enum (int), значения — веса.
func _weighted(weights: Dictionary) -> int:
	var total := 0.0
	for k in weights:
		total += maxf(0.0, float(weights[k]))
	if total <= 0.0:
		return -1
	var r := rng.randf() * total
	for k in weights:
		r -= maxf(0.0, float(weights[k]))
		if r <= 0.0:
			return int(k)
	return -1

func _dictf(d: Dictionary, key: int, def: float) -> float:
	return float(d.get(key, def)) if key >= 0 else def

func _pick_distinct(pool_size: int, count: int) -> Array[int]:
	var all: Array[int] = []
	for i in range(pool_size):
		all.append(i)
	all.shuffle()   # использует глобальный rand; для строгого детерминизма перемешай через rng
	return all.slice(0, mini(count, pool_size))

func _pick_distinct_excluding(pool_size: int, count: int, exclude: Array) -> Array[int]:
	var pool: Array[int] = []
	for i in range(pool_size):
		if not exclude.has(i):
			pool.append(i)
	pool.shuffle()
	return pool.slice(0, mini(count, pool.size()))

func _scale_damage(d: Dictionary, spread: Vector2, power: float) -> void:
	for k in d.keys():
		var m := _rf(spread) * power
		var v: Variant = d[k]
		if v is Vector2:
			d[k] = Vector2(v.x * m, v.y)   # X = ед., Y (проценты) не трогаем
		elif v is float or v is int:
			d[k] = snappedf(float(v) * m, 0.1)
