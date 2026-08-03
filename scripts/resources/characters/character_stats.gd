@tool
extends DatabaseItem
class_name CharacterStats

@export var id : String
@export var name : String
@export var faction : Resource
@export var faction_relations : Dictionary[Resource, GameEnums.FactionRelation]
@export var level : int
@export var current_xp : float
@export var cap_xp_per_lvl : float
@export var can_gain_xp : bool
@export var strength : int
@export var dexterity : int
@export var body : int
@export var intelligence : int
@export var perception : int
@export var specializations : Dictionary[GameEnums.Specialization, int]
@export var damage_table : Dictionary[GameEnums.DamageCategory, float]
@export var crit_chance : float
@export var crit_multiplier : float
@export var health : Vector2 ## X = текущее, Y = макс
@export var health_regen : Vector2 ## X = в ед. Y = в проц
@export var stamina : Vector2 ## X = текущее, Y = макс
@export var stamina_regen : Vector2 ## X = в ед. Y = в проц
@export var mana : Vector2 ## X = текущее, Y = макс
@export var mana_regen : Vector2 ## X = в ед. Y = в проц
@export var speed_bonus : Vector2
@export var carry_weight : float
@export var vision_radius : float
@export var vision_angle : float
@export var stealth_vision_radius : float
@export var stealth_vision_angle : float
@export var hearing_radius : float
@export var hearing_strength : float
@export var resistances : Dictionary[GameEnums.DamageTypes, Vector2]
@export var evasion : Vector2
@export var accuracy : Vector2
