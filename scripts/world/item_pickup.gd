class_name ItemPickup
extends Node2D
## Предмет на земле. Без физики: подбирается,
## когда игрок оказывается в той же клетке / рядом.

@export var item : Item
@export var quantity : int = 1
## Задержка перед возможностью подбора
@export var pickup_delay : float = 0.0
## Радиус подбора в пикселях
@export var pickup_radius : float = 20.0

var _timer := 0.0

func _ready() -> void:
	if item and item.sprite_world:
		var s := Sprite2D.new()
		s.texture = item.sprite_world
		add_child(s)

func _process(delta: float) -> void:
	_timer += delta
	if _timer < pickup_delay: return

	var pl := get_tree().get_first_node_in_group("player") as Node2D
	if pl == null or not is_instance_valid(pl): return
	if global_position.distance_to(pl.global_position) > pickup_radius: return

	var inv := pl.get_node_or_null("PlayerInventory") as PlayerInventory
	if inv == null: return
	quantity = inv.add_item(item, quantity)
	if quantity <= 0:
		queue_free()
