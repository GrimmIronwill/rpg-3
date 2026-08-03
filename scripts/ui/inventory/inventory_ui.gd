@tool
class_name InventoryUI
extends MarginContainer

signal slot_activated(slot: InventorySlot)   # ПКМ по предмету в сетке
signal drop_requested(slot: InventorySlot)   # ЯВНЫЙ выброс в мир (только Q)
signal dropped_outside(slot: InventorySlot, global_pos: Vector2, rotated: bool)  # отпустили вне сетки
signal drag_started(item: Item)              # для подсветки куклы и других сеток
signal drag_ended
signal drag_rotation_changed(rotated: bool)  # R во время драга — чтобы чужие сетки обновили подсветку

## ── Внешний драг (предмет пришёл извне, например с куклы) ──
signal external_placed(origin: Vector2i, rotated: bool)          # положили в пустое место сетки
signal external_swap_requested(target: InventorySlot, rotated: bool)  # бросили на предмет в сетке
signal external_dropped_outside(global_pos: Vector2, rotated: bool)   # отпустили вне сетки
signal external_world_drop_requested                             # нажали Q во время драга

@export var cell_size : int = 64:
	set(v):
		cell_size = v
		_update_size(); queue_redraw()
@export var grid_size : Vector2i = Vector2i(1, 1):
	set(v):
		grid_size = v
		_update_size(); queue_redraw()

const COL_BG   := Color(0, 0, 0, 0.35)
const COL_GRID := Color(1, 1, 1, 0.15)
const COL_SLOT := Color(1, 1, 1, 0.07)
const COL_OK   := Color(0.3, 1.0, 0.3, 0.35)
const COL_BAD  := Color(1.0, 0.3, 0.3, 0.35)

var inventory : Inventory:
	set(v):
		if inventory and inventory.changed.is_connected(queue_redraw):
			inventory.changed.disconnect(queue_redraw)
		inventory = v
		if inventory:
			grid_size = inventory.grid_size
			inventory.changed.connect(queue_redraw)
		queue_redraw()

var _drag_slot : InventorySlot = null
var _drag_rotated := false
var _drag_offset := Vector2i.ZERO   # ячейка предмета, за которую "взяли"
var _mouse_pos := Vector2.ZERO

## Состояние внешнего драга. _ext_swap_check — Callable(target: InventorySlot) -> bool,
## контроллер решает, можно ли поменяться местами с предметом в сетке.
var _ext_item : Item = null
var _ext_rotated := false
var _ext_swap_check := Callable()

## Ховер-превью: предмет, который сейчас тащат из ДРУГОЙ сетки/окна.
## Контроллер (PlayerInventory) раздаёт его всем сеткам при начале драга.
var _hover_item : Item = null
var _hover_rotated := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_size()

func is_dragging() -> bool:
	return _drag_slot != null or _ext_item != null

## ВАЖНО: _gui_input получает движение мыши только ВНУТРИ контрола.
## Поэтому во время перетаскивания (и чужого драга) следим за мышью каждый кадр.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	if is_dragging() or _hover_item != null:
		_mouse_pos = get_local_mouse_position()
		queue_redraw()

func _update_size() -> void:
	custom_minimum_size = Vector2(grid_size) * cell_size

func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / cell_size)), int(floor(pos.y / cell_size)))

## Origin перетаскиваемого предмета, ЗАЖАТЫЙ в границы сетки.
func _drag_origin() -> Vector2i:
	var s := inventory.item_size(_drag_slot.item, _drag_rotated)
	var origin := _cell_at(_mouse_pos) - _drag_offset
	return _clamp_origin(origin, s)

## Внешний предмет держим за центр.
func _ext_origin() -> Vector2i:
	var s := inventory.item_size(_ext_item, _ext_rotated)
	var origin := _cell_at(_mouse_pos) - Vector2i((s.x - 1) / 2, (s.y - 1) / 2)
	return _clamp_origin(origin, s)

