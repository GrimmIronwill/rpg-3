@tool
extends Window
class_name DictionaryEditorDialog
## Редактор Dictionary с учётом типов (отображение ключ → значение).
##   key   ← field.dict_key_type   (+ dict_key_enum_values для enum-ключей)
##   value ← field.dict_value_type (+ enum_values / array_element_type / nested_schema_name)

signal confirmed_dictionary(result: Dictionary)

var _field_def: DBFieldDef = null
var _database: DBDatabase = null
var _data: Dictionary = {}
var _keys: Array = []
var _selected_idx: int = -1
var _ui_built: bool = false

var _current_key: Variant = null
var _current_value: Variant = null
var _val_color: Color = Color.WHITE

# UI
var _item_list: ItemList
var _type_label: Label
var _key_host: HBoxContainer
var _value_host: HBoxContainer
var _add_btn: Button
var _update_btn: Button
var _remove_btn: Button

# виджеты ключа
var _k_line: LineEdit = null
var _k_spin: SpinBox = null
var _k_check: CheckBox = null
var _k_enum: OptionButton = null

# виджеты значения
var _v_line: LineEdit = null
var _v_spin: SpinBox = null
var _v_check: CheckBox = null
var _v_enum: OptionButton = null
var _v_vx: SpinBox = null
var _v_vy: SpinBox = null
var _v_vz: SpinBox = null
var _v_color_btn: Button = null
var _v_complex_btn: Button = null   # array / nested object

var _child_dialog: Window = null

# ──────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true
	title = "Dictionary Editor"
	min_size = Vector2i(520, 540)
	if not close_requested.is_connected(_on_cancel):
		close_requested.connect(_on_cancel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	_type_label = Label.new()
	_type_label.text = "Entries:"
	vbox.add_child(_type_label)

	_item_list = ItemList.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.custom_minimum_size.y = 220
	_item_list.item_selected.connect(_on_item_selected)
	vbox.add_child(_item_list)

	vbox.add_child(HSeparator.new())

	var key_lbl := Label.new(); key_lbl.text = "Key:"
	vbox.add_child(key_lbl)
	_key_host = HBoxContainer.new()
	_key_host.add_theme_constant_override("separation", 4)
	vbox.add_child(_key_host)

	var val_lbl := Label.new(); val_lbl.text = "Value:"
	vbox.add_child(val_lbl)
	_value_host = HBoxContainer.new()
	_value_host.add_theme_constant_override("separation", 4)
	vbox.add_child(_value_host)

	var act_row := HBoxContainer.new()
	vbox.add_child(act_row)
	_add_btn = Button.new(); _add_btn.text = "+ Add / Set"
	_add_btn.tooltip_text = "Добавить пару (или перезаписать значение существующего ключа)"
	_add_btn.pressed.connect(_on_add)
	act_row.add_child(_add_btn)
	_update_btn = Button.new(); _update_btn.text = "✎ Update"
	_update_btn.tooltip_text = "Заменить выбранную пару (ключ + значение)"
	_update_btn.pressed.connect(_on_update)
	act_row.add_child(_update_btn)
	_remove_btn = Button.new(); _remove_btn.text = "− Remove"
	_remove_btn.pressed.connect(_on_remove)
	act_row.add_child(_remove_btn)

	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(sp)
	var cancel_btn := Button.new(); cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)
	var ok_btn := Button.new(); ok_btn.text = "OK"
	ok_btn.pressed.connect(_on_ok)
	btn_row.add_child(ok_btn)

# ──────────────────────────────────────────────────────────────────────────────
# Публичный API
# ──────────────────────────────────────────────────────────────────────────────

