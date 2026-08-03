@tool
extends ItemEquipment
class_name ItemContainer
## Предмет-контейнер (рюкзак, пояс для зелий) со своим внутренним инвентарём.
## Вкладывать контейнеры друг в друга НЕЛЬЗЯ (запрещает FilteredInventory).
##
## Рюкзак:      equipment_category = BACKPACK,     allowed_item_types = []
## Пояс зелий:  equipment_category = POTION_BELT,  allowed_item_types = [CONSUMABLE]
##
## ВАЖНО: содержимое живёт на ИНСТАНСЕ ресурса. Если раздаёшь один .tres
## нескольким объектам/лутам — дублируй его (duplicate(true)),
## иначе все копии будут делить одно содержимое.

@export_group("Контейнер")
## Размер внутренней сетки в ячейках
@export var container_grid_size : Vector2i = Vector2i(4, 4)
## Ограничение по типам предметов (пусто = любые)
@export var allowed_item_types : Array[GameEnums.ItemType] = []
## Размер ячейки в окне контейнера (пиксели)
@export var window_cell_size : int = 48

var _inventory : FilteredInventory

## Ленивое создание: инвентарь появляется при первом обращении.
func get_inventory() -> Inventory:
	if _inventory == null:
		var types : Array = []
		for t in allowed_item_types:
			types.append(int(t))
		_inventory = FilteredInventory.new(container_grid_size, types, false)
	return _inventory

func is_empty_container() -> bool:
	return _inventory == null or _inventory.get_slots().is_empty()

func display_name() -> String:
	return name if name != "" else "Контейнер"
