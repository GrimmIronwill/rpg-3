@tool
extends Item
class_name ItemEquipment

@export var valid_equip_slots : Array[GameEnums.EquipSlot]
@export var equipment_category : GameEnums.EquipCategory
@export var level : int
@export var requirements : Dictionary[GameEnums.Attribute, int]
@export var attribute_bonuses : Dictionary[GameEnums.Attribute, Vector2]
@export var specialization_bonuses : Dictionary[GameEnums.Specialization, Vector2]
@export var damage_bonuses : Dictionary[GameEnums.DamageTypes, Vector2]
@export var global_damage_percent : float
@export var bonus_attack_speed : float
@export var resistances : Dictionary[GameEnums.DamageTypes, Vector2]
@export var bonus_health : Vector2
@export var bonus_stamina : Vector2
@export var bonus_mana : Vector2
@export var evasion : Vector2
@export var accuracy : Vector2
@export var speed_bonus : Vector2
@export var stamina_cost_modifier : float
@export var mana_cost_modifier : float
@export var crit_chance : float
@export var crit_multiplier : float
@export var durability : int
@export var max_durability : int
@export var rune_slots : int
@export var inserted_runes : Array[Resource]