func open(d: Dictionary, field: DBFieldDef, db: DBDatabase = null) -> void:
	_build_ui()
	_field_def = field
	_database  = db
	_data      = d.duplicate(true)
	_keys      = _data.keys()
	_selected_idx = -1
	title = "Dictionary Editor — %s" % (field.field_name if field else "dict")
	_type_label.text = "Entries  (%s → %s):" % [_key_type_label(), _value_type_label()]
	_type_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_type_label.custom_minimum_size.x = 0
	_rebuild_key_editor()
	_rebuild_value_editor()
	_current_key   = _default_key()
	_current_value = _default_value()
	_write_key_editor(_current_key)
	_write_value_editor(_current_value)
	_refresh_list()
	popup_centered()

# ──────────────────────────────────────────────────────────────────────────────
# Помощники типов
# ──────────────────────────────────────────────────────────────────────────────

func _key_type() -> int:
	return _field_def.dict_key_type if _field_def else DBFieldDef.FieldType.STRING

func _value_type() -> int:
	return _field_def.dict_value_type if _field_def else DBFieldDef.FieldType.STRING

func _key_field() -> DBFieldDef:
	var fd := DBFieldDef.new()
	fd.field_type = _key_type()
	if _field_def:
		fd.enum_values = _field_def.dict_key_enum_values
	return fd

func _value_field() -> DBFieldDef:
	var fd := DBFieldDef.new()
	fd.field_type = _value_type()
	if _field_def:
		fd.enum_values        = _field_def.enum_values
		fd.array_element_type = _field_def.array_element_type
		fd.resource_type_hint = _field_def.resource_type_hint
		fd.nested_schema_name = _field_def.nested_schema_name
	return fd

func _coerce_key(v: Variant) -> Variant:   return _key_field().coerce(v)
func _coerce_value(v: Variant) -> Variant: return _value_field().coerce(v)
func _default_key() -> Variant:            return _key_field().get_default()
func _default_value() -> Variant:          return _value_field().get_default()
func _key_type_label() -> String:          return _key_field().get_type_label()
func _value_type_label() -> String:        return _value_field().get_type_label()

func _format_key(k: Variant) -> String:
	if _key_type() == DBFieldDef.FieldType.ENUM and _field_def and k is int \
			and k >= 0 and k < _field_def.dict_key_enum_values.size():
		return _field_def.dict_key_enum_values[k]
	return DBFieldDef.format_value_for_display(k)

func _format_value(v: Variant) -> String:
	match _value_type():
		DBFieldDef.FieldType.ENUM:
			if _field_def and v is int and v >= 0 and v < _field_def.enum_values.size():
				return _field_def.enum_values[v]
			return str(v)
		DBFieldDef.FieldType.COLOR:
			return (v as Color).to_html(true) if v is Color else str(v)
		DBFieldDef.FieldType.ARRAY:
			return "[Array: %d]" % (v as Array).size() if v is Array else "[]"
		DBFieldDef.FieldType.NESTED_OBJECT:
			return "{Object: %d}" % (v as Dictionary).size() if v is Dictionary else "{}"
		_:
			return DBFieldDef.format_value_for_display(v)

# ──────────────────────────────────────────────────────────────────────────────
# Редактор ключа
# ──────────────────────────────────────────────────────────────────────────────

