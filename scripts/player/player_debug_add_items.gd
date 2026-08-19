extends Window
class_name DebugAddItems

@export var ScrollVBox: VBoxContainer

const BUTTONS_PER_ROW: int = 10
const BUTTON_SIZE: Vector2 = Vector2(32, 32)

var button_group: ButtonGroup = ButtonGroup.new()
var selectedButton: Button

var _current_row: HBoxContainer
var _buttons_in_row: int = 0


func _ready() -> void:
	if !DBLoader:
		return

	# ButtonGroup сам сообщает, какая кнопка нажата
	button_group.pressed.connect(_on_button_group_pressed)

	load_database()

func load_database() -> void:
	clear_selection()

	for child in ScrollVBox.get_children():
		child.queue_free()

	_current_row = null
	_buttons_in_row = 0

	var Items: Dictionary[Array, GDScript] = {
		DBLoader.ItemBase: Item,
		DBLoader.EquipmentBase: ItemEquipment,
		DBLoader.WeaponBase: ItemWeapon,
		DBLoader.ConsumablesBase: ItemConsumable,
		DBLoader.ContainerBase: ItemContainer
	}

	for base: Array in Items:
		var script: GDScript = Items[base]
		for data in base:
			create_button(data, script)


func add_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row_%d" % ScrollVBox.get_child_count()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 2)
	ScrollVBox.add_child(row)
	return row

func create_button(data, script: GDScript) -> Button:
	if _current_row == null or _buttons_in_row >= BUTTONS_PER_ROW:
		_current_row = add_row()
		_buttons_in_row = 0

	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = button_group
	btn.custom_minimum_size = BUTTON_SIZE
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.clip_text = true

	if data.sprite_container != null:
		btn.icon = data.sprite_container

	btn.text = data.name
	btn.tooltip_text = data.get_all_variables_text(false)

	# храним данные прямо в кнопке
	btn.set_meta("item_data", data)
	btn.set_meta("item_script", script)

	_current_row.add_child(btn)
	_buttons_in_row += 1
	return btn

func _on_button_group_pressed(button: BaseButton) -> void:
	selectedButton = button as Button

	var data := button.get_meta("item_data", null) as Item
	var script: GDScript = button.get_meta("item_script", null)

	print("Выбрано: ", data, " (", script, ")")

func get_selected_data() -> Item:
	var pressed := button_group.get_pressed_button()
	if pressed == null:
		return null
	return pressed.get_meta("item_data", null) as Item

func clear_selection() -> void:
	var pressed := button_group.get_pressed_button()
	if pressed:
		pressed.set_pressed_no_signal(false)
	selectedButton = null

func spawn_selected_at(world_position: Vector2, world_parent: Node = null) -> ItemPickup:
	var source := get_selected_data()
	if source == null:
		return null

	if world_parent == null:
		world_parent = get_tree().current_scene
	if world_parent == null:
		return null

	var item_copy := source.duplicate(true) as Item
	if item_copy == null:
		return null

	var spawn_position := world_position
	var nav := get_node_or_null("/root/NavManager")

	if nav and nav.is_initialized():
		var cell: Vector2i = nav.world_to_cell(world_position)
		spawn_position = nav.cell_to_world(cell)
	else:
		var fallback_cell := Vector2i(
			floori(world_position.x / 32.0),
			floori(world_position.y / 32.0)
		)
		spawn_position = Vector2(fallback_cell * Vector2i(32, 32)) + Vector2(16.0, 16.0)

	var pickup := ItemPickup.new()
	pickup.item = item_copy
	pickup.quantity = maxi(item_copy.quantity, 1)
	pickup.pickup_delay = 1.0

	world_parent.add_child(pickup)
	pickup.global_position = spawn_position

	return pickup

func _on_close_requested() -> void:
	hide()