func _clamp_origin(origin: Vector2i, s: Vector2i) -> Vector2i:
	origin.x = clampi(origin.x, 0, maxi(grid_size.x - s.x, 0))
	origin.y = clampi(origin.y, 0, maxi(grid_size.y - s.y, 0))
	return origin

func _mouse_inside_grid() -> bool:
	return Rect2(Vector2.ZERO, Vector2(grid_size) * cell_size).has_point(_mouse_pos)

## Клавиша без привязки к раскладке (fix: на RU-раскладке keycode != KEY_R).
func _key_of(event: InputEventKey) -> Key:
	return event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode

## ── Публичный API для кросс-сеточного драга ──

## Ячейка сетки под глобальной позицией курсора.
func cell_from_global(global_pos: Vector2) -> Vector2i:
	return _cell_at(global_pos - global_position)

## Origin для укладки предмета "за центр" в точке global_pos (зажат в сетку).
func origin_for_drop(item: Item, rotated: bool, global_pos: Vector2) -> Vector2i:
	if inventory == null or item == null:
		return Vector2i.ZERO
	var s := inventory.item_size(item, rotated)
	var origin := cell_from_global(global_pos) - Vector2i((s.x - 1) / 2, (s.y - 1) / 2)
	return _clamp_origin(origin, s)

## Подсветка чужого драга: item = null — выключить.
func set_hover_preview(item: Item, rotated := false) -> void:
	_hover_item = item
	_hover_rotated = rotated
	queue_redraw()

## Пропускает ли фильтр инвентаря предмет.
func accepts_item(item: Item) -> bool:
	if inventory is FilteredInventory:
		return (inventory as FilteredInventory).accepts(item)
	return item != null

func _can_stack_into(item: Item, target: InventorySlot) -> bool:
	var max_stack := maxi(target.item.max_stack, 1)
	return _same_item(item, target.item) and max_stack > 1 and target.quantity < max_stack

func _same_item(a: Item, b: Item) -> bool:
	return a == b or (a.id != "" and a.id == b.id)

## --- внешний драг: публичный API ---

## Контроллер (PlayerInventory) вызывает это, когда игрок взял предмет с куклы.
func begin_external_drag(item: Item, swap_check := Callable()) -> void:
	if item == null or is_dragging() or inventory == null:
		return
	_ext_item = item
	_ext_rotated = false
	_ext_swap_check = swap_check
	queue_redraw()
	drag_started.emit(item)   # кукла и другие сетки подсветятся

func _end_external_drag() -> void:
	_ext_item = null
	_ext_swap_check = Callable()
	queue_redraw()
	drag_ended.emit()

## --- тултип ---

func _get_tooltip(at_position: Vector2) -> String:
	if Engine.is_editor_hint() or inventory == null: return ""
	if is_dragging() or _hover_item: return ""
	var slot := inventory.slot_at(_cell_at(at_position))
	return ItemTooltip.build(slot.item) if slot else ""

## --- ввод ---

