class_name FilteredInventory
extends Inventory
## Инвентарь с фильтрами:
## - по типам предметов (пояс зелий = только CONSUMABLE);
## - запрет вкладывать контейнеры внутрь контейнеров.

## Разрешённые GameEnums.ItemType (пустой массив = любые типы)
var allowed_item_types : Array = []
## Можно ли класть внутрь другие контейнеры (ItemContainer).
## Для рюкзаков/поясов — false, для сундуков обычно true.
var allow_containers : bool = false

func _init(size := Vector2i(4, 4), types : Array = [], containers_allowed := false) -> void:
	super(size)
	allowed_item_types = types.duplicate()
	allow_containers = containers_allowed

## Пропускает ли фильтр предмет в принципе.
func accepts(item: Item) -> bool:
	if item == null:
		return false
	if not allow_containers and item is ItemContainer:
		return false
	if not allowed_item_types.is_empty() and not allowed_item_types.has(int(item.item_type)):
		return false
	return true

## Все пути укладки идут через can_place/add_item — фильтруем здесь,
## поэтому drag&drop в InventoryUI автоматически подсветит запрет красным.
func can_place(item: Item, origin: Vector2i, rotated := false, ignore: InventorySlot = null) -> bool:
	if not accepts(item):
		return false
	return super(item, origin, rotated, ignore)

func add_item(item: Item, quantity := 1) -> int:
	if not accepts(item):
		return quantity   # ничего не влезло — весь остаток назад
	return super(item, quantity)
