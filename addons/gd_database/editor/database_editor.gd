@tool
extends PanelContainer
class_name DatabaseEditor
## Корневая панель, добавляемая в нижний док редактора Godot.

var _plugin: EditorPlugin = null
var _database: DBDatabase = null
var _db_path: String = ""

var _split: HSplitContainer
var _table_list: Control
var _entry_view: Control
var _import_export_dialog: Window

var _top_bar: HBoxContainer
var _db_name_label: Label
var _save_btn: Button
var _new_db_btn: Button
var _open_db_btn: Button
var _io_btn: Button
var _gen_enums_btn: Button

var _current_table_name: String = ""

# ──────────────────────────────────────────────────────────────────────────────

func set_plugin(p: EditorPlugin) -> void:
	_plugin = p

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	custom_minimum_size = Vector2(900, 340)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	# ── Верхняя панель ──────────────────────────────────────────────────────────
	_top_bar = HBoxContainer.new()
	_top_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(_top_bar)

	_db_name_label = Label.new()
	_db_name_label.text = "No database loaded"
	_db_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_bar.add_child(_db_name_label)

	_new_db_btn = Button.new()
	_new_db_btn.text = "New DB"
	_new_db_btn.tooltip_text = "Create a new database resource"
	_new_db_btn.pressed.connect(_on_new_db)
	_top_bar.add_child(_new_db_btn)

	_open_db_btn = Button.new()
	_open_db_btn.text = "Open DB"
	_open_db_btn.tooltip_text = "Load an existing DBDatabase .tres file"
	_open_db_btn.pressed.connect(_on_open_db)
	_top_bar.add_child(_open_db_btn)

	_save_btn = Button.new()
	_save_btn.text = "💾 Save"
	_save_btn.tooltip_text = "Save database resource to disk"
	_save_btn.pressed.connect(save_current_database)
	_save_btn.disabled = true
	_top_bar.add_child(_save_btn)

	_io_btn = Button.new()
	_io_btn.text = "Import / Export"
	_io_btn.pressed.connect(_on_import_export)
	_io_btn.disabled = true
	_top_bar.add_child(_io_btn)

	_gen_enums_btn = Button.new()
	_gen_enums_btn.text = "⚙ Gen Enums"
	_gen_enums_btn.tooltip_text = "Сгенерировать .gd с enum'ами из всех схем"
	_gen_enums_btn.pressed.connect(_on_gen_enums)
	_gen_enums_btn.disabled = true
	_top_bar.add_child(_gen_enums_btn)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# ── Основной сплиттер ───────────────────────────────────────────────────────
	_split = HSplitContainer.new()
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split.split_offset = 220
	vbox.add_child(_split)

	_table_list = TableListPanel.new()
	_table_list.custom_minimum_size.x = 180
	_table_list.table_selected.connect(_on_table_selected)
	_table_list.table_renamed.connect(_on_table_renamed)
	_table_list.table_deleted.connect(_on_table_deleted)
	_split.add_child(_table_list)

	_entry_view = EntryTableView.new()
	_entry_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry_view.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_entry_view.data_changed.connect(_on_data_changed)
	_split.add_child(_entry_view)

	# ── Диалог импорта/экспорта ─────────────────────────────────────────────────
	_import_export_dialog = ImportExportDlg.new()
	_import_export_dialog.hide()
	add_child(_import_export_dialog)

# ──────────────────────────────────────────────────────────────────────────────
# Публичный API
# ──────────────────────────────────────────────────────────────────────────────

func load_database(db: DBDatabase) -> void:
	_database = db
	_database.resolve_enum_refs()
	_db_path  = db.resource_path
	_current_table_name = ""

	_db_name_label.text = "DB: %s  [%s]" % [db.database_name, _db_path.get_file()]
	_save_btn.disabled = false
	_io_btn.disabled   = false
	_gen_enums_btn.disabled = false

	if _table_list:
		_table_list.refresh(_database)

	_entry_view.clear()

