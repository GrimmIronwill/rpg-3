extends Node
class_name enums

## Типы урона
enum DamageTypes {
	SLASH,
	SLICE,
	PIERCE,
	BLUNT,
	FIRE,
	COLD,
	POISON,
	LIGHTNING,
	HOLY,
	DARK,
}

## enum -> строка (сырая)
static func damage_type_to_string(type: DamageTypes) -> String:
	var key = DamageTypes.keys()[type] as String
	return key

## строка -> enum (принимаем "сырой" ключ, например "Fire")
static func string_to_damage_type(name: String) -> DamageTypes:
	var idx := DamageTypes.keys().find(name)
	if idx == -1:
		push_error("Unknown damage type: %s" % name)
		return DamageTypes.SLASH # значение по умолчанию
	return DamageTypes.values()[idx]

### --- ###

enum Faction {
	NEUTRAL,
	PLAYER,
	BANDITS,
	UNDEAD,
	BEASTS,
}

enum FactionRelation {
	HOSTILE,
	NEUTRAL,
	FRIENDLY,
}

enum WeaponType {
	NONE,
	SWORD,
	AXE,
	MACE,
	BOW,
	STAFF,
	DAGGER,
}

enum WeaponHand {
	ONE_HANDED,
	TWO_HANDED,
}

enum AttackRange {
	MELEE,
	RANGED,
}

enum AttackActivation {
	PROJECTILE,
	INSTANT,
}