func _rebuild_key_editor() -> void:
	for c in _key_host.get_children():
		_key_host.remove_child(c); c.queue_free()
	_k_line = null; _k_spin = null; _k_check = null; _k_enum = null

	match _key_type():
		DBFieldDef.FieldType.INT:
			_k_spin = _make_spin(1, false)
			_k_spin.value_changed.connect(func(v): _current_key = int(v))
			_key_host.add_child(_k_spin)
		DBFieldDef.FieldType.FLOAT:
			_k_spin = _make_spin(0.001, true)
			_k_spin.value_changed.connect(func(v): _current_key = v)
			_key_host.add_child(_k_spin)
		DBFieldDef.FieldType.BOOL:
			_k_check = CheckBox.new(); _k_check.text = "true / false"
			_k_check.toggled.connect(func(b): _current_key = b)
			_key_host.add_child(_k_check)
		DBFieldDef.FieldType.ENUM:
			_k_enum = OptionButton.new()
			_k_enum.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_k_enum.search_bar_enabled = true
			if _field_def and _field_def.dict_key_enum_values.size() > 0:
				for ev in _field_def.dict_key_enum_values:
					_k_enum.add_item(ev)
			else:
				_k_enum.add_item("(no enum values)")
			_k_enum.item_selected.connect(func(idx): _current_key = idx)
			_key_host.add_child(_k_enum)
		DBFieldDef.FieldType.RESOURCE_REF:
			_k_line = LineEdit.new()
			_k_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_k_line.placeholder_text = "res://…"
			_k_line.text_changed.connect(func(t): _current_key = t)
			_key_host.add_child(_k_line)

			var browse := Button.new()
			browse.text = "Browse…"
			browse.tooltip_text = "Choose resource key"
			browse.pressed.connect(_on_browse_key_resource)
			_key_host.add_child(browse)
		_:
			_k_line = LineEdit.new()
			_k_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_k_line.placeholder_text = "key…"
			_k_line.text_changed.connect(func(t): _current_key = t)
			_key_host.add_child(_k_line)

func _write_key_editor(v: Variant) -> void:
	_current_key = _coerce_key(v)
	match _key_type():
		DBFieldDef.FieldType.INT, DBFieldDef.FieldType.FLOAT:
			if _k_spin: _k_spin.set_value_no_signal(float(_current_key))

		DBFieldDef.FieldType.BOOL:
			if _k_check: _k_check.set_pressed_no_signal(bool(_current_key))

		DBFieldDef.FieldType.ENUM:
			if _k_enum and _k_enum.item_count > 0:
				_k_enum.selected = clampi(int(_current_key), 0, _k_enum.item_count - 1)

		DBFieldDef.FieldType.STRING, DBFieldDef.FieldType.RESOURCE_REF:
			if _k_line:
				_k_line.text = str(_current_key)

		_:
			if _k_line:
				_k_line.text = str(_current_key)

# ──────────────────────────────────────────────────────────────────────────────
# Редактор значения
# ──────────────────────────────────────────────────────────────────────────────

