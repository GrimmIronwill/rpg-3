@tool
extends VBoxContainer
class_name TableListPanel

signal table_selected(table_name: String)
signal table_renamed(old_name: String, new_name: String)
signal table_deleted(table_name: String)

var _database: DBDatabase = null
var _item_list: ItemList
var _add_btn: Button
var _edit_schema_btn: Button   # новая кнопка
var _rename_btn: Button
var _del_btn: Button
var _schema_dialog: Window

func _ready() -> void:
	custom_minimum_size.x = 180

	var label := Label.new()
	label.text = "Tables"
	label.add_theme_font_size_override("font_size", 13)
	add_child(label)

	_item_list = ItemList.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.item_selected.connect(_on_item_selected)
	_item_list.item_activated.connect(_on_item_activated)   # двойной клик всё ещё работает
	add_child(_item_list)

	var btn_row := HBoxContainer.new()
	add_child(btn_row)

	_add_btn = Button.new()
	_add_btn.text = "+"
	_add_btn.tooltip_text = "Add new table"
	_add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_btn.pressed.connect(_on_add_table)
	btn_row.add_child(_add_btn)

	_edit_schema_btn = Button.new()
	_edit_schema_btn.text = "⚙"            # или иконка "Edit" при желании
	_edit_schema_btn.tooltip_text = "Edit schema (columns)"
	_edit_schema_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_schema_btn.pressed.connect(_on_edit_schema)
	btn_row.add_child(_edit_schema_btn)

	_rename_btn = Button.new()
	_rename_btn.text = "✎"
	_rename_btn.tooltip_text = "Rename table"
	_rename_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_btn.pressed.connect(_on_rename_table)
	btn_row.add_child(_rename_btn)

	_del_btn = Button.new()
	_del_btn.text = "−"
	_del_btn.tooltip_text = "Delete table"
	_del_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_del_btn.pressed.connect(_on_delete_table)
	btn_row.add_child(_del_btn)

	_schema_dialog = SchemaDialog.new()
	_schema_dialog.hide()
	add_child(_schema_dialog)

func refresh(db: DBDatabase, keep_selected: String = "") -> void:
	_database = db

	var selected_name := keep_selected

	# Если явно не передали имя — попробуем сохранить текущее выделение.
	if selected_name.is_empty() and _item_list != null:
		var idxs := _item_list.get_selected_items()
		if not idxs.is_empty():
			selected_name = str(_item_list.get_item_metadata(idxs[0]))

	_item_list.clear()

	if db == null:
		return

	var selected_idx := -1

	for name: String in db.get_table_names():
		var t := db.get_table(name)
		var count := t.entries.size() if t else 0

		_item_list.add_item("%s  (%d)" % [name, count])
		var idx := _item_list.item_count - 1
		_item_list.set_item_metadata(idx, name)

		if name == selected_name:
			selected_idx = idx

	if selected_idx >= 0:
		_item_list.select(selected_idx)

func _on_item_selected(idx: int) -> void:
	var name: String = _item_list.get_item_metadata(idx)
	table_selected.emit(name)

func _on_item_activated(idx: int) -> void:
	# Двойной клик — тоже открывает редактор схемы
	_open_schema_for_selected()

func _on_edit_schema() -> void:
	_open_schema_for_selected()

func _open_schema_for_selected() -> void:
	var idxs := _item_list.get_selected_items()
	if idxs.is_empty(): return
	var name: String = _item_list.get_item_metadata(idxs[0])
	var t := _database.get_table(name)
	if t and t.schema:
		_schema_dialog.open(t.schema, _database, name)
		var result = await _schema_dialog.schema_changed
		if result == null:
			return

		var old_name: String = result[0]
		var new_name: String = result[1]

		if new_name != old_name:
			if _database.has_table(new_name):
				push_warning("[GD Database] Table '%s' already exists." % new_name)
				refresh(_database, old_name)
				table_selected.emit(old_name)
				return

			if not _database.rename_table(old_name, new_name):
				push_warning("[GD Database] Failed to rename table '%s' to '%s'." % [old_name, new_name])
				refresh(_database, old_name)
				table_selected.emit(old_name)
				return

			refresh(_database, new_name)
			table_selected.emit(new_name)
		else:
			refresh(_database, old_name)
			table_selected.emit(old_name)


func _on_add_table() -> void:
	if _database == null: return
	_schema_dialog.open_new(_database)
	var result = await _schema_dialog.schema_created
	if result == null: return
	var schema: DBSchema = result[0]
	var table_name: String = result[1]
	if _database.has_table(table_name):
		push_warning("[GD Database] Table '%s' already exists." % table_name)
		return
	_database.create_table(table_name, schema)
	refresh(_database)
	table_selected.emit(table_name)

func _on_rename_table() -> void:
	var idxs := _item_list.get_selected_items()
	if idxs.is_empty(): return
	var old_name: String = _item_list.get_item_metadata(idxs[0])
	var dlg := AcceptDialog.new()
	dlg.title = "Rename Table"
	var edit := LineEdit.new()
	edit.text = old_name
	dlg.add_child(edit)
	add_child(dlg)
	dlg.popup_centered(Vector2i(300, 80))
	await dlg.confirmed
	var new_name := edit.text.strip_edges()
	if new_name.is_empty() or new_name == old_name:
		dlg.queue_free()
		return
	table_renamed.emit(old_name, new_name)
	dlg.queue_free()

func _on_delete_table() -> void:
	var idxs := _item_list.get_selected_items()
	if idxs.is_empty(): return
	var name: String = _item_list.get_item_metadata(idxs[0])
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete Table"
	dlg.dialog_text = "Delete table '%s' and all its entries?" % name
	add_child(dlg)
	dlg.popup_centered(Vector2i(360, 120))
	await dlg.confirmed
	table_deleted.emit(name)
	dlg.queue_free()
