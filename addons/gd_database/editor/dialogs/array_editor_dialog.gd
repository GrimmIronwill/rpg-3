@tool
extends Window
class_name ArrayEditorDialog
## Редактор однородного массива с учётом типа элементов.
## Редактор элемента подстраивается под `field.array_element_type`,
## выбранные элементы можно изменять кнопкой «Update».

signal confirmed_array(result: Array)

var _field_def: DBFieldDef = null
var _array_data: Array = []
var _selected_idx: int = -1
var _ui_built: bool = false

# Текущее значение во встроенном редакторе (синхронизируется с виджетами).
var _current_value: Variant = null
var _color_value: Color = Color.WHITE
var _database: DBDatabase = null

# ── Интерфейс ─────────────────────────────────────────────────────────────────
var _item_list: ItemList
var _type_label: Label
var _editor_host: HBoxContainer

# Виджеты редактора (создаются только соответствующие типу элемента).
var _line: LineEdit = null
var _num_spin: SpinBox = null
var _check: CheckBox = null
var _vx: SpinBox = null
var _vy: SpinBox = null
var _vz: SpinBox = null
var _color_btn: Button = null
var _enum_opt: OptionButton = null

var _add_btn: Button
var _update_btn: Button
var _remove_btn: Button
var _up_btn: Button
var _dn_btn: Button
var _complex_btn: Button = null   # dict / nested object / array элемент

# Дочерние диалоги (выбор цвета / файлов) — отслеживаются для избежания утечек.
var _child_dialog: Window = null

# ──────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true
	title = "Array Editor"
	min_size = Vector2i(440, 480)
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
	_type_label.text = "Array elements:"
	vbox.add_child(_type_label)

	_item_list = ItemList.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.custom_minimum_size.y = 220
	_item_list.item_selected.connect(_on_item_selected)
	vbox.add_child(_item_list)

	vbox.add_child(HSeparator.new())

	# Динамический редактор значения находится в этом контейнере (перестраивается по типу).
	var edit_lbl := Label.new()
	edit_lbl.text = "Value:"
	vbox.add_child(edit_lbl)

	_editor_host = HBoxContainer.new()
	_editor_host.add_theme_constant_override("separation", 4)
	vbox.add_child(_editor_host)

	# Добавить / Обновить / Удалить строку.
	var act_row := HBoxContainer.new()
	vbox.add_child(act_row)
	_add_btn = Button.new(); _add_btn.text = "+ Add"
	_add_btn.tooltip_text = "Append a new element"
	_add_btn.pressed.connect(_on_add)
	act_row.add_child(_add_btn)
	_update_btn = Button.new(); _update_btn.text = "✎ Update"
	_update_btn.tooltip_text = "Replace the selected element with the current value"
	_update_btn.pressed.connect(_on_update)
	act_row.add_child(_update_btn)
	_remove_btn = Button.new(); _remove_btn.text = "− Remove"
	_remove_btn.pressed.connect(_on_remove)
	act_row.add_child(_remove_btn)

	# Перемещение строк.
	var order_row := HBoxContainer.new()
	vbox.add_child(order_row)
	_up_btn = Button.new(); _up_btn.text = "▲ Up"
	_up_btn.pressed.connect(func(): _move(-1))
	order_row.add_child(_up_btn)
	_dn_btn = Button.new(); _dn_btn.text = "▼ Down"
	_dn_btn.pressed.connect(func(): _move(1))
	order_row.add_child(_dn_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	order_row.add_child(spacer)

	vbox.add_child(HSeparator.new())

	# OK / Отмена.
	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	var sp2 := Control.new(); sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(sp2)
	var cancel_btn := Button.new(); cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)
	var ok_btn := Button.new(); ok_btn.text = "OK"
	ok_btn.pressed.connect(_on_ok)
	btn_row.add_child(ok_btn)

# ──────────────────────────────────────────────────────────────────────────────
# Публичный API
# ──────────────────────────────────────────────────────────────────────────────

