@tool
extends Window
## Всплывающее окно для добавления или редактирования DBFieldDef.

signal field_confirmed(field: DBFieldDef)

var _field: DBFieldDef = null

var _name_edit: LineEdit
var _type_opt: OptionButton
var _default_edit: LineEdit
var _required_check: CheckBox
var _desc_edit: LineEdit
var _enum_section: VBoxContainer
var _enum_edit: LineEdit   # comma-separated
var _enum_mode_opt: OptionButton
var _enum_inline_box: VBoxContainer
var _enum_ref_box: VBoxContainer
var _enum_ref_opt: OptionButton
var _enum_ref_preview: Label
var _database: DBDatabase = null
var _owner_schema_name: String = ""
var _array_type_opt: OptionButton
var _nested_schema_edit: LineEdit
var _resource_hint_edit: LineEdit

var _dict_key_type_opt: OptionButton
var _dict_value_type_opt: OptionButton
var _dict_key_enum_edit: LineEdit
var _dict_key_enum_box: VBoxContainer
var _dict_key_enum_mode_opt: OptionButton
var _dict_key_enum_inline_box: VBoxContainer
var _dict_key_enum_ref_box: VBoxContainer
var _dict_key_enum_ref_opt: OptionButton
var _dict_key_enum_ref_preview: Label

var _ref_table_opt: OptionButton

const TYPE_LABELS := [
	"int", "float", "string", "bool", "enum",
	"Vector2", "Vector3", "Color",
	"Resource Ref", "Array", "Nested Object", "Dictionary",
	"Table Ref"
]

func _ready() -> void:
	title = "Field Definition"
	min_size = Vector2i(440, 520)
	close_requested.connect(hide)
	_build_ui()

