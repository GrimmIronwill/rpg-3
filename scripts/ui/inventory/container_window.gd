class_name ContainerWindow
extends PanelContainer
## Окно инвентаря контейнера (сундук, рюкзак, пояс).
## ВАЖНО: окно живёт в отдельном CanvasLayer (см. PlayerInventory._window_holder),
## НЕ внутри ui_root — иначе контейнеры-родители перекладывают/растягивают его
## и раздувают custom_minimum_size всего UI (в т.ч. инвентаря игрока).
## ПКМ по предмету -> take_requested (забрать игроку).
## Q над предметом -> world_drop_requested (выбросить в мир).
## Драг из сетки наружу -> slot_dropped_outside (контроллер решает, куда).

signal take_requested(slot: InventorySlot)
signal world_drop_requested(slot: InventorySlot)
signal slot_dropped_outside(slot: InventorySlot, global_pos: Vector2, rotated: bool, window: ContainerWindow)
signal closed(window: ContainerWindow)
signal focused(window: ContainerWindow)

const PAD := 8
const TITLE_H := 26
const MIN_CELL := 16

@export var cell_size : int = 48
@export var auto_close_distance : float = 128.0

var inventory : Inventory
var ui : InventoryUI
var source : Node2D = null

var _watch_source := false
var _drag_win := false
var _drag_off := Vector2.ZERO

func setup(p_inventory: Inventory, p_title: String, p_source: Node2D = null) -> void:
	inventory = p_inventory
	source = p_source
	_watch_source = p_source != null
	mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	add_child(vbox)

	# ── Заголовок: за него окно перетаскивается, X — закрыть ──
	var titlebar := HBoxContainer.new()
	titlebar.custom_minimum_size.y = TITLE_H

	var title_label := Label.new()
	title_label.text = p_title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = Control.MOUSE_FILTER_STOP
	title_label.gui_input.connect(_on_title_input)
	titlebar.add_child(title_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	titlebar.add_child(close_btn)
	vbox.add_child(titlebar)

	# ── Сетка контейнера ──
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PAD)
	margin.add_theme_constant_override("margin_top", PAD)
	margin.add_theme_constant_override("margin_right", PAD)
	margin.add_theme_constant_override("margin_bottom", PAD)

	ui = InventoryUI.new()
	# FIX: большая сетка (гигантский сундук) — ужимаем ячейку, чтобы окно влезло в экран.
	ui.cell_size = _fit_cell_size(p_inventory.grid_size)
	ui.inventory = p_inventory
	margin.add_child(ui)
	vbox.add_child(margin)

	ui.slot_activated.connect(_on_slot_activated)
	ui.drop_requested.connect(_on_drop_requested)
	ui.dropped_outside.connect(_on_slot_dropped_outside)

	reset_size()

## Подбор размера ячейки, чтобы окно гарантированно помещалось в экран.
func _fit_cell_size(gsize: Vector2i) -> int:
	var vp := get_viewport().get_visible_rect().size
	var avail := vp - Vector2(PAD * 2 + 24, PAD * 2 + TITLE_H + 32)
	var fit := mini(
		int(avail.x / maxf(gsize.x, 1.0)),
		int(avail.y / maxf(gsize.y, 1.0)))
	return clampi(mini(fit, cell_size), MIN_CELL, cell_size)

func _on_slot_activated(slot: InventorySlot) -> void:
	take_requested.emit(slot)

func _on_drop_requested(slot: InventorySlot) -> void:
	world_drop_requested.emit(slot)

func _on_slot_dropped_outside(slot: InventorySlot, global_pos: Vector2, rotated: bool) -> void:
	slot_dropped_outside.emit(slot, global_pos, rotated, self)

## ── Перетаскивание окна за заголовок ──

func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag_win = event.pressed
		_drag_off = get_global_mouse_position() - global_position

## ── Клик по окну = поднять наверх и сделать активным ──

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
	and get_global_rect().has_point(get_global_mouse_position()):
		move_to_front()
		focused.emit(self)

func _process(_delta: float) -> void:
	if _drag_win:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			global_position = get_global_mouse_position() - _drag_off
		else:
			_drag_win = false   # отпустили мышь вне заголовка
	_clamp_to_screen()
	_check_source()

func close() -> void:
	if not is_inside_tree(): return
	closed.emit(self)
	queue_free()

## ═══════════ ВСЕГДА В ПРЕДЕЛАХ ЭКРАНА ═══════════

func _clamp_to_screen() -> void:
	var vp := get_viewport().get_visible_rect().size
	global_position = Vector2(
		clampf(global_position.x, 0.0, maxf(vp.x - size.x, 0.0)),
		clampf(global_position.y, 0.0, maxf(vp.y - size.y, 0.0)))

## ═══════════ СЛЕЖЕНИЕ ЗА ВЛАДЕЛЬЦЕМ ═══════════

func _check_source() -> void:
	if not _watch_source: return
	if source == null or not is_instance_valid(source):
		close()   # сундук уничтожили
		return
	if auto_close_distance > 0.0:
		var pl := get_tree().get_first_node_in_group("player") as Node2D
		if pl and pl.global_position.distance_to(source.global_position) > auto_close_distance:
			close()   # игрок ушёл
