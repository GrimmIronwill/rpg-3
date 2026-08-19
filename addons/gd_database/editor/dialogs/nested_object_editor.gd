@tool
extends Window
class_name NestedObjectEditor
## Редактор вложенного Dictionary.
## Два режима:
##   • schema mode  – предоставлена DBSchema; поля фиксированы.
##   • free mode    – без схемы; пользователь добавляет/удаляет произвольные типизированные ключи.

signal object_confirmed(result: Dictionary)

# ── Данные ────────────────────────────────────────────────────────────────────
var _schema: DBSchema = null
var _free_mode: bool = false
var _database: DBDatabase = null   # ИСПРАВЛЕНИЕ: нужен, чтобы резолвить вложенные схемы по имени

# Режим схемы: текущие значения, ключи — имена полей.
var _data: Dictionary = {}

# Свободный режим: список слотов. Каждый слот = { id, name, type, value, elem_type }.
var _slots: Array = []
var _next_id: int = 0

# ── Интерфейс ─────────────────────────────────────────────────────────────────
var _scroll: ScrollContainer
var _fields_vbox: VBoxContainer

var _open_dialogs: Dictionary = {}

# Палитра типов для free-mode (ENUM намеренно исключён — нужны метаданные схемы).
const FREE_TYPES := [
	"int", "float", "string", "bool",
	"Vector2", "Vector3", "Color",
	"Resource Ref", "Array", "Nested Object", "Dictionary"
]
const FREE_TYPE_IDS := [
	DBFieldDef.FieldType.INT,
	DBFieldDef.FieldType.FLOAT,
	DBFieldDef.FieldType.STRING,
	DBFieldDef.FieldType.BOOL,
	DBFieldDef.FieldType.VECTOR2,
	DBFieldDef.FieldType.VECTOR3,
	DBFieldDef.FieldType.COLOR,
	DBFieldDef.FieldType.RESOURCE_REF,
	DBFieldDef.FieldType.ARRAY,
	DBFieldDef.FieldType.NESTED_OBJECT,
	DBFieldDef.FieldType.DICTIONARY,
]

# ──────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	title = "Edit Nested Object"
	min_size = Vector2i(560, 460)
	close_requested.connect(_on_close_requested)
	_build_ui()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "Object fields:"
	vbox.add_child(hdr)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size.y = 300
	vbox.add_child(_scroll)

	_fields_vbox = VBoxContainer.new()
	_fields_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields_vbox.add_theme_constant_override("separation", 4)
	_scroll.add_child(_fields_vbox)

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)
	var cancel_btn := Button.new(); cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_close_requested)
	btn_row.add_child(cancel_btn)
	var ok_btn := Button.new(); ok_btn.text = "OK"
	ok_btn.pressed.connect(_on_ok)
	btn_row.add_child(ok_btn)


# ──────────────────────────────────────────────────────────────────────────────
# Публичный API
# ──────────────────────────────────────────────────────────────────────────────

## ИСПРАВЛЕНИЕ: добавлен параметр db, чтобы вложенные уровни могли резолвить схемы.
func open(data: Dictionary, schema: DBSchema = null, db: DBDatabase = null) -> void:
	_schema = schema
	_database = db
	_free_mode = (schema == null)
	_close_all_dialogs()

	if _free_mode:
		_slots.clear()
		var src := data.duplicate(true)
		for key in src.keys():
			var val: Variant = _convert_dict_to_typed(src[key])
			var ft := _infer_type_from_value(val)
			var slot := {
				"id": _next_id,
				"name": str(key),
				"type": ft,
				"value": val,
				"elem_type": -1,
			}
			if ft == DBFieldDef.FieldType.ARRAY and (val as Array).size() > 0:
				slot["elem_type"] = _infer_type_from_value((val as Array)[0])
			_next_id += 1
			_slots.append(slot)
	else:
		_data = {}
		for f: DBFieldDef in _schema.fields:
			var v: Variant = data.get(f.field_name, f.get_default())
			_data[f.field_name] = f.coerce(v)

	_rebuild()
	popup_centered()