func save_current_database() -> void:
	if _database == null: return
	_database.resolve_enum_refs()
	var path := _database.resource_path
	if path.is_empty():
		_show_save_dialog()
		return
	var err := ResourceSaver.save(_database, path)
	if err != OK:
		push_error("[GD Database] Failed to save: %s" % error_string(err))
	else:
		print("[GD Database] Saved → %s" % path)

# ──────────────────────────────────────────────────────────────────────────────
# Обратные вызовы
# ──────────────────────────────────────────────────────────────────────────────

func _on_new_db() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "New Database"
	var vb := VBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Database name"
	name_edit.text = "MyDatabase"
	vb.add_child(name_edit)
	var path_edit := LineEdit.new()
	path_edit.placeholder_text = "Save path (res://data/my_db.tres)"
	path_edit.text = "res://data/my_database.tres"
	vb.add_child(path_edit)
	dialog.add_child(vb)
	add_child(dialog)
	dialog.popup_centered(Vector2i(360, 120))
	await dialog.confirmed
	var db := DBDatabase.new()
	db.database_name = name_edit.text.strip_edges()
	db.resource_path = path_edit.text.strip_edges()
	var err := ResourceSaver.save(db, db.resource_path)
	if err == OK:
		load_database(db)
	else:
		push_error("[GD Database] Could not create DB at %s" % db.resource_path)
	dialog.queue_free()

func _on_open_db() -> void:
	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.add_filter("*.tres,*.res", "Godot Resource")
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 550))
	dialog.file_selected.connect(func(path: String) -> void:
		var res := ResourceLoader.load(path)
		if res is DBDatabase:
			load_database(res as DBDatabase)
		else:
			push_error("[GD Database] Selected file is not a DBDatabase resource.")
		dialog.queue_free()
	)

func _show_save_dialog() -> void:
	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.tres", "Text Resource")
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 550))
	dialog.file_selected.connect(func(path: String) -> void:
		_database.resource_path = path
		ResourceSaver.save(_database, path)
		dialog.queue_free()
	)

func _on_table_selected(table_name: String) -> void:
	if _database == null:
		return

	_current_table_name = table_name

	_database.resolve_enum_refs()
	var t := _database.get_table(table_name)
	if t:
		_entry_view.load_table(t, _database)

func _on_table_renamed(old_name: String, new_name: String) -> void:
	if _database == null:
		return

	if _database.rename_table(old_name, new_name):
		if _current_table_name == old_name:
			_current_table_name = new_name

	_table_list.refresh(_database, _current_table_name)

func _on_table_deleted(table_name: String) -> void:
	if _database == null:
		return

	_database.remove_table(table_name)

	if _current_table_name == table_name:
		_current_table_name = ""

	_entry_view.clear()
	_table_list.refresh(_database)

func _on_data_changed() -> void:
	if _database:
		_database.emit_changed()

	if _table_list:
		_table_list.refresh(_database, _current_table_name)

func _on_import_export() -> void:
	if _database:
		_import_export_dialog.open(_database)

