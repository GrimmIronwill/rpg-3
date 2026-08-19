@tool
extends Window
class_name SchemaDialog
## Создаёт новую схему (таблицу) или редактирует существующую.

const FieldDialog = preload("res://addons/gd_database/editor/dialogs/field_dialog.gd")

signal schema_created(result: Array)    # [DBSchema, table_name]
signal schema_changed(result: Array) # [old_table_name, new_table_name]

var _database: DBDatabase = null
var _schema: DBSchema = null
var _is_new: bool = false
var _editing_table_name: String = ""

var _name_edit: LineEdit
var _table_name_edit: LineEdit
var _desc_edit: LineEdit
var _field_list: ItemList
var _field_dialog: Window

func _ready() -> void:
	title = "Schema Editor"
	min_size = Vector2i(560, 480)
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
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# ── Мета-данные ─────────────────────────────────────────────────────────────
	var meta_grid := GridContainer.new()
	meta_grid.columns = 2
	vbox.add_child(meta_grid)

	meta_grid.add_child(_lbl("Schema Name:"))
	_name_edit = LineEdit.new(); _name_edit.custom_minimum_size.x = 280
	meta_grid.add_child(_name_edit)

	meta_grid.add_child(_lbl("Table Name:"))
	_table_name_edit = LineEdit.new(); _table_name_edit.custom_minimum_size.x = 280
	meta_grid.add_child(_table_name_edit)

	meta_grid.add_child(_lbl("Description:"))
	_desc_edit = LineEdit.new(); _desc_edit.custom_minimum_size.x = 280
	meta_grid.add_child(_desc_edit)

	vbox.add_child(HSeparator.new())

	var field_hdr := HBoxContainer.new()
	field_hdr.add_child(_lbl("Fields"))
	var add_field_btn := Button.new()
	add_field_btn.text = "+ Add Field"
	add_field_btn.pressed.connect(_on_add_field)
	field_hdr.add_child(add_field_btn)
	var edit_field_btn := Button.new()
	edit_field_btn.text = "✎ Edit"
	edit_field_btn.pressed.connect(_on_edit_field)
	field_hdr.add_child(edit_field_btn)
	var del_field_btn := Button.new()
	del_field_btn.text = "− Remove"
	del_field_btn.pressed.connect(_on_remove_field)
	field_hdr.add_child(del_field_btn)
	var up_btn := Button.new()
	up_btn.text = "▲"
	up_btn.pressed.connect(func(): _move_field(-1))
	field_hdr.add_child(up_btn)
	var dn_btn := Button.new()
	dn_btn.text = "▼"
	dn_btn.pressed.connect(func(): _move_field(1))
	field_hdr.add_child(dn_btn)
	vbox.add_child(field_hdr)

	_field_list = ItemList.new()
	_field_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_field_list.custom_minimum_size.y = 220
	_field_list.item_activated.connect(func(_i): _on_edit_field())
	vbox.add_child(_field_list)

	# ── Нижние кнопки ───────────────────────────────────────────────────────────
	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(hide)
	btn_row.add_child(cancel_btn)
	var ok_btn := Button.new()
	ok_btn.text = "OK"
	ok_btn.pressed.connect(_on_ok)
	btn_row.add_child(ok_btn)

	# ── Диалог поля ─────────────────────────────────────────────────────────────
	_field_dialog = FieldDialog.new()
	_field_dialog.hide()
	add_child(_field_dialog)


# ──────────────────────────────────────────────────────────────────────────────

func open(schema: DBSchema, db: DBDatabase, table_name: String = "") -> void:
	_schema   = schema
	_database = db
	_is_new   = false
	_editing_table_name = table_name

	_name_edit.text = schema.schema_name

	# Важно: имя таблицы не равно имени схемы.
	_table_name_edit.text = table_name if not table_name.is_empty() else schema.schema_name

	_desc_edit.text = schema.description
	_refresh_field_list()
	popup_centered()

func open_new(db: DBDatabase) -> void:
	_schema   = DBSchema.new()
	_database = db
	_is_new   = true
	_name_edit.text       = "NewSchema"
	_table_name_edit.text = "NewTable"
	_desc_edit.text       = ""
	_refresh_field_list()
	popup_centered()

func _refresh_field_list() -> void:
	_field_list.clear()
	if _schema == null:
		return

	for f: DBFieldDef in _schema.fields:
		var req := " *" if f.required else ""

		var text := "%s : %s%s" % [
			f.field_name,
			f.get_type_label(),
			req
		]

		if not f.description.strip_edges().is_empty():
			text += " — " + f.description.strip_edges()

		_field_list.add_item(text)

		var idx := _field_list.item_count - 1
		_field_list.set_item_metadata(idx, f.field_name)

		if not f.description.strip_edges().is_empty():
			_field_list.set_item_tooltip(idx, f.description.strip_edges())

func _on_add_field() -> void:
	_field_dialog.set_context(_database, _name_edit.text.strip_edges())
	_field_dialog.open(null)
	var result = await _field_dialog.field_confirmed
	if result == null: return
	_schema.add_field(result as DBFieldDef)
	_refresh_field_list()

func _on_edit_field() -> void:
	var idxs := _field_list.get_selected_items()
	if idxs.is_empty(): return
	var fname: String = _field_list.get_item_metadata(idxs[0])
	var f := _schema.get_field(fname)
	if f == null: return
	_field_dialog.set_context(_database, _name_edit.text.strip_edges())
	_field_dialog.open(f)
	await _field_dialog.field_confirmed
	_refresh_field_list()

func _on_remove_field() -> void:
	var idxs := _field_list.get_selected_items()
	if idxs.is_empty(): return
	var fname: String = _field_list.get_item_metadata(idxs[0])
	_schema.remove_field(fname)
	_refresh_field_list()

func _move_field(delta: int) -> void:
	var idxs := _field_list.get_selected_items()
	if idxs.is_empty(): return
	var fname: String = _field_list.get_item_metadata(idxs[0])
	for i: int in range(_schema.fields.size()):
		if _schema.fields[i].field_name == fname:
			_schema.move_field(i, i + delta)
			break
	_refresh_field_list()

func _on_ok() -> void:
	_schema.schema_name = _name_edit.text.strip_edges()
	_schema.description = _desc_edit.text.strip_edges()

	var tname := _table_name_edit.text.strip_edges()
	if tname.is_empty():
		push_warning("[GD Database] Table name cannot be empty.")
		return

	hide()

	if _is_new:
		schema_created.emit([_schema, tname])
	else:
		schema_changed.emit([_editing_table_name, tname])

func _lbl(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l