func _build_ui() -> void:
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
	vbox.custom_minimum_size.x = 420
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	# Имя поля
	grid.add_child(_lbl("Field Name *"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. hp, attack_name"
	grid.add_child(_name_edit)

	# Тип
	grid.add_child(_lbl("Data Type *"))
	_type_opt = OptionButton.new()
	for t in TYPE_LABELS:
		_type_opt.add_item(t)
	_type_opt.item_selected.connect(_on_type_changed)
	grid.add_child(_type_opt)

	# Значение по умолчанию
	grid.add_child(_lbl("Default Value"))
	_default_edit = LineEdit.new()
	_default_edit.placeholder_text = "leave empty for type default"
	grid.add_child(_default_edit)

	# Обязательное
	grid.add_child(_lbl("Required"))
	_required_check = CheckBox.new()
	_required_check.text = ""
	grid.add_child(_required_check)

	# Описание
	grid.add_child(_lbl("Description"))
	_desc_edit = LineEdit.new()
	grid.add_child(_desc_edit)

	vbox.add_child(HSeparator.new())

	# ── Секции для конкретных типов ────────────────────────────────────────────
	_enum_section = VBoxContainer.new()
	vbox.add_child(_enum_section)

	var mode_row := HBoxContainer.new()
	mode_row.add_child(_lbl("Enum source:"))
	_enum_mode_opt = OptionButton.new()
	_enum_mode_opt.add_item("Inline values", 0)
	_enum_mode_opt.add_item("Reference existing enum", 1)
	_enum_mode_opt.item_selected.connect(_on_enum_mode_changed)
	mode_row.add_child(_enum_mode_opt)
	_enum_section.add_child(mode_row)

	_enum_inline_box = VBoxContainer.new()
	_enum_inline_box.add_child(_lbl("Enum Values (comma-separated):"))
	_enum_edit = LineEdit.new()
	_enum_edit.placeholder_text = "e.g. Fire,Ice,Thunder"
	_enum_inline_box.add_child(_enum_edit)
	_enum_section.add_child(_enum_inline_box)

	_enum_ref_box = VBoxContainer.new()
	_enum_ref_box.add_child(_lbl("Reference enum from:"))
	_enum_ref_opt = OptionButton.new()
	_enum_ref_opt.fit_to_longest_item = false
	_enum_ref_opt.search_bar_enabled = true
	_enum_ref_opt.custom_maximum_size.x = 300
	_enum_ref_opt.item_selected.connect(func(_i): _update_enum_ref_preview())
	_enum_ref_box.add_child(_enum_ref_opt)
	_enum_ref_preview = Label.new()
	_enum_ref_preview.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_enum_ref_preview.custom_maximum_size.x = 300
	_enum_ref_preview.autowrap_mode = TextServer.AUTOWRAP_WORD
	_enum_ref_box.add_child(_enum_ref_preview)
	_enum_section.add_child(_enum_ref_box)

	_enum_section.hide()

	var arr_section := VBoxContainer.new()
	vbox.add_child(arr_section)
	arr_section.add_child(_lbl("Array Element Type:"))
	_array_type_opt = OptionButton.new()
	for t in TYPE_LABELS:
		_array_type_opt.add_item(t)
	arr_section.add_child(_array_type_opt)
	arr_section.hide()
	_array_type_opt.set_meta("section", arr_section)

	var nested_section := VBoxContainer.new()
	vbox.add_child(nested_section)
	nested_section.add_child(_lbl("Nested / Ref Schema Name:"))
	_nested_schema_edit = LineEdit.new()
	_nested_schema_edit.placeholder_text = "table/schema name for nested object"
	nested_section.add_child(_nested_schema_edit)
	nested_section.hide()
	_nested_schema_edit.set_meta("section", nested_section)

	var res_section := VBoxContainer.new()
	vbox.add_child(res_section)
	res_section.add_child(_lbl("Resource Type Hint:"))
	_resource_hint_edit = LineEdit.new()
	_resource_hint_edit.placeholder_text = "e.g. Texture2D, AudioStream"
	res_section.add_child(_resource_hint_edit)
	res_section.hide()
	_resource_hint_edit.set_meta("section", res_section)

	var ref_section := VBoxContainer.new()
	vbox.add_child(ref_section)
	ref_section.add_child(_lbl("Reference Table (source of IDs):"))
	_ref_table_opt = OptionButton.new()
	_ref_table_opt.search_bar_enabled = true
	_ref_table_opt.fit_to_longest_item = false
	_ref_table_opt.custom_maximum_size.x = 300
	ref_section.add_child(_ref_table_opt)
	ref_section.hide()
	_ref_table_opt.set_meta("section", ref_section)

	var dict_section := VBoxContainer.new()
	vbox.add_child(dict_section)
	dict_section.add_child(_lbl("Dictionary Key Type:"))
	_dict_key_type_opt = OptionButton.new()
	for t in TYPE_LABELS:
		_dict_key_type_opt.add_item(t)
	dict_section.add_child(_dict_key_type_opt)

	# ── Значения enum для КЛЮЧА: видно ТОЛЬКО если ключ — enum (пункт 1) ─────────
	_dict_key_enum_box = VBoxContainer.new()
	dict_section.add_child(_dict_key_enum_box)

	var key_mode_row := HBoxContainer.new()
	key_mode_row.add_child(_lbl("Key enum source:"))
	_dict_key_enum_mode_opt = OptionButton.new()
	_dict_key_enum_mode_opt.add_item("Inline values", 0)
	_dict_key_enum_mode_opt.add_item("Reference existing enum", 1)
	_dict_key_enum_mode_opt.item_selected.connect(_on_dict_key_enum_mode_changed)
	key_mode_row.add_child(_dict_key_enum_mode_opt)
	_dict_key_enum_box.add_child(key_mode_row)

	_dict_key_enum_inline_box = VBoxContainer.new()
	_dict_key_enum_inline_box.add_child(_lbl("Key Enum Values (comma-separated):"))
	_dict_key_enum_edit = LineEdit.new()
	_dict_key_enum_edit.placeholder_text = "e.g. STRENGTH,DEXTERITY,INTELLIGENCE"
	_dict_key_enum_inline_box.add_child(_dict_key_enum_edit)
	_dict_key_enum_box.add_child(_dict_key_enum_inline_box)

	_dict_key_enum_ref_box = VBoxContainer.new()
	_dict_key_enum_ref_box.add_child(_lbl("Reference enum from:"))
	_dict_key_enum_ref_opt = OptionButton.new()
	_dict_key_enum_ref_opt.fit_to_longest_item = false
	_dict_key_enum_ref_opt.search_bar_enabled = true
	_dict_key_enum_ref_opt.custom_maximum_size.x = 300
	_dict_key_enum_ref_opt.item_selected.connect(func(_i): _update_dict_key_enum_ref_preview())
	_dict_key_enum_ref_box.add_child(_dict_key_enum_ref_opt)
	_dict_key_enum_ref_preview = Label.new()
	_dict_key_enum_ref_preview.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_dict_key_enum_ref_preview.custom_maximum_size.x = 300
	_dict_key_enum_ref_preview.autowrap_mode = TextServer.AUTOWRAP_WORD
	_dict_key_enum_ref_box.add_child(_dict_key_enum_ref_preview)
	_dict_key_enum_box.add_child(_dict_key_enum_ref_box)

	dict_section.add_child(_lbl("Dictionary Value Type:"))
	_dict_value_type_opt = OptionButton.new()
	for t in TYPE_LABELS:
		_dict_value_type_opt.add_item(t)
	dict_section.add_child(_dict_value_type_opt)
	dict_section.hide()
	_dict_key_type_opt.set_meta("section", dict_section)

	# Сохраняем ссылки на секции в метаданных type_opt для переключения видимости
	_type_opt.set_meta("enum_sect",   _enum_section)
	_type_opt.set_meta("arr_sect",    _array_type_opt.get_meta("section"))
	_type_opt.set_meta("nest_sect",   _nested_schema_edit.get_meta("section"))
	_type_opt.set_meta("res_sect",    _resource_hint_edit.get_meta("section"))
	_type_opt.set_meta("dict_sect", _dict_key_type_opt.get_meta("section"))

	vbox.add_child(HSeparator.new())

	# ── Кнопки ──────────────────────────────────────────────────────────────────
	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(sp)
	var cancel_btn := Button.new(); cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(hide)
	btn_row.add_child(cancel_btn)
	var ok_btn := Button.new(); ok_btn.text = "OK"
	ok_btn.pressed.connect(_on_ok)
	btn_row.add_child(ok_btn)


func open(field: DBFieldDef) -> void:
	if not _array_type_opt.item_selected.is_connected(_on_array_elem_type_changed):
		_array_type_opt.item_selected.connect(_on_array_elem_type_changed)
	if not _dict_value_type_opt.item_selected.is_connected(_on_array_elem_type_changed):
		_dict_value_type_opt.item_selected.connect(_on_array_elem_type_changed)
	if not _dict_key_type_opt.item_selected.is_connected(_on_array_elem_type_changed):
		_dict_key_type_opt.item_selected.connect(_on_array_elem_type_changed)

	if field == null:
		_field = DBFieldDef.new()
		_name_edit.text = ""
		_type_opt.selected = DBFieldDef.FieldType.STRING
		_default_edit.text = ""
		_required_check.button_pressed = false
		_desc_edit.text = ""
		_enum_edit.text = ""
		_enum_mode_opt.selected = 0
		_array_type_opt.selected = DBFieldDef.FieldType.STRING
		_nested_schema_edit.text = ""
		_resource_hint_edit.text = ""
		_dict_key_type_opt.selected   = DBFieldDef.FieldType.STRING
		_dict_value_type_opt.selected = DBFieldDef.FieldType.STRING
		_dict_key_enum_edit.text = ""
		_dict_key_enum_mode_opt.selected = 0
	else:
		_field = field
		_name_edit.text      = field.field_name
		_type_opt.selected   = field.field_type
		_default_edit.text = DBFieldDef.format_value_for_display(field.default_value) if field.default_value != null else ""
		_required_check.button_pressed = field.required
		_desc_edit.text      = field.description
		_enum_edit.text = ",".join(Array(field.enum_values))
		_enum_mode_opt.selected = 1 if not field.enum_ref.is_empty() else 0
		_array_type_opt.selected = field.array_element_type
		_nested_schema_edit.text = field.nested_schema_name
		_resource_hint_edit.text = field.resource_type_hint
		_dict_key_type_opt.selected   = field.dict_key_type
		_dict_value_type_opt.selected = field.dict_value_type
		_dict_key_enum_edit.text = ",".join(Array(field.dict_key_enum_values))
		_dict_key_enum_mode_opt.selected = 1 if not field.dict_key_enum_ref.is_empty() else 0
	_on_type_changed(_type_opt.selected)
	_on_enum_mode_changed(_enum_mode_opt.selected)
	if _enum_mode_opt.selected == 1:
		_select_enum_ref(_field.enum_ref)
	_on_dict_key_enum_mode_changed(_dict_key_enum_mode_opt.selected)
	if _dict_key_enum_mode_opt.selected == 1:
		_select_dict_key_enum_ref(_field.dict_key_enum_ref)
	_populate_ref_tables()
	if field != null:
		_select_ref_table(field.ref_table_name)
	popup_centered()

func _select_dict_key_enum_ref(key: String) -> void:
	for i in range(_dict_key_enum_ref_opt.item_count):
		if str(_dict_key_enum_ref_opt.get_item_metadata(i)) == key:
			_dict_key_enum_ref_opt.selected = i
			break
	_update_dict_key_enum_ref_preview()

func _on_type_changed(_idx: int) -> void:
	_update_type_sections()

func _on_array_elem_type_changed(_idx: int) -> void:
	_update_type_sections()

func _update_type_sections() -> void:
	var t: int = _type_opt.selected
	var is_array := (t == DBFieldDef.FieldType.ARRAY)
	var is_dict  := (t == DBFieldDef.FieldType.DICTIONARY)

	var elem_type := _array_type_opt.selected
	var elem_is_enum   := is_array and (elem_type == DBFieldDef.FieldType.ENUM)
	var elem_is_nested := is_array and (elem_type == DBFieldDef.FieldType.NESTED_OBJECT)
	var elem_is_dict   := is_array and (elem_type == DBFieldDef.FieldType.DICTIONARY)

	# «Словарь» — это и сам Dictionary, и Array<Dictionary>: типы ключа/значения берём из dict-секции
	var dict_like := is_dict or elem_is_dict
	var dict_val_is_enum := dict_like and (_dict_value_type_opt.selected == DBFieldDef.FieldType.ENUM)
	var dict_key_is_enum := dict_like and (_dict_key_type_opt.selected == DBFieldDef.FieldType.ENUM)

	_enum_section.visible                           = (t == DBFieldDef.FieldType.ENUM) or elem_is_enum or dict_val_is_enum
	_array_type_opt.get_meta("section").visible     = is_array
	_dict_key_type_opt.get_meta("section").visible  = dict_like
	_nested_schema_edit.get_meta("section").visible = (t == DBFieldDef.FieldType.NESTED_OBJECT) or is_dict or elem_is_nested
	var uses_resource_ref := t == DBFieldDef.FieldType.RESOURCE_REF \
		or (is_array and elem_type == DBFieldDef.FieldType.RESOURCE_REF) \
		or (dict_like and _dict_key_type_opt.selected == DBFieldDef.FieldType.RESOURCE_REF) \
		or (dict_like and _dict_value_type_opt.selected == DBFieldDef.FieldType.RESOURCE_REF)

	_resource_hint_edit.get_meta("section").visible = uses_resource_ref

	var uses_table_ref := t == DBFieldDef.FieldType.TABLE_REF \
		or (is_array and elem_type == DBFieldDef.FieldType.TABLE_REF) \
		or (dict_like and _dict_value_type_opt.selected == DBFieldDef.FieldType.TABLE_REF) \
		or (dict_like and _dict_key_type_opt.selected == DBFieldDef.FieldType.TABLE_REF)
	_ref_table_opt.get_meta("section").visible = uses_table_ref

	_dict_key_enum_box.visible = dict_key_is_enum

func _on_ok() -> void:
	var name := _name_edit.text.strip_edges()
	if name.is_empty():
		push_warning("[GD Database] Field name cannot be empty.")
		return
	_field.field_name         = name
	_field.field_type         = _type_opt.selected as DBFieldDef.FieldType
	_field.required           = _required_check.button_pressed
	_field.description        = _desc_edit.text.strip_edges()
	_field.array_element_type = _array_type_opt.selected as DBFieldDef.FieldType
	_field.dict_key_type      = _dict_key_type_opt.selected as DBFieldDef.FieldType
	_field.dict_value_type    = _dict_value_type_opt.selected as DBFieldDef.FieldType

	# Поле ведёт себя как словарь: Dictionary ИЛИ Array<Dictionary>
	var field_is_dict_like := _field.field_type == DBFieldDef.FieldType.DICTIONARY \
		or (_field.field_type == DBFieldDef.FieldType.ARRAY \
			and _field.array_element_type == DBFieldDef.FieldType.DICTIONARY)

	if field_is_dict_like and _field.dict_key_type == DBFieldDef.FieldType.ENUM:
		if _dict_key_enum_mode_opt.selected == 1:
			var kref := _selected_dict_key_enum_ref()
			_field.dict_key_enum_ref = kref          # ИСПРАВЛЕНИЕ: запоминаем ссылку
			if _database and not kref.is_empty():
				_field.dict_key_enum_values = _database.get_enum_values_for_ref(kref)
			else:
				_field.dict_key_enum_values = PackedStringArray()
		else:
			_field.dict_key_enum_ref = ""            # ИСПРАВЛЕНИЕ: inline → ссылки нет
			_field.dict_key_enum_values = PackedStringArray(_dict_key_enum_edit.text.split(",", false))
	else:
		_field.dict_key_enum_ref = ""                # FIX
		_field.dict_key_enum_values = PackedStringArray(_dict_key_enum_edit.text.split(",", false))

	var uses_table_ref := _field.field_type == DBFieldDef.FieldType.TABLE_REF \
		or (_field.field_type == DBFieldDef.FieldType.ARRAY \
			and _field.array_element_type == DBFieldDef.FieldType.TABLE_REF) \
		or (field_is_dict_like and (_field.dict_value_type == DBFieldDef.FieldType.TABLE_REF \
			or _field.dict_key_type == DBFieldDef.FieldType.TABLE_REF))

	var uses_enum := _field.field_type == DBFieldDef.FieldType.ENUM \
		or (_field.field_type == DBFieldDef.FieldType.ARRAY \
			and _field.array_element_type == DBFieldDef.FieldType.ENUM) \
		or (field_is_dict_like and _field.dict_value_type == DBFieldDef.FieldType.ENUM)

	if uses_enum and _enum_mode_opt.selected == 1:
		var ref := _selected_enum_ref()
		_field.enum_ref = ref
		if _database and not ref.is_empty():
			_field.enum_values = _database.get_enum_values_for_ref(ref)
	elif uses_enum:
		_field.enum_ref = ""
		_field.enum_values = PackedStringArray(_enum_edit.text.split(",", false))
	else:
		_field.enum_ref = ""
		_field.enum_values = PackedStringArray()

	_field.nested_schema_name = _nested_schema_edit.text.strip_edges()
	_field.resource_type_hint = _resource_hint_edit.text.strip_edges()
	_field.ref_table_name = _selected_ref_table() if uses_table_ref else ""

	var dv_str := _default_edit.text.strip_edges()
	if not dv_str.is_empty():
		_field.default_value = _parse_default(dv_str, _field.field_type)
	else:
		_field.default_value = null
	hide()
	field_confirmed.emit(_field)


func _parse_default(s: String, t: DBFieldDef.FieldType) -> Variant:
	match t:
		DBFieldDef.FieldType.INT:   return int(s)
		DBFieldDef.FieldType.FLOAT: return float(s)
		DBFieldDef.FieldType.BOOL:  return s.to_lower() in ["true", "1", "yes"]
		DBFieldDef.FieldType.ENUM:  return int(s)
		DBFieldDef.FieldType.VECTOR2:
			return _str_to_vector2(s)
		DBFieldDef.FieldType.VECTOR3:
			return _str_to_vector3(s)
		_:                          return s

func _str_to_vector2(s: String) -> Vector2:
	var clean := s.strip_edges().replace("(", "").replace(")", "")
	var parts := clean.split(",", false)
	if parts.size() >= 2:
		return Vector2(float(parts[0]), float(parts[1]))
	return Vector2.ZERO

func _str_to_vector3(s: String) -> Vector3:
	var clean := s.strip_edges().replace("(", "").replace(")", "")
	var parts := clean.split(",", false)
	if parts.size() >= 3:
		return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return Vector3.ZERO

func _lbl(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func set_context(db: DBDatabase, owner_schema_name: String) -> void:
	_database = db
	_owner_schema_name = owner_schema_name

func _on_enum_mode_changed(idx: int) -> void:
	_enum_inline_box.visible = (idx == 0)
	_enum_ref_box.visible    = (idx == 1)
	if idx == 1:
		_populate_enum_refs()
		_update_enum_ref_preview()

func _on_dict_key_enum_mode_changed(idx: int) -> void:
	_dict_key_enum_inline_box.visible = (idx == 0)
	_dict_key_enum_ref_box.visible    = (idx == 1)
	if idx == 1:
		_populate_dict_key_enum_refs()
		_update_dict_key_enum_ref_preview()

func _populate_dict_key_enum_refs() -> void:
	_dict_key_enum_ref_opt.clear()
	if _database == null:
		_dict_key_enum_ref_opt.add_item("(no database)")
		_dict_key_enum_ref_opt.set_item_metadata(0, "")
		return
	var sources := _database.collect_enum_sources()
	var keys := sources.keys()
	keys.sort()
	var own_key := ""
	if not _owner_schema_name.is_empty() and not _field.field_name.is_empty():
		own_key = "%s/%s" % [_owner_schema_name, _field.field_name]
	var added := 0
	for k in keys:
		if k == own_key:
			continue   # нельзя ссылаться сам на себя
		var vals: PackedStringArray = sources[k]
		_dict_key_enum_ref_opt.add_item("%s  [%s]" % [k, ", ".join(vals)])
		_dict_key_enum_ref_opt.set_item_metadata(_dict_key_enum_ref_opt.item_count - 1, k)
		added += 1
	if added == 0:
		_dict_key_enum_ref_opt.add_item("(no enums defined elsewhere)")
		_dict_key_enum_ref_opt.set_item_metadata(0, "")

func _selected_dict_key_enum_ref() -> String:
	if _dict_key_enum_ref_opt.item_count == 0:
		return ""
	var md = _dict_key_enum_ref_opt.get_item_metadata(_dict_key_enum_ref_opt.selected)
	return str(md) if md != null else ""

func _update_dict_key_enum_ref_preview() -> void:
	var key := _selected_dict_key_enum_ref()
	if key.is_empty() or _database == null:
		_dict_key_enum_ref_preview.text = ""
		return
	_dict_key_enum_ref_preview.text = "Values: " + ", ".join(_database.get_enum_values_for_ref(key))


func _populate_enum_refs() -> void:
	_enum_ref_opt.clear()
	if _database == null:
		_enum_ref_opt.add_item("(no database)")
		_enum_ref_opt.set_item_metadata(0, "")
		return
	var sources := _database.collect_enum_sources()
	var keys := sources.keys()
	keys.sort()
	var own_key := ""
	if not _owner_schema_name.is_empty() and not _field.field_name.is_empty():
		own_key = "%s/%s" % [_owner_schema_name, _field.field_name]
	var added := 0
	for k in keys:
		if k == own_key:
			continue   # нельзя ссылаться сам на себя
		var vals: PackedStringArray = sources[k]
		_enum_ref_opt.add_item("%s  [%s]" % [k, ", ".join(vals)])
		_enum_ref_opt.set_item_metadata(_enum_ref_opt.item_count - 1, k)
		added += 1
	if added == 0:
		_enum_ref_opt.add_item("(no enums defined elsewhere)")
		_enum_ref_opt.set_item_metadata(0, "")

func _selected_enum_ref() -> String:
	if _enum_ref_opt.item_count == 0:
		return ""
	var md = _enum_ref_opt.get_item_metadata(_enum_ref_opt.selected)
	return str(md) if md != null else ""

func _select_enum_ref(key: String) -> void:
	for i in range(_enum_ref_opt.item_count):
		if str(_enum_ref_opt.get_item_metadata(i)) == key:
			_enum_ref_opt.selected = i
			break
	_update_enum_ref_preview()

func _update_enum_ref_preview() -> void:
	var key := _selected_enum_ref()
	if key.is_empty() or _database == null:
		_enum_ref_preview.text = ""
		return
	_enum_ref_preview.text = "Values: " + ", ".join(_database.get_enum_values_for_ref(key))

func _populate_ref_tables() -> void:
	_ref_table_opt.clear()
	if _database == null:
		_ref_table_opt.add_item("(no database)")
		_ref_table_opt.set_item_metadata(0, "")
		return
	for tname in _database.get_table_names():
		var t := _database.get_table(tname)
		var cnt := t.entries.size() if t else 0
		_ref_table_opt.add_item("%s  (%d rows)" % [tname, cnt])
		_ref_table_opt.set_item_metadata(_ref_table_opt.item_count - 1, tname)
	if _ref_table_opt.item_count == 0:
		_ref_table_opt.add_item("(no tables)")
		_ref_table_opt.set_item_metadata(0, "")

func _select_ref_table(name: String) -> void:
	for i in range(_ref_table_opt.item_count):
		if str(_ref_table_opt.get_item_metadata(i)) == name:
			_ref_table_opt.selected = i
			return

func _selected_ref_table() -> String:
	if _ref_table_opt.item_count == 0:
		return ""
	var md = _ref_table_opt.get_item_metadata(_ref_table_opt.selected)
	return str(md) if md != null else ""
