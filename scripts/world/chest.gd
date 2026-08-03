@tool
class_name Chest
extends WorldObject
## Сундук: разрушаемый объект мира с инвентарём.
## Открывается КЛИКОМ (умный клик игрока) или E, когда игрок стоит ВПЛОТНУЮ
## (в соседней клетке, включая диагональ). OpenRange больше нет.
## При разрушении высыпает содержимое на землю (ItemPickup).

@export_group("Контейнер")
@export var container_name : String = "Сундук"
@export var container_grid_size : Vector2i = Vector2i(6, 4)
## Можно ли класть внутрь рюкзаки/пояса (сами контейнеры)
@export var allow_containers_inside : bool = true
## Стартовый лут. Ресурсы дублируются, количество берётся из item.quantity.
@export var start_items : Array[Item] = []

var _inventory : FilteredInventory

func _ready() -> void:
	super()
	if Engine.is_editor_hint(): return
	add_to_group("interactables")

func get_inventory() -> Inventory:
	if _inventory == null:
		_inventory = FilteredInventory.new(container_grid_size, [], allow_containers_inside)
		for it in start_items:
			if it == null: continue
			var copy := it.duplicate(true) as Item   # НЕ делим ресурс между сундуками
			_inventory.add_item(copy, maxi(copy.quantity, 1))
	return _inventory

## ═══════════ ИНТЕРФЕЙС "interactables" ═══════════

## Открыть можно только вплотную: игрок в соседней клетке (Chebyshev <= 1).
func can_interact(by: Node2D) -> bool:
	if not is_alive() or by == null: return false
	return Character.chebyshev(_cell_of(global_position), _cell_of(by.global_position)) <= 1

func interact(by: Node2D) -> void:
	var pinv := _find_player_inventory(by)
	if pinv == null and get_tree().current_scene:
		pinv = _find_player_inventory(get_tree().current_scene)
	if pinv == null:
		push_warning("Chest: PlayerInventory не найден ни на игроке, ни в сцене!")
		return
	pinv.open_container(get_inventory(), container_name, self, _close_distance())

## Клетка мира для точки (через NavManager, с фолбэком).
func _cell_of(p: Vector2) -> Vector2i:
	var nav := get_node_or_null("/root/NavManager")
	if nav and nav.is_initialized():
		return nav.world_to_cell(p)
	return Vector2i(floori(p.x / 32.0), floori(p.y / 32.0))

## Дистанция автозакрытия окна: чуть больше диагонали соседней клетки,
## но меньше двух клеток по прямой — отошёл от сундука == окно закрылось.
func _close_distance() -> float:
	var cs := 32.0
	var nav := get_node_or_null("/root/NavManager")
	if nav and nav.is_initialized():
		cs = float(nav.cell_size.x)
	return cs * 1.9

## Поиск PlayerInventory по КЛАССУ на любой глубине.
func _find_player_inventory(root: Node) -> PlayerInventory:
	if root is PlayerInventory:
		return root
	for c in root.get_children():
		var found := _find_player_inventory(c)
		if found: return found
	return null

## ═══════════ РАЗРУШЕНИЕ -> ЛУТ НА ЗЕМЛЮ ═══════════

func _on_destroyed(_attacker: Node2D) -> void:
	if _inventory == null:
		return
	for slot in _inventory.get_slots().duplicate():
		_spawn_pickup(slot.item, slot.quantity)
		_inventory.remove(slot)

func _spawn_pickup(item: Item, qty: int) -> void:
	if item == null or qty <= 0: return
	var pickup := ItemPickup.new()
	pickup.item = item
	pickup.quantity = qty
	pickup.pickup_delay = 0.5
	var holder : Node = get_tree().current_scene if get_tree().current_scene else get_parent()
	holder.add_child(pickup)
	pickup.global_position = global_position \
		+ Vector2.RIGHT.rotated(randf() * TAU) * randf_range(8.0, collision_radius + 24.0)
