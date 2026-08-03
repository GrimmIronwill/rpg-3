@tool
class_name PlayerInventory
extends Node

signal opened
signal closed

@export var grid_size := Vector2i(10, 6)
@export var ui : InventoryUI
@export var ui_root : Control
@export var doll : EquipmentDollUI
@export var doll_root : Control
@export var equipment : PlayerEquipment

var inventory : Inventory

## Слот куклы, из которого сейчас тащим предмет (-1 — не тащим).
var _doll_drag_from : int = -1

## ── Окна контейнеров (сундуки, рюкзаки, пояса) ──
var _windows : Array = []                     # открытые ContainerWindow
var _active_window : ContainerWindow = null   # последнее активное окно
var _windows_layer : CanvasLayer = null       # ВСЕ окна живут тут, НЕ в ui_root

## ── Текущий драг (для кросс-сеточной подсветки) ──
var _drag_item : Item = null
var _drag_source_ui : InventoryUI = null

func _ready() -> void:
	if Engine.is_editor_hint(): return
	inventory = Inventory.new(grid_size)

	if equipment == null:
		var p := get_parent()
		if p:
			for c in p.get_children():
				if c is PlayerEquipment:
					equipment = c
					break

	var root : Node = get_parent() if get_parent() else self
	if ui == null:
		ui = _find_inventory_ui(root)
	if doll == null:
		doll = _find_doll(root)
	if ui == null:
		push_warning("PlayerInventory: InventoryUI не найден — назначь его в инспекторе!")
	if doll == null:
		push_warning("PlayerInventory: EquipmentDollUI не найден — назначь его в инспекторе!")

	if ui:
		ui.inventory = inventory
		ui.slot_activated.connect(_on_slot_activated)
		ui.drop_requested.connect(_on_drop_requested)
		ui.dropped_outside.connect(_on_dropped_outside)
		# драг С куклы:
		ui.external_placed.connect(_on_external_placed)
		ui.external_swap_requested.connect(_on_external_swap)
		ui.external_dropped_outside.connect(_on_external_dropped_outside)
		ui.external_world_drop_requested.connect(_on_external_world_drop)
		_hook_drag_ui(ui)
	if doll:
		doll.equipment = equipment
		doll.unequip_requested.connect(_on_unequip_requested)
		_connect_doll_slots(doll)   # подписка на drag_requested/open_requested каждого слота

	# Старт: всё скрыто (и кукла тоже, даже если живёт вне ui_root).
	if ui_root:
		ui_root.visible = false
	if doll and not (ui_root and ui_root.is_ancestor_of(doll)):
		doll_root.visible = false

## Слоты куклы могут лежать на любой глубине — обходим рекурсивно.
func _connect_doll_slots(node: Node) -> void:
	if node is EquipmentSlotUI:
		node.drag_requested.connect(_on_doll_drag_requested)
		if node.has_signal("open_requested") \
		and not node.open_requested.is_connected(_on_doll_open_requested):
			node.open_requested.connect(_on_doll_open_requested)
	for c in node.get_children():
		_connect_doll_slots(c)

func _find_inventory_ui(node: Node) -> InventoryUI:
	if node is InventoryUI:
		return node
	for c in node.get_children():
		var f := _find_inventory_ui(c)
		if f: return f
	return null

func _find_doll(node: Node) -> EquipmentDollUI:
	if node is EquipmentDollUI:
		return node
	for c in node.get_children():
		var f := _find_doll(c)
		if f: return f
	return null

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	# Экшен из InputMap (если настроен) — приоритетнее.
	if InputMap.has_action("inventory") and event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	# FIX: TAB (и I как fallback) открывает/закрывает инвентарь ВМЕСТЕ с куклой.
	if event is InputEventKey and event.pressed and not event.echo:
		var key : Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if key == KEY_TAB or key == KEY_I:
			toggle()
			get_viewport().set_input_as_handled()

func is_open() -> bool:
	if ui_root: return ui_root.visible
	if doll: return doll.visible
	return false

func toggle() -> void:
	var show := not is_open()
	if ui_root:
		ui_root.visible = show
	# Кукла может жить ВНЕ ui_root — переключаем её отдельно.
	if doll and not (ui_root and ui_root.is_ancestor_of(doll)):
		doll_root.visible = show
	if not show:
		close_all_containers()   # закрыли инвентарь — закрываем и окна контейнеров
	(opened if show else closed).emit()

func add_item(item: Item, qty := 1) -> int:
	return inventory.add_item(item, qty)