# ──────────────────────────────────────────────────────────────────────────────
# Построение строк
# ──────────────────────────────────────────────────────────────────────────────

func _clear_rows() -> void:
	for c in _fields_vbox.get_children():
		_fields_vbox.remove_child(c)
		c.queue_free()

func _rebuild() -> void:
	_clear_rows()
	if _free_mode:
		for slot in _slots:
			_add_free_row(slot)
		var add_btn := Button.new()
		add_btn.text = "+ Add Field"
		add_btn.pressed.connect(_on_add_free_field)
		_fields_vbox.add_child(add_btn)
	else:
		if _schema:
			for f: DBFieldDef in _schema.fields:
				_add_schema_row(f)

func _add_schema_row(f: DBFieldDef) -> void:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = f.field_name + ":"
	label.custom_minimum_size.x = 130
	hbox.add_child(label)

	var skey := f.field_name
	var getter := func() -> Variant: return _data.get(skey, null)
	var setter := func(v: Variant) -> void: _data[skey] = v
	var elem_get := func() -> int: return f.array_element_type
	var elem_set := func(_t: int) -> void: pass

	var editor := _build_value_editor(
		skey, f.field_type, _data.get(skey, null), f,
		getter, setter, elem_get, elem_set
	)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(editor)
	_fields_vbox.add_child(hbox)

func _add_free_row(slot: Dictionary) -> void:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_edit := LineEdit.new()
	name_edit.text = str(slot["name"])
	name_edit.custom_minimum_size.x = 120
	name_edit.text_changed.connect(func(t: String) -> void: slot["name"] = t)
	hbox.add_child(name_edit)

	var type_opt := OptionButton.new()
	for tname in FREE_TYPES:
		type_opt.add_item(tname)
	type_opt.selected = _free_type_index(int(slot["type"]))
	type_opt.item_selected.connect(func(idx: int) -> void: _on_free_type_changed(slot, idx))
	hbox.add_child(type_opt)

	var dlg_key := "slot_%d" % int(slot["id"])
	var getter := func() -> Variant: return slot["value"]
	var setter := func(v: Variant) -> void: slot["value"] = v
	var elem_get := func() -> int: return int(slot.get("elem_type", -1))
	var elem_set := func(t: int) -> void: slot["elem_type"] = t

	var editor := _build_value_editor(
		dlg_key, int(slot["type"]), slot["value"], null,
		getter, setter, elem_get, elem_set
	)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(editor)

	var del_btn := Button.new()
	del_btn.text = "✕"
	del_btn.tooltip_text = "Remove field"
	del_btn.pressed.connect(func() -> void: _on_remove_free_field(slot))
	hbox.add_child(del_btn)

	_fields_vbox.add_child(hbox)

# ──────────────────────────────────────────────────────────────────────────────
# Универсальный построитель редактора значений (используется в обоих режимах)
# ──────────────────────────────────────────────────────────────────────────────