func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or inventory == null: return
	if event is InputEventMouseMotion:
		_mouse_pos = event.position
		if is_dragging() or _hover_item: queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		_mouse_pos = event.position
		if _ext_item:
			match event.button_index:
				MOUSE_BUTTON_LEFT:  _try_external_drop()
				MOUSE_BUTTON_RIGHT: _end_external_drag()   # отмена, предмет остаётся на кукле
			accept_event()
			return
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _drag_slot: _try_drop()
				else: _try_pick()
			MOUSE_BUTTON_RIGHT:
				if _drag_slot:
					_end_drag()
				else:
					var s := inventory.slot_at(_cell_at(_mouse_pos))
					if s: slot_activated.emit(s)
		accept_event()

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or inventory == null: return
	if not is_visible_in_tree(): return

	# ── Внешний драг: клики вне сетки ──
	if _ext_item and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# ПКМ где угодно = отмена (и до слотов куклы клик не дойдёт).
			_end_external_drag()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT \
		and not get_global_rect().has_point(get_global_mouse_position()):
			# Отпустили вне сетки: контроллер решит — окно, слот куклы или отмена.
			var rot := _ext_rotated
			_end_external_drag()
			external_dropped_outside.emit(get_global_mouse_position(), rot)
			get_viewport().set_input_as_handled()
			return

	# ── Внутренний драг: ЛКМ вне сетки -> решает контроллер (окно/кукла/отмена) ──
	if _drag_slot and event is InputEventMouseButton and event.pressed \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and not get_global_rect().has_point(get_global_mouse_position()):
		var s := _drag_slot
		var rot := _drag_rotated
		_end_drag()
		dropped_outside.emit(s, get_global_mouse_position(), rot)
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match _key_of(event):
		KEY_R:
			if _ext_item:
				_ext_rotated = not _ext_rotated
				drag_rotation_changed.emit(_ext_rotated)
				queue_redraw()
				get_viewport().set_input_as_handled()
			elif _drag_slot:
				_drag_rotated = not _drag_rotated
				_drag_offset = Vector2i(_drag_offset.y, _drag_offset.x)
				drag_rotation_changed.emit(_drag_rotated)
				queue_redraw()
				get_viewport().set_input_as_handled()
		KEY_Q:
			if _ext_item:
				external_world_drop_requested.emit()   # выбросить прямо с куклы
				_end_external_drag()
				get_viewport().set_input_as_handled()
				return
			var s : InventorySlot = _drag_slot
			if s == null and get_global_rect().has_point(get_global_mouse_position()):
				s = inventory.slot_at(_cell_at(get_local_mouse_position()))
			if s:
				if _drag_slot: _end_drag()
				drop_requested.emit(s)
				get_viewport().set_input_as_handled()

func _end_drag() -> void:
	_drag_slot = null
	queue_redraw()
	drag_ended.emit()

func _try_pick() -> void:
	var slot := inventory.slot_at(_cell_at(_mouse_pos))
	if slot == null: return
	_drag_slot = slot
	_drag_rotated = slot.rotated
	_drag_offset = _cell_at(_mouse_pos) - slot.origin
	queue_redraw()
	drag_started.emit(slot.item)

func _try_drop() -> void:
	var target := inventory.slot_at(_cell_at(_mouse_pos))
	if target and inventory.can_stack(_drag_slot, target):
		if inventory.merge(_drag_slot, target) == 0:
			_end_drag()
		return
	if inventory.move(_drag_slot, _drag_origin(), _drag_rotated):
		_end_drag()

## Бросок внешнего предмета внутри сетки: либо своп с предметом под курсором,
## либо укладка в пустое место. Если нельзя — драг продолжается.
func _try_external_drop() -> void:
	var target := inventory.slot_at(_cell_at(_mouse_pos))
	if target:
		if _ext_swap_check.is_valid() and _ext_swap_check.call(target):
			external_swap_requested.emit(target, _ext_rotated)
			_end_external_drag()
		return
	var origin := _ext_origin()
	if inventory.can_place(_ext_item, origin, _ext_rotated):
		external_placed.emit(origin, _ext_rotated)
		_end_external_drag()

## --- отрисовка ---

func _font() -> Font:
	var f := get_theme_default_font()
	return f if f != null else ThemeDB.fallback_font

