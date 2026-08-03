class_name Inventory
extends RefCounted

signal changed

var grid_size : Vector2i
var _slots : Array[InventorySlot] = []
var _cell_map : Dictionary = {}  # Vector2i -> InventorySlot

func _init(size := Vector2i(10, 10)) -> void:
	grid_size = size

func get_slots() -> Array[InventorySlot]:
	return _slots

func slot_at(cell: Vector2i) -> InventorySlot:
	return _cell_map.get(cell)

## Размер предмета в ячейках с учётом поворота
func item_size(item: Item, rotated: bool) -> Vector2i:
	var s := Vector2i(maxi(int(item.size.x), 1), maxi(int(item.size.y), 1))
	return Vector2i(s.y, s.x) if rotated else s

func can_place(item: Item, origin: Vector2i, rotated := false, ignore: InventorySlot = null) -> bool:
	var s := item_size(item, rotated)
	if origin.x < 0 or origin.y < 0 \
	or origin.x + s.x > grid_size.x or origin.y + s.y > grid_size.y:
		return false
	for y in s.y:
		for x in s.x:
			var occ = _cell_map.get(origin + Vector2i(x, y))
			if occ != null and occ != ignore:
				return false
	return true

func place(item: Item, origin: Vector2i, rotated := false, quantity := 1) -> InventorySlot:
	if not can_place(item, origin, rotated):
		return null
	var slot := InventorySlot.new()
	slot.item = item
	slot.origin = origin
	slot.rotated = rotated
	slot.quantity = quantity
	_slots.append(slot)
	_occupy(slot)
	changed.emit()
	return slot

func remove(slot: InventorySlot) -> void:
	_free_cells(slot)
	_slots.erase(slot)
	changed.emit()

## Перемещение (drag&drop). true = успех.
func move(slot: InventorySlot, new_origin: Vector2i, new_rotated: bool) -> bool:
	if not can_place(slot.item, new_origin, new_rotated, slot):
		return false
	_free_cells(slot)
	slot.origin = new_origin
	slot.rotated = new_rotated
	_occupy(slot)
	changed.emit()
	return true

func can_stack(from: InventorySlot, into: InventorySlot) -> bool:
	return from != into \
		and _same_item(from.item, into.item) \
		and maxi(into.item.max_stack, 1) > 1 \
		and into.quantity < into.item.max_stack

## Слить стаки. Возвращает остаток в from (0 = from удалён).
func merge(from: InventorySlot, into: InventorySlot) -> int:
	var add := mini(from.quantity, into.item.max_stack - into.quantity)
	into.quantity += add
	from.quantity -= add
	if from.quantity <= 0:
		remove(from)
	changed.emit()
	return maxi(from.quantity, 0)

## Автодобавление (подбор с земли и т.п.). Возвращает остаток, который не влез.
func add_item(item: Item, quantity := 1) -> int:
	var max_stack := maxi(item.max_stack, 1)
	if max_stack > 1:
		for slot in _slots:
			if quantity <= 0: break
			if _same_item(slot.item, item) and slot.quantity < max_stack:
				var add := mini(quantity, max_stack - slot.quantity)
				slot.quantity += add
				quantity -= add
	while quantity > 0:
		var spot := _find_free_origin(item)
		if spot.is_empty(): break
		var put := mini(quantity, max_stack)
		place(item, spot[0], spot[1], put)
		quantity -= put
	changed.emit()
	return quantity

## --- внутреннее ---

func _find_free_origin(item: Item) -> Array:  # [origin, rotated] или []
	for rot in [false, true]:
		var s := item_size(item, rot)
		for y in range(grid_size.y - s.y + 1):
			for x in range(grid_size.x - s.x + 1):
				if can_place(item, Vector2i(x, y), rot):
					return [Vector2i(x, y), rot]
	return []

func _same_item(a: Item, b: Item) -> bool:
	return a == b or (a.id != "" and a.id == b.id)

func _occupy(slot: InventorySlot) -> void:
	var s := item_size(slot.item, slot.rotated)
	for y in s.y:
		for x in s.x:
			_cell_map[slot.origin + Vector2i(x, y)] = slot

func _free_cells(slot: InventorySlot) -> void:
	var s := item_size(slot.item, slot.rotated)
	for y in s.y:
		for x in s.x:
			_cell_map.erase(slot.origin + Vector2i(x, y))