func _build_value_editor(dlg_key: String, type: int, value: Variant,
		field_def: DBFieldDef,
		getter: Callable, setter: Callable,
		elem_get: Callable, elem_set: Callable) -> Control:

	match type:
		DBFieldDef.FieldType.INT:
			var sb := SpinBox.new()
			sb.allow_lesser = true; sb.allow_greater = true
			sb.step = 1; sb.min_value = -9999999; sb.max_value = 9999999
			sb.value = float(value) if (value is int or value is float) else 0.0
			sb.value_changed.connect(func(v: float) -> void: setter.call(int(v)))
			return sb

		DBFieldDef.FieldType.FLOAT:
			var sb := SpinBox.new()
			sb.allow_lesser = true; sb.allow_greater = true
			sb.step = 0.001; sb.min_value = -9999999.0; sb.max_value = 9999999.0
			sb.value = float(value) if (value is int or value is float) else 0.0
			sb.value_changed.connect(func(v: float) -> void: setter.call(v))
			return sb

		DBFieldDef.FieldType.BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = bool(value)
			cb.toggled.connect(func(b: bool) -> void: setter.call(b))
			return cb

		DBFieldDef.FieldType.STRING:
			var le := LineEdit.new()
			le.text = str(value) if value != null else ""
			le.text_changed.connect(func(t: String) -> void: setter.call(t))
			return le

		DBFieldDef.FieldType.RESOURCE_REF:
			var hb := HBoxContainer.new()
			hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var le := LineEdit.new()
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.placeholder_text = "res://…"
			le.text = str(value) if value != null else ""
			le.text_changed.connect(func(t: String) -> void: setter.call(t))
			hb.add_child(le)
			var browse := Button.new()
			browse.text = "Browse…"
			browse.pressed.connect(func() -> void:
				_open_resource_browser(dlg_key, le, field_def, setter)
			)
			hb.add_child(browse)
			return hb

		DBFieldDef.FieldType.ENUM:
			var opt := OptionButton.new()
			opt.search_bar_enabled = true
			if field_def and field_def.enum_values.size() > 0:
				for ev in field_def.enum_values:
					opt.add_item(ev)
				opt.selected = clampi(int(value), 0, field_def.enum_values.size() - 1)
			else:
				opt.add_item(str(value))
				opt.selected = 0
			opt.item_selected.connect(func(idx: int) -> void: setter.call(idx))
			return opt

		DBFieldDef.FieldType.COLOR:
			var c := _to_color(value)
			var btn := Button.new()
			btn.custom_minimum_size.x = 120
			_style_color_button(btn, c)
			btn.pressed.connect(func() -> void:
				_open_color(dlg_key, btn, _to_color(getter.call()), setter)
			)
			return btn

		DBFieldDef.FieldType.VECTOR2:
			var btn := Button.new()
			btn.custom_minimum_size.x = 160
			btn.text = DBFieldDef.format_value_for_display(_convert_to_vector2(value))
			btn.pressed.connect(func() -> void:
				_open_vector2(dlg_key, btn, _convert_to_vector2(getter.call()), setter)
			)
			return btn

		DBFieldDef.FieldType.VECTOR3:
			var btn := Button.new()
			btn.custom_minimum_size.x = 160
			btn.text = DBFieldDef.format_value_for_display(_convert_to_vector3(value))
			btn.pressed.connect(func() -> void:
				_open_vector3(dlg_key, btn, _convert_to_vector3(getter.call()), setter)
			)
			return btn

		DBFieldDef.FieldType.ARRAY:
			var arr0: Array = value if value is Array else []
			var btn := Button.new()
			btn.text = "[Array: %d]" % arr0.size()
			btn.pressed.connect(func() -> void:
				var cur: Variant = getter.call()
				var a: Array = cur if cur is Array else []
				# ИСПРАВЛЕНИЕ: пробрасываем field_def → массив сохраняет nested_schema_name/enum.
				_open_array(dlg_key, btn, a, int(elem_get.call()), field_def, setter, elem_set)
			)
			return btn

		DBFieldDef.FieldType.NESTED_OBJECT:
			var d0: Dictionary = value if value is Dictionary else {}
			var btn := Button.new()
			btn.text = "{Object: %d fields}" % d0.size()
			btn.pressed.connect(func() -> void:
				var cur: Variant = getter.call()
				var d: Dictionary = cur if cur is Dictionary else {}
				# ИСПРАВЛЕНИЕ: резолвим дочернюю схему по nested_schema_name (рекурсивная вложенность).
				_open_nested(dlg_key, btn, d, _resolve_nested_schema(field_def), setter)
			)
			return btn

		DBFieldDef.FieldType.DICTIONARY:
			# ИСПРАВЛЕНИЕ: раньше этой ветки не было → словарь падал в _: и рисовался строкой.
			var dd0: Dictionary = value if value is Dictionary else {}
			var btn := Button.new()
			btn.text = "{Dict: %d}" % dd0.size()
			btn.pressed.connect(func() -> void:
				var cur: Variant = getter.call()
				var d: Dictionary = cur if cur is Dictionary else {}
				_open_dict(dlg_key, btn, d, field_def, setter)
			)
			return btn

		_:
			var le := LineEdit.new()
			le.text = str(value) if value != null else ""
			le.text_changed.connect(func(t: String) -> void: setter.call(t))
			return le