## ═══════════ КРОСС-СЕТОЧНЫЙ ДРАГ: ПОДСВЕТКА ═══════════

## Подписка любой сетки (игрока или окна) на общий драг-брокер.
func _hook_drag_ui(u: InventoryUI) -> void:
	if u == null: return
	u.drag_started.connect(_on_any_drag_started.bind(u))
	u.drag_ended.connect(_on_any_drag_ended)
	u.drag_rotation_changed.connect(_on_any_drag_rotated)

func _all_uis() -> Array:
	var out : Array = []
	if ui: out.append(ui)
	for w in _windows:
		if is_instance_valid(w) and w.ui:
			out.append(w.ui)
	return out

func _on_any_drag_started(item: Item, source: InventoryUI) -> void:
	_drag_item = item
	_drag_source_ui = source
	for u in _all_uis():
		if u != source:
			u.set_hover_preview(item, false)
	if doll:
		doll._set_drag_preview(item)

func _on_any_drag_rotated(rotated: bool) -> void:
	if _drag_item == null: return
	for u in _all_uis():
		if u != _drag_source_ui:
			u.set_hover_preview(_drag_item, rotated)

func _on_any_drag_ended() -> void:
	_drag_item = null
	_drag_source_ui = null
	for u in _all_uis():
		u.set_hover_preview(null)
	if doll:
		doll._set_drag_preview(null)

## ═══════════ ОКНА КОНТЕЙНЕРОВ ═══════════

## FIX: окна ВСЕГДА живут в собственном CanvasLayer.
## Раньше они добавлялись в ui_root: контейнер-родитель сам их позиционировал
## (окно "прилипало" к углу) и раздувал minimum size всего UI —
## из-за этого большой сундук растягивал инвентарь игрока.
func _window_holder() -> Node:
	if _windows_layer == null or not is_instance_valid(_windows_layer):
		_windows_layer = CanvasLayer.new()
		_windows_layer.layer = 100
		add_child(_windows_layer)
	return _windows_layer

## Открыть окно инвентаря контейнера. source — объект мира (Chest) или null.
## Повторный вызов для того же инвентаря просто поднимает уже открытое окно.
func open_container(inv: Inventory, title: String, source: Node2D = null,
		close_distance := 128.0) -> ContainerWindow:
	if inv == null: return null
	if not is_open():
		toggle()   # для переноса предметов нужен видимый инвентарь игрока

	for w in _windows:
		if is_instance_valid(w) and w.inventory == inv:
			w.move_to_front()
			_active_window = w
			return w

	var win := ContainerWindow.new()
	win.auto_close_distance = close_distance
	_window_holder().add_child(win)
	win.setup(inv, title, source)

	win.take_requested.connect(_on_window_take.bind(win))
	win.world_drop_requested.connect(_on_window_world_drop.bind(win))
	win.slot_dropped_outside.connect(_on_window_slot_dropped)
	win.closed.connect(_on_window_closed)
	win.focused.connect(_on_window_focused)
	_hook_drag_ui(win.ui)   # окно участвует в общей подсветке драга

	_windows.append(win)
	_active_window = win
	win.move_to_front()
	# FIX: позиционируем отложенно — PanelContainer считает свой size
	# только после layout-пасса, иначе центрирование по нулевому size.
	_position_window.call_deferred(win)
	return win

func _position_window(win: ContainerWindow) -> void:
	if not is_instance_valid(win) or not win.is_inside_tree(): return
	win.reset_size()
	var vp := win.get_viewport().get_visible_rect().size
	var idx := maxi(_windows.find(win), 0)
	win.global_position = vp * 0.5 - win.size * 0.5 + Vector2(36, 36) * idx

func close_all_containers() -> void:
	for w in _windows.duplicate():
		if is_instance_valid(w):
			w.close()
	_windows.clear()
	_active_window = null

func _on_window_focused(win: ContainerWindow) -> void:
	_active_window = win

func _on_window_closed(win: ContainerWindow) -> void:
	_windows.erase(win)
	if _active_window == win:
		_active_window = null
		for w in _windows:
			if is_instance_valid(w):
				_active_window = w   # последнее открытое становится активным

func _active_container_valid() -> bool:
	return _active_window != null and is_instance_valid(_active_window) \
		and _active_window.visible and _active_window.inventory != null

## Верхнее окно контейнера под точкой (или null).
func _window_at(global_pos: Vector2) -> ContainerWindow:
	var best : ContainerWindow = null
	for w in _windows:
		if not is_instance_valid(w) or not w.is_visible_in_tree(): continue
		if not w.get_global_rect().has_point(global_pos): continue
		if best == null or w.get_index() >= best.get_index():
			best = w   # выше по порядку отрисовки
	return best

