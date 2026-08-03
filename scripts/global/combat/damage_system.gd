class_name DamageSystem
extends RefCounted

## ═══════════════════════════════════════════
##   РАСЧЁТ УРОНА: (урон - броня*коэф) * (1 - резист%)
## ═══════════════════════════════════════════

## Коэффициенты эффективности брони против физ. типов урона
const PHYS_ARMOR_COEF := {
	GameEnums.DamageTypes.SLICE:  1.5,  # режущий
	GameEnums.DamageTypes.SLASH:  1.0,  # рубящий
	GameEnums.DamageTypes.PIERCE: 0.4,  # колющий
	GameEnums.DamageTypes.BLUNT:  0.2,  # дробящий
}

static func is_physical(type: int) -> bool:
	return PHYS_ARMOR_COEF.has(type)

## damage_table : {DamageTypes: float} — входящий урон по типам
## resistances  : {DamageTypes: Vector2} — X = флат-броня против типа, Y = % резиста (50 = 50%)
static func calculate(damage_table: Dictionary, phys_armor: float,
		magic_armor: float, resistances: Dictionary) -> float:
	var total := 0.0
	for type in damage_table:
		var dmg := float(damage_table[type])
		if dmg <= 0.0:
			continue

		var res: Vector2 = resistances.get(type, Vector2.ZERO)
		var armor: float
		if is_physical(type):
			armor = (phys_armor + res.x) * PHYS_ARMOR_COEF[type]
		else:
			armor = magic_armor + res.x

		var after_armor := maxf(dmg - armor, 0.0)
		# резист > 100% просто обнуляет урон, не хилит
		var mult := maxf(1.0 - res.y / 100.0, 0.0)
		total += after_armor * mult
	return total