# ──────────────────────────────────────────────────────────────────────────────
# Диалоги сложных типов (все записывают через `setter`)
# ──────────────────────────────────────────────────────────────────────────────

func _open_resource_browser(dlg_key: String, le: LineEdit,
		field_def: DBFieldDef, setter: Callable) -> void:
	_close_dialog(dlg_key)
	var dlg := EditorFileDialog.new()
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	if field_def and not field_def.resource_type_hint.is_empty():
		dlg.add_filter("*.*", field_def.resource_type_hint)
	else:
		dlg.add_filter("*.*", "All Resources")
		dlg.add_filter("*.tres,*.res,*.tscn,*.gd", "Godot Resources")
	add_child(dlg)
	_open_dialogs[dlg_key] = dlg
	dlg.popup_centered(Vector2i(800, 550))
	dlg.file_selected.connect(func(path: String) -> void:
		setter.call(path)
		le.text = path
		_open_dialogs.erase(dlg_key)
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void:
		_open_dialogs.erase(dlg_key)
		dlg.queue_free()
	)

func _open_color(dlg_key: String, btn: Button, current: Color, setter: Callable) -> void:
	_close_dialog(dlg_key)
	var dlg := AcceptDialog.new()
	dlg.title = "Pick Color"
	var cp := ColorPicker.new()
	cp.color = current
	dlg.add_child(cp)
	add_child(dlg)
	_open_dialogs[dlg_key] = dlg
	dlg.popup_centered(Vector2i(380, 440))
	dlg.confirmed.connect(func() -> void:
		setter.call(cp.color)
		_style_color_button(btn, cp.color)
		_open_dialogs.erase(dlg_key)
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void:
		_open_dialogs.erase(dlg_key)
		dlg.queue_free()
	)

func _open_vector2(dlg_key: String, btn: Button, val: Vector2, setter: Callable) -> void:
	_close_dialog(dlg_key)
	var dlg := AcceptDialog.new()
	dlg.title = "Edit Vector2"
	var grid := GridContainer.new()
	grid.columns = 2
	var ex := _spin(val.x)
	var ey := _spin(val.y)
	grid.add_child(_label("X")); grid.add_child(ex)
	grid.add_child(_label("Y")); grid.add_child(ey)
	dlg.add_child(grid)
	add_child(dlg)
	_open_dialogs[dlg_key] = dlg
	dlg.popup_centered(Vector2i(260, 130))
	dlg.confirmed.connect(func() -> void:
		var nv := Vector2(ex.value, ey.value)
		setter.call(nv)
		btn.text = DBFieldDef.format_value_for_display(nv)
		_open_dialogs.erase(dlg_key)
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void:
		_open_dialogs.erase(dlg_key)
		dlg.queue_free()
	)

func _open_vector3(dlg_key: String, btn: Button, val: Vector3, setter: Callable) -> void:
	_close_dialog(dlg_key)
	var dlg := AcceptDialog.new()
	dlg.title = "Edit Vector3"
	var grid := GridContainer.new()
	grid.columns = 2
	var ex := _spin(val.x)
	var ey := _spin(val.y)
	var ez := _spin(val.z)
	grid.add_child(_label("X")); grid.add_child(ex)
	grid.add_child(_label("Y")); grid.add_child(ey)
	grid.add_child(_label("Z")); grid.add_child(ez)
	dlg.add_child(grid)
	add_child(dlg)
	_open_dialogs[dlg_key] = dlg
	dlg.popup_centered(Vector2i(260, 160))
	dlg.confirmed.connect(func() -> void:
		var nv := Vector3(ex.value, ey.value, ez.value)
		setter.call(nv)
		btn.text = DBFieldDef.format_value_for_display(nv)
		_open_dialogs.erase(dlg_key)
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void:
		_open_dialogs.erase(dlg_key)
		dlg.queue_free()
	)