## Универсальный АВТО-перенос слота между инвентарями (ПКМ-переносы и т.п.).
func _move_between(slot: InventorySlot, from_inv: Inventory, to_inv: Inventory) -> void:
	if slot == null or from_inv == null or to_inv == null or from_inv == to_inv:
		return
	var left := to_inv.add_item(slot.item, slot.quantity)
	if left <= 0:
		from_inv.remove(slot)
	elif left != slot.quantity:
		slot.quantity = left
		from_inv.changed.emit()

## ТОЧНЫЙ перенос по drag&drop: кладём именно в ячейку под курсором.
## Над предметом — стакаем; занято/не лезет/фильтр — отмена (false), предмет
## остаётся в исходном инвентаре. Подсветка в сетке-цели это уже показала.
func _precise_transfer(slot: InventorySlot, from_inv: Inventory, to_ui: InventoryUI,
		global_pos: Vector2, rotated: bool) -> bool:
	if slot == null or from_inv == null or to_ui == null or to_ui.inventory == null:
		return false
	var to_inv : Inventory = to_ui.inventory
	if from_inv == to_inv:
		return false
	if not to_ui.get_global_rect().has_point(global_pos):
		return false   # отпустили над окном, но не над сеткой (заголовок и т.п.)
	if not to_ui.accepts_item(slot.item):
		return false   # фильтр контейнера (типы, контейнер-в-контейнер)

	# 1) Стак в предмет под курсором.
	var target := to_inv.slot_at(to_ui.cell_from_global(global_pos))
	if target:
		var max_stack := maxi(target.item.max_stack, 1)
		if _same_item(slot.item, target.item) and max_stack > 1 \
		and target.quantity < max_stack:
			var add := mini(slot.quantity, max_stack - target.quantity)
			target.quantity += add
			slot.quantity -= add
			if slot.quantity <= 0:
				from_inv.remove(slot)
			else:
				from_inv.changed.emit()
			to_inv.changed.emit()
			return true
		return false   # занято и не стакается — отмена

	# 2) Точная укладка в пустое место под курсором.
	var origin := to_ui.origin_for_drop(slot.item, rotated, global_pos)
	if to_inv.can_place(slot.item, origin, rotated):
		var item := slot.item
		var qty := slot.quantity
		from_inv.remove(slot)
		to_inv.place(item, origin, rotated, qty)
		return true
	return false

func _same_item(a: Item, b: Item) -> bool:
	return a == b or (a.id != "" and a.id == b.id)

## ПКМ по предмету в ОКНЕ контейнера -> забрать в инвентарь игрока.
func _on_window_take(slot: InventorySlot, win: ContainerWindow) -> void:
	_move_between(slot, win.inventory, inventory)

## Q в окне контейнера -> выбросить предмет в мир.
func _on_window_world_drop(slot: InventorySlot, win: ContainerWindow) -> void:
	win.inventory.remove(slot)
	_drop_to_world(slot.item, slot.quantity)

## Драг ИЗ окна контейнера, отпущен вне его сетки:
## другое окно -> точно туда; сетка игрока -> точно туда; кукла -> надеть; иначе отмена.
func _on_window_slot_dropped(slot: InventorySlot, global_pos: Vector2,
		rotated: bool, win: ContainerWindow) -> void:
	var other := _window_at(global_pos)
	if other and other != win:
		_precise_transfer(slot, win.inventory, other.ui, global_pos, rotated)
		return
	if ui and ui.is_visible_in_tree() and ui.get_global_rect().has_point(global_pos):
		_precise_transfer(slot, win.inventory, ui, global_pos, rotated)
		return
	# Из сундука сразу на куклу.
	if doll and equipment:
		var target := doll._slot_at_global(global_pos)
		if target and slot.item is ItemEquipment and target.can_accept(slot.item):
			var item := slot.item as ItemEquipment
			_take_one_from(slot, win.inventory)
			_return_removed(equipment.equip(item, int(target.slot_id)))

## ПКМ по предмету в СЕТКЕ игрока при открытом окне -> переложить в контейнер.
## Фильтры (типы, запрет контейнеров в контейнерах) отработают в FilteredInventory.
func _transfer_to_active(slot: InventorySlot) -> void:
	_move_between(slot, inventory, _active_window.inventory)