func open(array: Array, field: DBFieldDef, db: DBDatabase = null) -> void:
	_build_ui()
	_field_def   = field
	_database     = db
	_array_data  = array.duplicate(true)
	_selected_idx = -1
	title = "Array Editor — %s <%s>" % [
		field.field_name if field else "array",
		_element_type_label()
	]
	_type_label.text = "Array elements  (type: %s):" % _element_type_label()
	_type_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_type_label.custom_minimum_size.x = 0
	_type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rebuild_value_editor()
	_current_value = _default_elem_value()
	_write_editor(_current_value)
	_refresh_list()
	popup_centered(Vector2i(480, 600))

# ──────────────────────────────────────────────────────────────────────────────
# Помощники типа элемента
# ──────────────────────────────────────────────────────────────────────────────

func _element_type() -> int:
	return _field_def.array_element_type if _field_def else DBFieldDef.FieldType.STRING

func _element_type_label() -> String:
	if _field_def == null: return "string"
	var tmp := DBFieldDef.new()
	tmp.field_type = _field_def.array_element_type
	tmp.enum_values = _field_def.enum_values
	tmp.resource_type_hint = _field_def.resource_type_hint
	return tmp.get_type_label()

## Временное определение поля для одного элемента — переиспользуется для приведения типов.
func _make_elem_field() -> DBFieldDef:
	var fd := DBFieldDef.new()
	fd.field_type = _element_type()
	if _field_def:
		fd.enum_values          = _field_def.enum_values
		fd.enum_ref             = _field_def.enum_ref
		fd.resource_type_hint   = _field_def.resource_type_hint
		fd.nested_schema_name   = _field_def.nested_schema_name
		fd.dict_key_type        = _field_def.dict_key_type
		fd.dict_value_type      = _field_def.dict_value_type
		fd.dict_key_enum_values = _field_def.dict_key_enum_values
		fd.ref_table_name       = _field_def.ref_table_name
	return fd


func _coerce_elem(v: Variant) -> Variant:
	return _make_elem_field().coerce(v)

func _default_elem_value() -> Variant:
	return _make_elem_field().get_default()

func _format_elem(v: Variant) -> String:
	match _element_type():
		DBFieldDef.FieldType.COLOR:
			return (v as Color).to_html(true) if v is Color else str(v)
		DBFieldDef.FieldType.ENUM:
			if _field_def and v is int and v >= 0 and v < _field_def.enum_values.size():
				return _field_def.enum_values[v]
			return str(v)
		DBFieldDef.FieldType.DICTIONARY:
			return "{Dict: %d}" % (v as Dictionary).size() if v is Dictionary else "{}"
		DBFieldDef.FieldType.NESTED_OBJECT:
			return "{Object: %d}" % (v as Dictionary).size() if v is Dictionary else "{}"
		DBFieldDef.FieldType.ARRAY:
			return "[Array: %d]" % (v as Array).size() if v is Array else "[]"
		_:
			return DBFieldDef.format_value_for_display(v)

# ──────────────────────────────────────────────────────────────────────────────
# Динамический редактор значения
# ──────────────────────────────────────────────────────────────────────────────