func _rebuild_value_editor() -> void:
	for c in _value_host.get_children():
		_value_host.remove_child(c); c.queue_free()
	_v_line = null; _v_spin = null; _v_check = null; _v_enum = null
	_v_vx = null; _v_vy = null; _v_vz = null
	_v_color_btn = null; _v_complex_btn = null

	match _value_type():
		DBFieldDef.FieldType.INT:
			_v_spin = _make_spin(1, false)
			_v_spin.value_changed.connect(func(v): _current_value = int(v))
			_value_host.add_child(_v_spin)
		DBFieldDef.FieldType.FLOAT:
			_v_spin = _make_spin(0.001, true)
			_v_spin.value_changed.connect(func(v): _current_value = v)
			_value_host.add_child(_v_spin)
		DBFieldDef.FieldType.BOOL:
			_v_check = CheckBox.new(); _v_check.text = "true / false"
			_v_check.toggled.connect(func(b): _current_value = b)
			_value_host.add_child(_v_check)
		DBFieldDef.FieldType.STRING:
			_v_line = LineEdit.new()
			_v_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_v_line.placeholder_text = "value…"
			_v_line.text_changed.connect(func(t): _current_value = t)
			_value_host.add_child(_v_line)
		DBFieldDef.FieldType.RESOURCE_REF:
			_v_line = LineEdit.new()
			_v_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_v_line.placeholder_text = "res://…"
			_v_line.text_changed.connect(func(t): _current_value = t)
			_value_host.add_child(_v_line)
			var browse := Button.new(); browse.text = "Browse…"
			browse.pressed.connect(_on_browse_resource)
			_value_host.add_child(browse)
		DBFieldDef.FieldType.ENUM:
			_v_enum = OptionButton.new()
			_v_enum.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_v_enum.search_bar_enabled = true
			if _field_def and _field_def.enum_values.size() > 0:
				for ev in _field_def.enum_values:
					_v_enum.add_item(ev)
			else:
				_v_enum.add_item("(no enum values)")
			_v_enum.item_selected.connect(func(idx): _current_value = idx)
			_value_host.add_child(_v_enum)
		DBFieldDef.FieldType.VECTOR2:
			_value_host.add_child(_axis_label("X"))
			_v_vx = _make_spin(0.001, true); _v_vx.value_changed.connect(func(_v): _update_vector())
			_value_host.add_child(_v_vx)
			_value_host.add_child(_axis_label("Y"))
			_v_vy = _make_spin(0.001, true); _v_vy.value_changed.connect(func(_v): _update_vector())
			_value_host.add_child(_v_vy)
		DBFieldDef.FieldType.VECTOR3:
			_value_host.add_child(_axis_label("X"))
			_v_vx = _make_spin(0.001, true); _v_vx.value_changed.connect(func(_v): _update_vector())
			_value_host.add_child(_v_vx)
			_value_host.add_child(_axis_label("Y"))
			_v_vy = _make_spin(0.001, true); _v_vy.value_changed.connect(func(_v): _update_vector())
			_value_host.add_child(_v_vy)
			_value_host.add_child(_axis_label("Z"))
			_v_vz = _make_spin(0.001, true); _v_vz.value_changed.connect(func(_v): _update_vector())
			_value_host.add_child(_v_vz)
		DBFieldDef.FieldType.COLOR:
			_v_color_btn = Button.new()
			_v_color_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_v_color_btn.pressed.connect(_on_pick_color)
			_value_host.add_child(_v_color_btn)
			_style_color_button(_val_color)
		DBFieldDef.FieldType.ARRAY:
			_v_complex_btn = Button.new()
			_v_complex_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_v_complex_btn.pressed.connect(_on_edit_array_value)
			_value_host.add_child(_v_complex_btn)
		DBFieldDef.FieldType.NESTED_OBJECT:
			_v_complex_btn = Button.new()
			_v_complex_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_v_complex_btn.pressed.connect(_on_edit_nested_value)
			_value_host.add_child(_v_complex_btn)
		_:
			_v_line = LineEdit.new()
			_v_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_v_line.text_changed.connect(func(t): _current_value = t)
			_value_host.add_child(_v_line)

func _write_value_editor(v: Variant) -> void:
	_current_value = _coerce_value(v)
	match _value_type():
		DBFieldDef.FieldType.INT, DBFieldDef.FieldType.FLOAT:
			if _v_spin: _v_spin.set_value_no_signal(float(_current_value))
		DBFieldDef.FieldType.BOOL:
			if _v_check: _v_check.set_pressed_no_signal(bool(_current_value))
		DBFieldDef.FieldType.STRING, DBFieldDef.FieldType.RESOURCE_REF:
			if _v_line: _v_line.text = str(_current_value)
		DBFieldDef.FieldType.ENUM:
			if _v_enum and _v_enum.item_count > 0:
				_v_enum.selected = clampi(int(_current_value), 0, _v_enum.item_count - 1)
		DBFieldDef.FieldType.VECTOR2:
			var v2: Vector2 = _current_value if _current_value is Vector2 else Vector2.ZERO
			if _v_vx: _v_vx.set_value_no_signal(v2.x)
			if _v_vy: _v_vy.set_value_no_signal(v2.y)
		DBFieldDef.FieldType.VECTOR3:
			var v3: Vector3 = _current_value if _current_value is Vector3 else Vector3.ZERO
			if _v_vx: _v_vx.set_value_no_signal(v3.x)
			if _v_vy: _v_vy.set_value_no_signal(v3.y)
			if _v_vz: _v_vz.set_value_no_signal(v3.z)
		DBFieldDef.FieldType.COLOR:
			_val_color = _current_value if _current_value is Color else Color.WHITE
			_style_color_button(_val_color)
		DBFieldDef.FieldType.ARRAY:
			if _v_complex_btn:
				var a: Array = _current_value if _current_value is Array else []
				_v_complex_btn.text = "[Array: %d]" % a.size()
		DBFieldDef.FieldType.NESTED_OBJECT:
			if _v_complex_btn:
				var dd: Dictionary = _current_value if _current_value is Dictionary else {}
				_v_complex_btn.text = "{Object: %d fields}" % dd.size()
		_:
			if _v_line: _v_line.text = str(_current_value)

