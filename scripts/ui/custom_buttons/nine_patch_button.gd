@tool
extends NinePatchRect
class_name NinePatchButton

signal button_pressed
signal button_toggled(is_pressed: bool)

@export_group("Textures")
@export var BaseTexture: Texture2D:
	set(value):
		BaseTexture = value
		if _state == ButtonStates.IDLE:
			texture = value

@export var HoverTexture: Texture2D
@export var PressedTexture: Texture2D
@export var DisabledTexture: Texture2D

@export_group("Behavior")
@export var toggle_mode: bool = false

@export var disabled: bool = false:
	set(value):
		set_disabled(value)
	get:
		return _disabled

@export_group("Label")
@export var text: String = "":
	set(value):
		text = value
		if _label:
			_label.text = value

@export var font_color: Color = Color.WHITE:
	set(value):
		font_color = value
		if _label:
			_label.add_theme_color_override("font_color", value)

@export var font_size: int = 16:
	set(value):
		font_size = value
		if _label:
			_label.add_theme_font_size_override("font_size", value)

@export var HAlign : HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER:
	set(value):
		HAlign = value
		if _label:
			_label.horizontal_alignment = value

@export var VAlign : VerticalAlignment = VERTICAL_ALIGNMENT_CENTER:
	set(value):
		VAlign = value
		if _label:
			_label.vertical_alignment = value

enum ButtonStates {
	IDLE,
	HOVER,
	PRESSED,
	DISABLED,
}

var _state: ButtonStates = ButtonStates.IDLE
var _disabled: bool = false
var _pressed: bool = false
var _label: Label
var _is_hovered: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	patch_margin_left = 23
	patch_margin_right = 23
	patch_margin_top = 9
	patch_margin_bottom = 9


func _ready() -> void:
	_setup_label()
	_connect_signals()
	set_disabled(_disabled)
	_apply_texture_for_state()


func _setup_label() -> void:
	for child in get_children():
		if child is Label and child.name == &"ButtonLabel":
			_label = child
			break

	if _label == null:
		_label = Label.new()
		_label.name = &"ButtonLabel"
		add_child(_label)

	_label.horizontal_alignment = HAlign
	_label.vertical_alignment = VAlign
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = text
	_label.add_theme_color_override("font_color", font_color)
	_label.add_theme_font_size_override("font_size", font_size)

	_label.anchor_left = 0.0
	_label.anchor_top = 0.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 0.0
	_label.offset_top = 0.0
	_label.offset_right = 0.0
	_label.offset_bottom = 0.0


func _connect_signals() -> void:
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)

	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)

	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)


func set_disabled(value: bool) -> void:
	_disabled = value

	if _disabled:
		_change_state(ButtonStates.DISABLED)
	else:
		if toggle_mode and _pressed:
			_change_state(ButtonStates.PRESSED)
		elif _is_hovered:
			_change_state(ButtonStates.HOVER)
		else:
			_change_state(ButtonStates.IDLE)


func is_disabled() -> bool:
	return _disabled


func set_pressed_no_signal(value: bool) -> void:
	_pressed = value

	if _disabled:
		_change_state(ButtonStates.DISABLED)
		return

	if toggle_mode and _pressed:
		_change_state(ButtonStates.PRESSED)
	elif _is_hovered:
		_change_state(ButtonStates.HOVER)
	else:
		_change_state(ButtonStates.IDLE)


func is_button_pressed() -> bool:
	return _pressed


func _on_gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if _disabled:
		return

	if not (event is InputEventMouseButton):
		return

	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return

	if toggle_mode:
		_handle_toggle_input(mb)
	else:
		_handle_normal_input(mb)


func _handle_normal_input(mb: InputEventMouseButton) -> void:
	if mb.pressed:
		_change_state(ButtonStates.PRESSED)
	else:
		if _is_hovered:
			_change_state(ButtonStates.HOVER)
			button_pressed.emit()
		else:
			_change_state(ButtonStates.IDLE)


func _handle_toggle_input(mb: InputEventMouseButton) -> void:
	if not mb.pressed:
		return

	_pressed = not _pressed

	if _pressed:
		_change_state(ButtonStates.PRESSED)
		button_pressed.emit()
	else:
		if _is_hovered:
			_change_state(ButtonStates.HOVER)
		else:
			_change_state(ButtonStates.IDLE)

	button_toggled.emit(_pressed)


func _change_state(new_state: ButtonStates) -> void:
	if _state == new_state:
		return

	_state = new_state
	_apply_texture_for_state()


func _apply_texture_for_state() -> void:
	match _state:
		ButtonStates.IDLE:
			texture = BaseTexture

		ButtonStates.HOVER:
			texture = HoverTexture if HoverTexture else BaseTexture

		ButtonStates.PRESSED:
			texture = PressedTexture if PressedTexture else BaseTexture

		ButtonStates.DISABLED:
			texture = DisabledTexture if DisabledTexture else BaseTexture

	modulate.a = 0.55 if _disabled and DisabledTexture == null else 1.0


func _on_mouse_entered() -> void:
	_is_hovered = true

	if _disabled:
		return

	if toggle_mode and _pressed:
		return

	if _state != ButtonStates.PRESSED:
		_change_state(ButtonStates.HOVER)


func _on_mouse_exited() -> void:
	_is_hovered = false

	if _disabled:
		return

	if toggle_mode and _pressed:
		return

	if _state != ButtonStates.PRESSED:
		_change_state(ButtonStates.IDLE)