func _rebuild_value_editor() -> void:
	for c in _editor_host.get_children():
		_editor_host.remove_child(c)
		c.queue_free()
	_line = null; _num_spin = null; _check = null
	_vx = null; _vy = null; _vz = null
	_color_btn = null; _enum_opt = null
	_complex_btn = null

	match _element_type():
		DBFieldDef.FieldType.INT:
			_num_spin = _make_spin(1, false)
			_num_spin.value_changed.connect(func(v): _current_value = int(v))
			_editor_host.add_child(_num_spin)

		DBFieldDef.FieldType.FLOAT:
			_num_spin = _make_spin(0.001, true)
			_num_spin.value_changed.connect(func(v): _current_value = v)
			_editor_host.add_child(_num_spin)

		DBFieldDef.FieldType.BOOL:
			_check = CheckBox.new()
			_check.text = "true / false"
			_check.toggled.connect(func(b): _current_value = b)
			_editor_host.add_child(_check)

		DBFieldDef.FieldType.STRING:
			_line = LineEdit.new()
			_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_line.placeholder_text = "value…"
			_line.text_changed.connect(func(t): _current_value = t)
			_editor_host.add_child(_line)

		DBFieldDef.FieldType.RESOURCE_REF:
			_line = LineEdit.new()
			_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_line.placeholder_text = "res://…"
			_line.text_changed.connect(func(t): _current_value = t)
			_editor_host.add_child(_line)
			var browse := Button.new()
			browse.text = "Browse…"
			browse.pressed.connect(_on_browse_resource)
			_editor_host.add_child(browse)

		DBFieldDef.FieldType.ENUM:
			_enum_opt = OptionButton.new()
			_enum_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_enum_opt.search_bar_enabled = true
			if _field_def and _field_def.enum_values.size() > 0:
				for ev in _field_def.enum_values:
					_enum_opt.add_item(ev)
			else:
				_enum_opt.add_item("(no enum values)")
			_enum_opt.item_selected.connect(func(idx): _current_value = idx)
			_editor_host.add_child(_enum_opt)

		DBFieldDef.FieldType.VECTOR2:
			_editor_host.add_child(_axis_label("X"))
			_vx = _make_spin(0.001, true); _vx.value_changed.connect(func(_v): _update_vector())
			_editor_host.add_child(_vx)
			_editor_host.add_child(_axis_label("Y"))
			_vy = _make_spin(0.001, true); _vy.value_changed.connect(func(_v): _update_vector())
			_editor_host.add_child(_vy)

		DBFieldDef.FieldType.VECTOR3:
			_editor_host.add_child(_axis_label("X"))
			_vx = _make_spin(0.001, true); _vx.value_changed.connect(func(_v): _update_vector())
			_editor_host.add_child(_vx)
			_editor_host.add_child(_axis_label("Y"))
			_vy = _make_spin(0.001, true); _vy.value_changed.connect(func(_v): _update_vector())
			_editor_host.add_child(_vy)
			_editor_host.add_child(_axis_label("Z"))
			_vz = _make_spin(0.001, true); _vz.value_changed.connect(func(_v): _update_vector())
			_editor_host.add_child(_vz)

		DBFieldDef.FieldType.COLOR:
			_color_btn = Button.new()
			_color_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_color_btn.pressed.connect(_on_pick_color)
			_editor_host.add_child(_color_btn)
			_style_color_button(_color_value)

		DBFieldDef.FieldType.DICTIONARY:
			_complex_btn = Button.new()
			_complex_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_complex_btn.pressed.connect(_on_edit_dict_element)
			_editor_host.add_child(_complex_btn)

		DBFieldDef.FieldType.NESTED_OBJECT:
			_complex_btn = Button.new()
			_complex_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_complex_btn.pressed.connect(_on_edit_nested_element)
			_editor_host.add_child(_complex_btn)

		DBFieldDef.FieldType.ARRAY:
			_complex_btn = Button.new()
			_complex_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_complex_btn.pressed.connect(_on_edit_array_element)
			_editor_host.add_child(_complex_btn)

		DBFieldDef.FieldType.TABLE_REF:
			_line = LineEdit.new()
			_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_line.placeholder_text = "entry_id…"
			_line.text_changed.connect(func(t): _current_value = t)
			_editor_host.add_child(_line)
			var pick := Button.new()
			pick.text = "Pick…"
			pick.pressed.connect(_on_pick_table_ref)
			_editor_host.add_child(pick)

		_:
			_line = LineEdit.new()
			_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_line.text_changed.connect(func(t): _current_value = t)
			_editor_host.add_child(_line)


