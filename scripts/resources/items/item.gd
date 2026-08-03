@tool
extends DatabaseItem
class_name Item

@export var id : String
@export var name : String
@export var sprite_container : Texture2D
@export var sprite_mask_container : Texture2D
@export var sprite_world : Texture2D
@export var sprite_mask_world : Texture2D
@export var quantity : int
@export var max_stack : int
@export var size : Vector2 ## Размер в ячейках
@export var item_type : GameEnums.ItemType
@export var rarity : GameEnums.Rarity
@export var cost_money : float
@export var cost_value_points : float
@export var weight : float