## ИСПРАВЛЕНИЕ: добавлен параметр field_def, чтобы дочерний массив сохранял метаданные
## (enum/nested_schema_name/dict-типы) и базу данных.
func _open_array(dlg_key: String, btn: Button, arr: Array, elem_type: int,
		field_def: DBFieldDef, setter: Callable, elem_set: Callable) -> void:
	_close_dialog(dlg_key)
	if elem_type == -1:
		_pick_array_elem_type(dlg_key, func(t: int) -> void:
			elem_set.call(t)
			_open_array(dlg_key, btn, arr, t, field_def, setter, elem_set)
		)
		return

	var fd := DBFieldDef.new()
	fd.field_type = DBFieldDef.FieldType.ARRAY
	fd.array_element_type = elem_type
	if field_def:
		fd.enum_values          = field_def.enum_values
		fd.enum_ref             = field_def.enum_ref
		fd.nested_schema_name   = field_def.nested_schema_name
		fd.resource_type_hint   = field_def.resource_type_hint
		fd.dict_key_type        = field_def.dict_key_type
		fd.dict_value_type      = field_def.dict_value_type
		fd.dict_key_enum_values = field_def.dict_key_enum_values

	var ed := ArrayEditorDialog.new()
	add_child(ed)
	_open_dialogs[dlg_key] = ed
	ed.confirmed_array.connect(func(result: Array) -> void:
		setter.call(result)
		btn.text = "[Array: %d]" % result.size()
		_open_dialogs.erase(dlg_key)
		ed.queue_free()
	)
	ed.close_requested.connect(func() -> void:
		_open_dialogs.erase(dlg_key)
		ed.queue_free()
	)
	ed.open(arr, fd, _database)

func _pick_array_elem_type(dlg_key: String, on_pick: Callable) -> void:
	_close_dialog(dlg_key)
	var dlg := AcceptDialog.new()
	dlg.title = "Choose array element type"
	var vb := VBoxContainer.new()
	var opt := OptionButton.new()
	for t in FREE_TYPES:
		opt.add_item(t)
	opt.selected = 2   # string by default
	vb.add_child(opt)
	dlg.add_child(vb)
	add_child(dlg)
	_open_dialogs[dlg_key] = dlg
	dlg.popup_centered(Vector2i(260, 110))
	dlg.confirmed.connect(func() -> void:
		var t := _free_type_from_index(opt.selected)
		_open_dialogs.erase(dlg_key)
		dlg.queue_free()
		on_pick.call(t)
	)
	dlg.canceled.connect(func() -> void:
		_open_dialogs.erase(dlg_key)
		dlg.queue_free()
	)

## ИСПРАВЛЕНИЕ: добавлен параметр sub_schema + проброс _database (рекурсивная вложенность).
func _open_nested(dlg_key: String, btn: Button, obj: Dictionary,
		sub_schema: DBSchema, setter: Callable) -> void:
	_close_dialog(dlg_key)
	var ed := NestedObjectEditor.new()
	add_child(ed)
	_open_dialogs[dlg_key] = ed
	ed.object_confirmed.connect(func(result: Dictionary) -> void:
		setter.call(result)
		btn.text = "{Object: %d fields}" % result.size()
		_open_dialogs.erase(dlg_key)
		ed.queue_free()
	)
	ed.close_requested.connect(func() -> void:
		_open_dialogs.erase(dlg_key)
		ed.queue_free()
	)
	ed.open(obj, sub_schema, _database)

