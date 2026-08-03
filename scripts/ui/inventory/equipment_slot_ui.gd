@tool
class_name EquipmentSlotUI
extends Control
## Один слот куклы. ЛКМ по занятому слоту = начать перетаскивание,
## ПКМ = снять предмет в инвентарь, СКМ = открыть контейнер (рюкзак/пояс).

signal unequip_requested(slot_id: int)
signal drag_requested(slot_id: int)   # взяли предмет со слота ЛКМ-ом
signal open_requested(slot_id: int)   # НОВОЕ: СКМ — открыть надетый контейнер

@export var slot_id : GameEnums.EquipSlot = GameEnums.EquipSlot.HEAD_PRIMARY:
	set(v):
		slot_id = v
		queue_redraw()

@export var cell_size : int = 52:
	set(v):
		cell_size = v
		custom_minimum_size = Vector2(v, v)
		queue_redraw()

const COL_SLOT  := Color(1, 1, 1, 0.08)
const COL_EDGE  := Color(1, 1, 1, 0.25)
const COL_FULL  := Color(0.5, 0.8, 1.0, 0.15)
const COL_HOVER := Color(1, 1, 0.5, 0.25)
const COL_OK  := Color(0.3, 1.0, 0.3, 0.30)
const COL_BAD := Color(1.0, 0.3, 0.3, 0.30)

## Предмет, который сейчас тащат (null — перетаскивания нет).
var preview_item : Item = null:
	set(v):
		preview_item = v
		queue_redraw()

## Подходит ли предмет в этот слот (учитывает и слот, и требования по атрибутам).
func can_accept(item: Item) -> bool:
	if equipment == null or item == null:
		return false
	if not equipment.allowed_slots(item).has(int(slot_id)):
		return false
	return equipment.can_equip(item)

var equipment : PlayerEquipment:
	set(v):
		if equipment and equipment.changed.is_connected(queue_redraw):
			equipment.changed.disconnect(queue_redraw)
		equipment = v
		if equipment:
			equipment.changed.connect(queue_redraw)
		queue_redraw()

var _hover := false

func _ready() -> void:
	custom_minimum_size = Vector2(cell_size, cell_size)
	if size == Vector2.ZERO:
		size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())

func get_item() -> Item:
	return equipment.get_item(slot_id) if equipment else null

## Тултип: имя + статы предмета, либо название слота, если он пуст.
func _get_tooltip(_at_position: Vector2) -> String:
	if Engine.is_editor_hint(): return ""
	if preview_item: return ""   # во время драга тултип не нужен
	var it := get_item()
	if it:
		return ItemTooltip.build(it)
	return GameEnums.equip_slot_label(slot_id)

func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if get_item() != null:
				drag_requested.emit(int(slot_id))
				accept_event()
		MOUSE_BUTTON_RIGHT:
			if get_item() != null:
				unequip_requested.emit(slot_id)
			accept_event()
		MOUSE_BUTTON_MIDDLE:
			if get_item() is ItemContainer:
				open_requested.emit(int(slot_id))
			accept_event()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var it := get_item()
	draw_rect(r, COL_FULL if it else COL_SLOT)
	if _hover:
		draw_rect(r, COL_HOVER)
	draw_rect(r, COL_EDGE, false, 1.0)

	if it:
		if it.sprite_container:
			draw_texture_rect(it.sprite_container, r.grow(-4), false)
		else:
			draw_rect(r.grow(-6), Color(0.4, 0.5, 0.8, 0.7))
	else:
		var f := get_theme_default_font()
		if f == null: f = ThemeDB.fallback_font
		draw_string(f, Vector2(3, 12),
			GameEnums.equip_slot_label(slot_id).left(6),
			HORIZONTAL_ALIGNMENT_LEFT, int(size.x) - 4, 8, Color(1, 1, 1, 0.35))

	# Зелёная/красная подсветка во время драга.
	if preview_item:
		draw_rect(r, COL_OK if can_accept(preview_item) else COL_BAD)
