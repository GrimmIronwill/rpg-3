@tool
extends ItemEquipment
class_name ItemWeapon

@export var weapon_type : GameEnums.WeaponType
@export var grip : GameEnums.WeaponGrip
@export var weapon_range : GameEnums.WeaponRange
@export var attack_activation : GameEnums.AttackActivation
@export var damage_table : Dictionary[GameEnums.DamageTypes, float]
@export var attack_speed: int
@export var melee_range : int
@export var ranged_distance : int
@export var stamina_cost : float
@export var mana_cost : float