func _draw() -> void:
	var px := Vector2(grid_size) * cell_size
	draw_rect(Rect2(Vector2.ZERO, px), COL_BG)
	for x in grid_size.x + 1:
		draw_line(Vector2(x * cell_size, 0), Vector2(x * cell_size, px.y), COL_GRID)
	for y in grid_size.y + 1:
		draw_line(Vector2(0, y * cell_size), Vector2(px.x, y * cell_size), COL_GRID)

	if inventory == null: return
	var font := _font()

	for slot in inventory.get_slots():
		if slot == _drag_slot: continue
		var s := inventory.item_size(slot.item, slot.rotated)
		var rect := Rect2(Vector2(slot.origin) * cell_size, Vector2(s) * cell_size)
		draw_rect(rect, COL_SLOT)
		_draw_item(slot.item, rect, slot.rotated, Color.WHITE)
		_draw_quantity(font, rect, slot.quantity)

	if _drag_slot:
		var s = inventory.item_size(_drag_slot.item, _drag_rotated)
		if _mouse_inside_grid():
			var origin := _drag_origin()
			var ok = inventory.can_place(_drag_slot.item, origin, _drag_rotated, _drag_slot)
			draw_rect(Rect2(Vector2(origin) * cell_size, Vector2(s) * cell_size),
				COL_OK if ok else COL_BAD)
		_draw_drag_preview(_drag_slot.item, s, _drag_slot.quantity, _drag_rotated, font)

	if _ext_item:
		var s = inventory.item_size(_ext_item, _ext_rotated)
		if _mouse_inside_grid():
			var target := inventory.slot_at(_cell_at(_mouse_pos))
			if target:
				# Курсор над предметом: подсвечиваем ЕГО — зелёным, если своп возможен.
				var can_swap = _ext_swap_check.is_valid() and _ext_swap_check.call(target)
				var ts := inventory.item_size(target.item, target.rotated)
				draw_rect(Rect2(Vector2(target.origin) * cell_size, Vector2(ts) * cell_size),
					COL_OK if can_swap else COL_BAD)
			else:
				var origin := _ext_origin()
				var ok = inventory.can_place(_ext_item, origin, _ext_rotated)
				draw_rect(Rect2(Vector2(origin) * cell_size, Vector2(s) * cell_size),
					COL_OK if ok else COL_BAD)
		_draw_drag_preview(_ext_item, s, 1, _ext_rotated, font)

	# ── Ховер чужого драга (тащат из другой сетки/окна) ──
	if _hover_item and not is_dragging() and _mouse_inside_grid():
		var s = inventory.item_size(_hover_item, _hover_rotated)
		var target := inventory.slot_at(_cell_at(_mouse_pos))
		if target:
			var ok := accepts_item(_hover_item) and _can_stack_into(_hover_item, target)
			var ts := inventory.item_size(target.item, target.rotated)
			draw_rect(Rect2(Vector2(target.origin) * cell_size, Vector2(ts) * cell_size),
				COL_OK if ok else COL_BAD)
		else:
			var origin := _clamp_origin(
				_cell_at(_mouse_pos) - Vector2i((s.x - 1) / 2, (s.y - 1) / 2), s)
			var ok := accepts_item(_hover_item) \
				and inventory.can_place(_hover_item, origin, _hover_rotated)
			draw_rect(Rect2(Vector2(origin) * cell_size, Vector2(s) * cell_size),
				COL_OK if ok else COL_BAD)

func _draw_drag_preview(item: Item, s: Vector2i, qty: int, rotated: bool, font: Font) -> void:
	var rect := Rect2(_mouse_pos - Vector2(s) * cell_size * 0.5, Vector2(s) * cell_size)
	_draw_item(item, rect, rotated, Color(1, 1, 1, 0.75))
	_draw_quantity(font, rect, qty)

func _draw_quantity(font: Font, rect: Rect2, q: int) -> void:
	if q <= 1: return
	var pos := rect.position + Vector2(5, rect.size.y - 6)
	draw_string_outline(font, pos, str(q), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color.BLACK)
	draw_string(font, pos, str(q), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

func _draw_item(item: Item, rect: Rect2, rotated: bool, tint: Color) -> void:
	rect = Rect2(
		rect.position.x + 8, rect.position.y + 8,
		rect.size.x - 16, rect.size.y - 16
	)
	var tex : Texture2D = item.sprite_container
	if tex == null:
		draw_rect(rect.grow(-2), Color(0.4, 0.5, 0.8, 0.6))
		return
	if rotated:
		draw_set_transform(rect.position + Vector2(rect.size.x, 0), PI * 0.5)
		draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(rect.size.y, rect.size.x)), false, tint)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect(tex, rect, false, tint)