## Записывает `_current_value` в виджеты редактора.
func _write_editor(v: Variant) -> void:
	_current_value = _coerce_elem(v)
	match _element_type():
		DBFieldDef.FieldType.INT, DBFieldDef.FieldType.FLOAT:
			if _num_spin: _num_spin.set_value_no_signal(float(_current_value))
		DBFieldDef.FieldType.BOOL:
			if _check: _check.set_pressed_no_signal(bool(_current_value))
		DBFieldDef.FieldType.STRING, DBFieldDef.FieldType.RESOURCE_REF, \
		DBFieldDef.FieldType.TABLE_REF:
			if _line: _line.text = str(_current_value)
		DBFieldDef.FieldType.ENUM:
			if _enum_opt and _enum_opt.item_count > 0:
				_enum_opt.selected = clampi(int(_current_value), 0, _enum_opt.item_count - 1)
		DBFieldDef.FieldType.VECTOR2:
			var v2: Vector2 = _current_value if _current_value is Vector2 else Vector2.ZERO
			if _vx: _vx.set_value_no_signal(v2.x)
			if _vy: _vy.set_value_no_signal(v2.y)
		DBFieldDef.FieldType.VECTOR3:
			var v3: Vector3 = _current_value if _current_value is Vector3 else Vector3.ZERO
			if _vx: _vx.set_value_no_signal(v3.x)
			if _vy: _vy.set_value_no_signal(v3.y)
			if _vz: _vz.set_value_no_signal(v3.z)
		DBFieldDef.FieldType.COLOR:
			_color_value = _current_value if _current_value is Color else Color.WHITE
			_style_color_button(_color_value)
		DBFieldDef.FieldType.DICTIONARY:
			if _complex_btn:
				var dd: Dictionary = _current_value if _current_value is Dictionary else {}
				_complex_btn.text = "{Dict: %d}" % dd.size()
		DBFieldDef.FieldType.NESTED_OBJECT:
			if _complex_btn:
				var od: Dictionary = _current_value if _current_value is Dictionary else {}
				_complex_btn.text = "{Object: %d fields}" % od.size()
		DBFieldDef.FieldType.ARRAY:
			if _complex_btn:
				var aa: Array = _current_value if _current_value is Array else []
				_complex_btn.text = "[Array: %d]" % aa.size()
		_:
			if _line: _line.text = str(_current_value)

func _update_vector() -> void:
	if _element_type() == DBFieldDef.FieldType.VECTOR3:
		_current_value = Vector3(_vx.value, _vy.value, _vz.value)
	else:
		_current_value = Vector2(_vx.value, _vy.value)

# ──────────────────────────────────────────────────────────────────────────────
# Работа со списком
# ──────────────────────────────────────────────────────────────────────────────

func _refresh_list() -> void:
	_item_list.clear()
	for v in _array_data:
		_item_list.add_item(_format_elem(v))
	if _selected_idx >= 0 and _selected_idx < _array_data.size():
		_item_list.select(_selected_idx)

func _on_item_selected(idx: int) -> void:
	_selected_idx = idx
	_write_editor(_array_data[idx])

func _on_pick_table_ref() -> void:
	_close_child_dialog()
	if _database == null or _field_def == null or _field_def.ref_table_name.is_empty():
		push_warning("[Array Editor] Не задана целевая таблица для Table Ref.")
		return
	var picker := TableRefPickerDialog.new()
	add_child(picker)
	_child_dialog = picker
	picker.ref_confirmed.connect(func(id: String) -> void:
		_current_value = id
		if _line: _line.text = id
		_close_child_dialog()
	)
	picker.close_requested.connect(_close_child_dialog)
	picker.open(_database, _field_def.ref_table_name, str(_current_value))

func _on_add() -> void:
	_array_data.append(_coerce_elem(_current_value))
	_selected_idx = _array_data.size() - 1
	_refresh_list()