## ИСПРАВЛЕНИЕ (новое): открывает настоящий редактор словаря вместо строки.
func _open_dict(dlg_key: String, btn: Button, d: Dictionary,
		field_def: DBFieldDef, setter: Callable) -> void:
	_close_dialog(dlg_key)
	var fd := field_def
	if fd == null:
		# free-mode словарь без метаданных → строка→строка
		fd = DBFieldDef.new()
		fd.field_type      = DBFieldDef.FieldType.DICTIONARY
		fd.dict_key_type   = DBFieldDef.FieldType.STRING
		fd.dict_value_type = DBFieldDef.FieldType.STRING
	var ed := DictionaryEditorDialog.new()
	add_child(ed)
	_open_dialogs[dlg_key] = ed
	ed.confirmed_dictionary.connect(func(result: Dictionary) -> void:
		setter.call(result)
		btn.text = "{Dict: %d}" % result.size()
		_open_dialogs.erase(dlg_key)
		ed.queue_free()
	)
	ed.close_requested.connect(func() -> void:
		_open_dialogs.erase(dlg_key)
		ed.queue_free()
	)
	ed.open(d, fd, _database)

## ИСПРАВЛЕНИЕ (новое): резолвит дочернюю схему по nested_schema_name через базу.
func _resolve_nested_schema(field_def: DBFieldDef) -> DBSchema:
	if _database and field_def and not field_def.nested_schema_name.is_empty():
		return _database.get_schema_by_name_or_table(field_def.nested_schema_name)
	return null

# ──────────────────────────────────────────────────────────────────────────────
# Управление полями в free-mode
# ──────────────────────────────────────────────────────────────────────────────

func _on_add_free_field() -> void:
	var slot := {
		"id": _next_id,
		"name": _unique_default_name(),
		"type": DBFieldDef.FieldType.STRING,
		"value": "",
		"elem_type": -1,
	}
	_next_id += 1
	_slots.append(slot)
	_rebuild()

func _on_remove_free_field(slot: Dictionary) -> void:
	_close_dialog("slot_%d" % int(slot["id"]))
	var idx := _slots.find(slot)
	if idx != -1:
		_slots.remove_at(idx)
	_rebuild()

func _on_free_type_changed(slot: Dictionary, opt_idx: int) -> void:
	var new_type := _free_type_from_index(opt_idx)
	if int(slot["type"]) == new_type:
		return
	_close_dialog("slot_%d" % int(slot["id"]))
	slot["value"] = _coerce_value(slot["value"], new_type)
	slot["type"] = new_type
	if new_type == DBFieldDef.FieldType.ARRAY:
		var v: Variant = slot["value"]
		slot["elem_type"] = _infer_type_from_value((v as Array)[0]) if (v is Array and (v as Array).size() > 0) else -1
	else:
		slot["elem_type"] = -1
	_rebuild()

func _unique_default_name() -> String:
	var existing := {}
	for s in _slots:
		existing[str(s["name"])] = true
	var i := 1
	while existing.has("field_%d" % i):
		i += 1
	return "field_%d" % i

# ──────────────────────────────────────────────────────────────────────────────
# Жизненный цикл диалогов
# ──────────────────────────────────────────────────────────────────────────────

func _close_dialog(dlg_key: String) -> void:
	if _open_dialogs.has(dlg_key):
		var dlg = _open_dialogs[dlg_key]
		if is_instance_valid(dlg):
			dlg.queue_free()
		_open_dialogs.erase(dlg_key)

func _close_all_dialogs() -> void:
	for key in _open_dialogs.keys():
		var dlg = _open_dialogs[key]
		if is_instance_valid(dlg):
			dlg.queue_free()
	_open_dialogs.clear()

# ──────────────────────────────────────────────────────────────────────────────
# OK / Отмена
# ──────────────────────────────────────────────────────────────────────────────

func _on_ok() -> void:
	_close_all_dialogs()
	var out := {}
	if _free_mode:
		for slot in _slots:
			var nm := str(slot["name"]).strip_edges()
			if nm.is_empty():
				continue
			if out.has(nm):
				push_warning("[NestedObjectEditor] Duplicate key '%s' skipped." % nm)
				continue
			out[nm] = _dup(slot["value"])
	else:
		for f: DBFieldDef in _schema.fields:
			out[f.field_name] = _dup(_data.get(f.field_name, f.get_default()))
	hide()
	object_confirmed.emit(out)