func _on_gen_enums() -> void:
	if _database == null:
		return
	_database.resolve_enum_refs()

	var dlg := ConfirmationDialog.new()
	dlg.title = "Generate Enums"
	dlg.min_size = Vector2i(480, 560)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dlg.add_child(vb)

	# ── Enum-поля (значения) ────────────────────────────────────────────────
	var hdr := Label.new()
	hdr.text = "Enum-поля (значения):"
	vb.add_child(hdr)

	var enum_scroll := ScrollContainer.new()
	enum_scroll.custom_minimum_size.y = 170
	enum_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(enum_scroll)
	var enum_box := VBoxContainer.new()
	enum_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enum_scroll.add_child(enum_box)

	var enum_checks: Array[CheckBox] = []
	var sources := _database.collect_enum_sources()
	var keys := sources.keys()
	keys.sort()
	for k in keys:
		var cb := CheckBox.new()
		var vals: PackedStringArray = sources[k]
		cb.text = "%s  [%s]" % [k, ", ".join(vals)]
		cb.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		cb.custom_minimum_size.x = 300
		cb.button_pressed = true
		cb.set_meta("ref", k)
		enum_box.add_child(cb)
		enum_checks.append(cb)
	if enum_checks.is_empty():
		var none := Label.new()
		none.text = "(нет самостоятельных enum-полей)"
		enum_box.add_child(none)

	var enum_btns := HBoxContainer.new()
	vb.add_child(enum_btns)
	var sel_all := Button.new(); sel_all.text = "Выбрать все"
	sel_all.pressed.connect(func() -> void:
		for cb in enum_checks: cb.button_pressed = true)
	enum_btns.add_child(sel_all)
	var sel_none := Button.new(); sel_none.text = "Снять все"
	sel_none.pressed.connect(func() -> void:
		for cb in enum_checks: cb.button_pressed = false)
	enum_btns.add_child(sel_none)

	vb.add_child(HSeparator.new())

	# ── Авто-enum имён колонок ──────────────────────────────────────────────
	var cols_check := CheckBox.new()
	cols_check.text = "Авто: enum'ы имён колонок для таблиц (обход всех полей)"
	cols_check.button_pressed = false
	vb.add_child(cols_check)

	var tbl_scroll := ScrollContainer.new()
	tbl_scroll.custom_minimum_size.y = 150
	tbl_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(tbl_scroll)
	var tbl_box := VBoxContainer.new()
	tbl_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tbl_scroll.add_child(tbl_box)

	var tbl_checks: Array[CheckBox] = []
	for tname in _database.get_table_names():
		var cb := CheckBox.new()
		cb.text = tname
		cb.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		cb.custom_minimum_size.x = 300
		cb.button_pressed = true
		cb.disabled = true
		cb.set_meta("table", tname)
		tbl_box.add_child(cb)
		tbl_checks.append(cb)
	cols_check.toggled.connect(func(on: bool) -> void:
		for cb in tbl_checks: cb.disabled = not on)

	add_child(dlg)
	dlg.popup_centered()

	dlg.confirmed.connect(func() -> void:
		var selected_refs := PackedStringArray()
		for cb in enum_checks:
			if cb.button_pressed:
				selected_refs.append(str(cb.get_meta("ref")))
		var include_columns: bool = cols_check.button_pressed
		var selected_tables := PackedStringArray()
		if include_columns:
			for cb in tbl_checks:
				if cb.button_pressed:
					selected_tables.append(str(cb.get_meta("table")))
		dlg.queue_free()
		if selected_refs.is_empty() and not include_columns:
			push_warning("[GD Database] Ничего не выбрано для генерации.")
			return
		_open_enum_save_dialog(selected_refs, include_columns, selected_tables)
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())

func _open_enum_save_dialog(enum_refs: PackedStringArray,
		include_columns: bool, column_tables: PackedStringArray) -> void:
	var dlg := EditorFileDialog.new()
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dlg.add_filter("*.gd", "GDScript")
	dlg.current_path = "res://game_enums.gd"
	add_child(dlg)
	dlg.popup_centered(Vector2i(800, 550))
	dlg.file_selected.connect(func(path: String) -> void:
		var cn := path.get_file().get_basename().to_pascal_case()
		if cn.is_empty():
			cn = "GameEnums"
		# include_value_enums = есть хотя бы одна выбранная enum-ссылка.
		var err := DBEnumExporter.export_to_file(
			_database, path, cn, enum_refs,
			not enum_refs.is_empty(), include_columns, column_tables)
		if err == OK:
			print("[GD Database] Enums → %s" % path)
			if _plugin:
				_plugin.get_editor_interface().get_resource_filesystem().scan()
		else:
			push_error("[GD Database] Не удалось сгенерировать enum'ы: %s" % error_string(err))
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())