func _update_vector() -> void:
	if _value_type() == DBFieldDef.FieldType.VECTOR3:
		_current_value = Vector3(_v_vx.value, _v_vy.value, _v_vz.value)
	else:
		_current_value = Vector2(_v_vx.value, _v_vy.value)

# ──────────────────────────────────────────────────────────────────────────────
# Работа со списком
# ──────────────────────────────────────────────────────────────────────────────

func _refresh_list() -> void:
	_item_list.clear()
	_keys = _data.keys()
	for k in _keys:
		_item_list.add_item("%s  →  %s" % [_format_key(k), _format_value(_data[k])])
	if _selected_idx >= 0 and _selected_idx < _keys.size():
		_item_list.select(_selected_idx)

func _on_item_selected(idx: int) -> void:
	_selected_idx = idx
	var k: Variant = _keys[idx]
	_write_key_editor(k)
	_write_value_editor(_data[k])

func _on_add() -> void:
	var k: Variant = _coerce_key(_current_key)
	_data[k] = _coerce_value(_current_value)
	_keys = _data.keys()
	_selected_idx = _keys.find(k)
	_refresh_list()

func _on_update() -> void:
	if _selected_idx < 0 or _selected_idx >= _keys.size():
		push_warning("[Dictionary Editor] Сначала выбери пару для обновления.")
		return
	var old_key: Variant = _keys[_selected_idx]
	_data.erase(old_key)
	var new_key: Variant = _coerce_key(_current_key)
	_data[new_key] = _coerce_value(_current_value)
	_keys = _data.keys()
	_selected_idx = _keys.find(new_key)
	_refresh_list()

func _on_remove() -> void:
	var idxs := _item_list.get_selected_items()
	if idxs.is_empty(): return
	_data.erase(_keys[idxs[0]])
	_selected_idx = -1
	_refresh_list()

# ──────────────────────────────────────────────────────────────────────────────
# Редакторы сложных значений
# ──────────────────────────────────────────────────────────────────────────────

func _on_pick_color() -> void:
	_close_child_dialog()
	var dlg := AcceptDialog.new()
	dlg.title = "Pick Color"
	var cp := ColorPicker.new()
	cp.color = _val_color
	dlg.add_child(cp)
	add_child(dlg)
	_child_dialog = dlg
	dlg.popup_centered(Vector2i(380, 440))
	dlg.confirmed.connect(func() -> void:
		_val_color = cp.color
		_current_value = cp.color
		_style_color_button(cp.color)
		_close_child_dialog()
	)
	dlg.canceled.connect(_close_child_dialog)

func _on_browse_resource() -> void:
	_close_child_dialog()
	var dlg := EditorFileDialog.new()
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	if _field_def and not _field_def.resource_type_hint.is_empty():
		dlg.add_filter("*.*", _field_def.resource_type_hint)
	else:
		dlg.add_filter("*.*", "All Resources")
		dlg.add_filter("*.tres,*.res,*.tscn,*.gd", "Godot Resources")
	add_child(dlg)
	_child_dialog = dlg
	dlg.popup_centered(Vector2i(800, 550))
	dlg.file_selected.connect(func(path: String) -> void:
		_current_value = path
		if _v_line: _v_line.text = path
		_close_child_dialog()
	)
	dlg.canceled.connect(_close_child_dialog)