func _on_close_requested() -> void:
	_close_all_dialogs()
	hide()

# ──────────────────────────────────────────────────────────────────────────────
# Вспомогательные функции
# ──────────────────────────────────────────────────────────────────────────────

func _free_type_index(field_type: int) -> int:
	var idx := FREE_TYPE_IDS.find(field_type)
	return idx if idx != -1 else 2   # default → string

func _free_type_from_index(idx: int) -> int:
	if idx >= 0 and idx < FREE_TYPE_IDS.size():
		return FREE_TYPE_IDS[idx]
	return DBFieldDef.FieldType.STRING

func _infer_type_from_value(value: Variant) -> int:
	if value is bool:       return DBFieldDef.FieldType.BOOL
	if value is int:        return DBFieldDef.FieldType.INT
	if value is float:      return DBFieldDef.FieldType.FLOAT
	if value is String:     return DBFieldDef.FieldType.STRING
	if value is Vector2:    return DBFieldDef.FieldType.VECTOR2
	if value is Vector3:    return DBFieldDef.FieldType.VECTOR3
	if value is Color:      return DBFieldDef.FieldType.COLOR
	if value is Array:      return DBFieldDef.FieldType.ARRAY
	if value is Dictionary: return DBFieldDef.FieldType.NESTED_OBJECT
	return DBFieldDef.FieldType.STRING

func _coerce_value(value: Variant, new_type: int) -> Variant:
	var fd := DBFieldDef.new()
	fd.field_type = new_type
	return fd.coerce(value)

func _convert_dict_to_typed(value: Variant) -> Variant:
	if not (value is Dictionary):
		return value
	var d: Dictionary = value
	if d.has("x") and d.has("y") and d.has("z") and d.size() == 3:
		return Vector3(float(d.get("x", 0)), float(d.get("y", 0)), float(d.get("z", 0)))
	if d.has("x") and d.has("y") and d.size() == 2:
		return Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
	if d.has("r") and d.has("g") and d.has("b"):
		return Color(float(d["r"]), float(d["g"]), float(d["b"]), float(d.get("a", 1.0)))
	return value

func _to_color(value: Variant) -> Color:
	if value is Color:      return value
	if value is Dictionary: return Color(float(value.get("r", 1)), float(value.get("g", 1)), float(value.get("b", 1)), float(value.get("a", 1)))
	if value is String and not (value as String).is_empty():
		return Color.html(value)
	return Color.WHITE

func _convert_to_vector2(value: Variant) -> Vector2:
	if value is Vector2:    return value
	if value is Dictionary: return Vector2(float(value.get("x", 0)), float(value.get("y", 0)))
	if value is String:     return _str_to_vector2(value)
	return Vector2.ZERO

func _convert_to_vector3(value: Variant) -> Vector3:
	if value is Vector3:    return value
	if value is Dictionary: return Vector3(float(value.get("x", 0)), float(value.get("y", 0)), float(value.get("z", 0)))
	if value is String:     return _str_to_vector3(value)
	return Vector3.ZERO

func _str_to_vector2(s: String) -> Vector2:
	var parts := s.strip_edges().replace("(", "").replace(")", "").split(",", false)
	return Vector2(float(parts[0]), float(parts[1])) if parts.size() >= 2 else Vector2.ZERO

func _str_to_vector3(s: String) -> Vector3:
	var parts := s.strip_edges().replace("(", "").replace(")", "").split(",", false)
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2])) if parts.size() >= 3 else Vector3.ZERO

func _dup(v: Variant) -> Variant:
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	return v

func _style_color_button(btn: Button, c: Color) -> void:
	btn.text = c.to_html(false)
	var style := StyleBoxFlat.new()
	style.bg_color = c
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color.BLACK if c.get_luminance() > 0.5 else Color.WHITE)

func _spin(v: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.step = 0.001
	sb.allow_lesser = true
	sb.allow_greater = true
	sb.value = v
	return sb

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l
