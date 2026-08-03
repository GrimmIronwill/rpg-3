extends RefCounted
class_name InventorySlot

var item : Item
var origin : Vector2i        ## Левый верхний угол в сетке
var rotated : bool = false   ## size.x ↔ size.y
var quantity : int = 1