func _on_browse_key_resource() -> void:
	_close_child_dialog()

	var dlg := EditorFileDialog.new()
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE

	# Сейчас resource_type_hint общий для поля.
	# Если он задан, используем его и для ключа Resource Ref.
	if _field_def and not _field_def.resource_type_hint.is_empty():
		dlg.add_filter("*.*", _field_def.resource_type_hint)
	else:
		dlg.add_filter("*.*", "All Resources")
		dlg.add_filter("*.tres,*.res,*.tscn,*.gd", "Godot Resources")

	add_child(dlg)
	_child_dialog = dlg
	dlg.popup_centered(Vector2i(800, 550))

	dlg.file_selected.connect(func(path: String) -> void:
		_current_key = path
		if _k_line:
			_k_line.text = path
		_close_child_dialog()
	)

	dlg.canceled.connect(_close_child_dialog)

func _on_edit_array_value() -> void:
	_close_child_dialog()
	var fd := DBFieldDef.new()
	fd.field_type = DBFieldDef.FieldType.ARRAY
	fd.array_element_type = _field_def.array_element_type if _field_def else DBFieldDef.FieldType.STRING
	fd.enum_values = _field_def.enum_values if _field_def else PackedStringArray()
	var ed := ArrayEditorDialog.new()
	add_child(ed)
	_child_dialog = ed
	ed.confirmed_array.connect(func(result: Array) -> void:
		_current_value = result
		if _v_complex_btn: _v_complex_btn.text = "[Array: %d]" % result.size()
		_close_child_dialog()
	)
	ed.close_requested.connect(_close_child_dialog)
	var cur: Array = _current_value if _current_value is Array else []
	ed.open(cur, fd)

func _on_edit_nested_value() -> void:
	_close_child_dialog()
	var nested_schema: DBSchema = null
	if _database and _field_def and not _field_def.nested_schema_name.is_empty():
		var nt := _database.get_table(_field_def.nested_schema_name)
		if nt: nested_schema = nt.schema
	var ed := NestedObjectEditor.new()
	add_child(ed)
	_child_dialog = ed
	ed.object_confirmed.connect(func(result: Dictionary) -> void:
		_current_value = result
		if _v_complex_btn: _v_complex_btn.text = "{Object: %d fields}" % result.size()
		_close_child_dialog()
	)
	ed.close_requested.connect(_close_child_dialog)
	var cur: Dictionary = _current_value if _current_value is Dictionary else {}
	ed.open(cur, nested_schema, _database)

func _close_child_dialog() -> void:
	if _child_dialog and is_instance_valid(_child_dialog):
		_child_dialog.queue_free()
	_child_dialog = null

# ──────────────────────────────────────────────────────────────────────────────
# OK / Отмена
# ──────────────────────────────────────────────────────────────────────────────

func _on_ok() -> void:
	_close_child_dialog()
	hide()
	confirmed_dictionary.emit(_data.duplicate(true))

func _on_cancel() -> void:
	_close_child_dialog()
	hide()

# ──────────────────────────────────────────────────────────────────────────────
# Вспомогательные элементы UI
# ──────────────────────────────────────────────────────────────────────────────

func _make_spin(step: float, allow_float: bool) -> SpinBox:
	var sb := SpinBox.new()
	sb.step = step
	sb.allow_lesser = true
	sb.allow_greater = true
	sb.min_value = -9999999.0
	sb.max_value = 9999999.0
	sb.custom_minimum_size.x = 90
	if not allow_float:
		sb.rounded = true
	return sb

func _axis_label(text: String) -> Label:
	var l := Label.new(); l.text = text; return l

func _style_color_button(c: Color) -> void:
	if _v_color_btn == null: return
	_v_color_btn.text = c.to_html(true)
	var style := StyleBoxFlat.new()
	style.bg_color = c
	style.set_corner_radius_all(4)
	_v_color_btn.add_theme_stylebox_override("normal", style)
	_v_color_btn.add_theme_stylebox_override("hover", style)
	_v_color_btn.add_theme_stylebox_override("pressed", style)
	_v_color_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_v_color_btn.add_theme_color_override(
		"font_color", Color.BLACK if c.get_luminance() > 0.5 else Color.WHITE)