## ═══════════ ДРАГ С КУКЛЫ ═══════════

func _on_doll_drag_requested(slot_id: int) -> void:
	if ui == null or equipment == null or ui.is_dragging():
		return
	var item := equipment.get_item(slot_id)
	if item == null: return
	_doll_drag_from = slot_id
	# Предмет НЕ снимаем — он остаётся на кукле, пока драг не завершится успешно.
	ui.begin_external_drag(item, _can_swap_with)

## СКМ по слоту куклы: открыть надетый рюкзак/пояс.
func _on_doll_open_requested(slot_id: int) -> void:
	if equipment == null: return
	var c := equipment.get_item(slot_id) as ItemContainer
	if c:
		open_container(c.get_inventory(), c.display_name(), null)

## Можно ли поменяться местами с предметом из сетки: он должен подходить
## в освобождаемый слот куклы (и по типу слота, и по требованиям).
func _can_swap_with(target: InventorySlot) -> bool:
	if equipment == null or _doll_drag_from < 0: return false
	var it := target.item as ItemEquipment
	if it == null: return false
	return equipment.allowed_slots(it).has(_doll_drag_from) and equipment.can_equip(it)

## Положили в пустое место сетки.
func _on_external_placed(origin: Vector2i, rotated: bool) -> void:
	if _doll_drag_from < 0 or equipment == null: return
	var from := _doll_drag_from
	_doll_drag_from = -1
	var item := equipment.unequip(from)
	if item == null: return
	if not _place_at(item, origin, rotated):
		if inventory.add_item(item, 1) > 0:
			_drop_to_world(item, 1)

## Бросили на предмет в сетке -> меняем местами.
func _on_external_swap(target: InventorySlot, rotated: bool) -> void:
	if _doll_drag_from < 0 or equipment == null: return
	var from := _doll_drag_from
	_doll_drag_from = -1
	var incoming := target.item as ItemEquipment
	if incoming == null: return
	var t_origin : Vector2i = target.origin
	var t_rotated : bool = target.rotated
	inventory.remove(target)
	var outgoing := equipment.unequip(from)
	_return_removed(equipment.equip(incoming, from))
	if outgoing == null: return
	# Пытаемся положить снятое на место забранного (размеры могут отличаться).
	if not _place_at(outgoing, t_origin, rotated) \
	and not _place_at(outgoing, t_origin, t_rotated):
		if inventory.add_item(outgoing, 1) > 0:
			_drop_to_world(outgoing, 1)

## Отпустили вне сетки: окно контейнера -> ТОЧНО под курсор;
## другой слот куклы -> переложить/своп; иначе — отмена.
func _on_external_dropped_outside(global_pos: Vector2, rotated: bool) -> void:
	if _doll_drag_from < 0 or equipment == null: return
	var from := _doll_drag_from
	_doll_drag_from = -1

	# С куклы в окно контейнера (рюкзак в сундук и т.п.).
	var win := _window_at(global_pos)
	if win and win.ui and win.inventory:
		var it := equipment.unequip(from)
		if it == null: return
		var placed := false
		if win.ui.accepts_item(it) and win.ui.get_global_rect().has_point(global_pos):
			var origin := win.ui.origin_for_drop(it, rotated, global_pos)
			if win.inventory.can_place(it, origin, rotated):
				win.inventory.place(it, origin, rotated, 1)
				placed = true
		if not placed and win.ui.accepts_item(it) \
		and win.inventory.add_item(it, 1) <= 0:
			placed = true
		if not placed:
			_return_removed(equipment.equip(it as ItemEquipment, from))  # не влезло — назад
		return

	if doll == null: return
	var target := doll._slot_at_global(global_pos)
	if target == null or int(target.slot_id) == from:
		return   # отмена — предмет так и висит на кукле
	var dragged := equipment.get_item(from)
	if dragged == null: return
	var occupant := target.get_item()
	if occupant == null:
		if target.can_accept(dragged):
			var d := equipment.unequip(from)
			_return_removed(equipment.equip(d, int(target.slot_id)))
	else:
		# Своп кукла <-> кукла (например, два кольца).
		if equipment.allowed_slots(dragged).has(int(target.slot_id)) \
		and equipment.allowed_slots(occupant).has(from):
			var d := equipment.unequip(from)
			var o := equipment.unequip(int(target.slot_id))
			_return_removed(equipment.equip(d, int(target.slot_id)))
			_return_removed(equipment.equip(o, from))