func _on_update() -> void:
	if _selected_idx < 0 or _selected_idx >= _array_data.size():
		push_warning("[Array Editor] Select an element to update first.")
		return
	_array_data[_selected_idx] = _coerce_elem(_current_value)
	_refresh_list()

func _on_remove() -> void:
	var idxs := _item_list.get_selected_items()
	if idxs.is_empty(): return
	_array_data.remove_at(idxs[0])
	_selected_idx = -1
	_refresh_list()

func _move(delta: int) -> void:
	var idxs := _item_list.get_selected_items()
	if idxs.is_empty(): return
	var i: int = idxs[0]
	var j: int = clampi(i + delta, 0, _array_data.size() - 1)
	if i == j: return
	var v: Variant = _array_data[i]
	_array_data.remove_at(i)
	_array_data.insert(j, v)
	_selected_idx = j
	_refresh_list()

# ──────────────────────────────────────────────────────────────────────────────
# Редакторы сложных элементов
# ──────────────────────────────────────────────────────────────────────────────

func _on_edit_dict_element() -> void:
	_close_child_dialog()
	var ed := DictionaryEditorDialog.new()
	add_child(ed)
	_child_dialog = ed
	ed.confirmed_dictionary.connect(func(result: Dictionary) -> void:
		_current_value = result
		if _complex_btn: _complex_btn.text = "{Dict: %d}" % result.size()
		_close_child_dialog()
	)
	ed.close_requested.connect(_close_child_dialog)
	var cur: Dictionary = _current_value if _current_value is Dictionary else {}
	ed.open(cur, _make_elem_field(), _database)

func _on_edit_nested_element() -> void:
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
		if _complex_btn: _complex_btn.text = "{Object: %d fields}" % result.size()
		_close_child_dialog()
	)
	ed.close_requested.connect(_close_child_dialog)
	var cur: Dictionary = _current_value if _current_value is Dictionary else {}
	ed.open(cur, nested_schema, _database)

func _on_edit_array_element() -> void:
	_close_child_dialog()
	var fd := DBFieldDef.new()
	fd.field_type = DBFieldDef.FieldType.ARRAY
	fd.array_element_type = DBFieldDef.FieldType.STRING   # вложенный тип неизвестен → строка
	var ed := ArrayEditorDialog.new()
	add_child(ed)
	_child_dialog = ed
	ed.confirmed_array.connect(func(result: Array) -> void:
		_current_value = result
		if _complex_btn: _complex_btn.text = "[Array: %d]" % result.size()
		_close_child_dialog()
	)
	ed.close_requested.connect(_close_child_dialog)
	var cur: Array = _current_value if _current_value is Array else []
	ed.open(cur, fd)

func _on_pick_color() -> void:
	_close_child_dialog()
	var dlg := AcceptDialog.new()
	dlg.title = "Pick Color"
	var cp := ColorPicker.new()
	cp.color = _color_value
	dlg.add_child(cp)
	add_child(dlg)
	_child_dialog = dlg
	dlg.popup_centered(Vector2i(380, 440))
	dlg.confirmed.connect(func() -> void:
		_color_value = cp.color
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
		if _line: _line.text = path
		_close_child_dialog()
	)
	dlg.canceled.connect(_close_child_dialog)

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
	confirmed_array.emit(_array_data.duplicate(true))

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
	var l := Label.new()
	l.text = text
	return l

func _style_color_button(c: Color) -> void:
	if _color_btn == null: return
	_color_btn.text = c.to_html(true)
	var style := StyleBoxFlat.new()
	style.bg_color = c
	style.set_corner_radius_all(4)
	_color_btn.add_theme_stylebox_override("normal", style)
	_color_btn.add_theme_stylebox_override("hover", style)
	_color_btn.add_theme_stylebox_override("pressed", style)
	_color_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_color_btn.add_theme_color_override(
		"font_color", Color.BLACK if c.get_luminance() > 0.5 else Color.WHITE)