## Q во время драга с куклы = выбросить в мир.
func _on_external_world_drop() -> void:
	if _doll_drag_from < 0 or equipment == null: return
	var from := _doll_drag_from
	_doll_drag_from = -1
	var item := equipment.unequip(from)
	if item:
		_drop_to_world(item, 1)

## Точная укладка в сетку: добавляем и двигаем в нужную ячейку.
## (Экипировка не стакается, поэтому add_item создаст отдельный слот.)
func _place_at(item: Item, origin: Vector2i, rotated: bool) -> bool:
	if not inventory.can_place(item, origin, rotated):
		return false
	if inventory.add_item(item, 1) > 0:
		return false
	for s in inventory.get_slots():
		if s.item == item:
			inventory.move(s, origin, rotated)
			break
	return true

## ═══════════ ДРАГ ИЗ СЕТКИ ИГРОКА: ОКНО ИЛИ КУКЛА ═══════════

func _on_dropped_outside(slot: InventorySlot, global_pos: Vector2, rotated: bool) -> void:
	# На окно контейнера -> ТОЧНО в ячейку под курсором.
	var win := _window_at(global_pos)
	if win:
		_precise_transfer(slot, inventory, win.ui, global_pos, rotated)
		return
	# На куклу -> надеть.
	if doll == null or equipment == null: return
	var target := doll._slot_at_global(global_pos)
	if target == null: return
	var item := slot.item as ItemEquipment
	if item == null: return
	if not target.can_accept(item): return

	_take_one_from(slot)
	_return_removed(equipment.equip(item, int(target.slot_id)))

## ═══════════ ПКМ ПО ПРЕДМЕТУ: контейнер / перенос / надеть / использовать ═══════════

func _on_slot_activated(slot: InventorySlot) -> void:
	# Открыто окно контейнера -> ПКМ = переложить туда.
	if _active_container_valid():
		_transfer_to_active(slot)
		return
	# ПКМ по рюкзаку/поясу -> открыть его окно (надевается перетаскиванием на куклу).
	if slot.item is ItemContainer:
		var c := slot.item as ItemContainer
		open_container(c.get_inventory(), c.display_name(), null)
		return
	if slot.item is ItemEquipment:
		_equip_from_inventory(slot)
	elif slot.item is ItemConsumable:
		_use_consumable(slot)

func _equip_from_inventory(slot: InventorySlot) -> void:
	if equipment == null or not equipment.can_equip(slot.item):
		return
	var item := slot.item as ItemEquipment
	_take_one_from(slot)
	_return_removed(equipment.equip(item))

func _take_one_from(slot: InventorySlot, inv: Inventory = null) -> void:
	if inv == null:
		inv = inventory
	if slot.quantity > 1:
		slot.quantity -= 1
		inv.changed.emit()
	else:
		inv.remove(slot)

func _return_removed(removed: Array) -> void:
	for r in removed:
		if r == null: continue
		if inventory.add_item(r, 1) > 0:
			_drop_to_world(r, 1)

func _use_consumable(slot: InventorySlot) -> void:
	var c := slot.item as ItemConsumable
	var character := get_parent() as Character
	if character:
		if c.bonus_health.x > 0.0:
			character.heal(c.bonus_health.x)
		if c.bonus_health.y > 0.0:
			character.heal(character.max_health() * c.bonus_health.y / 100.0)
	slot.quantity -= 1
	if slot.quantity <= 0:
		inventory.remove(slot)
	else:
		inventory.changed.emit()

## ═══════════ СНЯТИЕ С КУКЛЫ (ПКМ) ═══════════

func _on_unequip_requested(slot_id: int) -> void:
	if equipment == null: return
	var item := equipment.unequip(slot_id)
	if item == null: return
	if inventory.add_item(item, 1) > 0:
		_drop_to_world(item, 1)

## ═══════════ ВЫБРАСЫВАНИЕ В МИР ═══════════

func _on_drop_requested(slot: InventorySlot) -> void:
	inventory.remove(slot)
	_drop_to_world(slot.item, slot.quantity)

func _drop_to_world(item: Item, qty: int) -> void:
	var body := get_parent() as Node2D
	if body == null or item == null: return
	var pickup := ItemPickup.new()
	pickup.item = item
	pickup.quantity = qty
	pickup.pickup_delay = 1.0
	var holder : Node = get_tree().current_scene if get_tree().current_scene else body.get_parent()
	holder.add_child(pickup)
	pickup.global_position = body.global_position \
		+ Vector2.RIGHT.rotated(randf() * TAU) * (body.collision_radius + 20.0 if body is Character else 24.0)
