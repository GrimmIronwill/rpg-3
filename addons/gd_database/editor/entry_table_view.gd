@tool
extends VBoxContainer
class_name EntryTableView
## Табличная сетка. Использует Tree в табличном режиме.

signal data_changed

var _table: DBTable = null
var _database: DBDatabase = null

# UI
var _toolbar: HBoxContainer
var _search_edit: LineEdit
var _sort_field: String = ""
var _sort_asc: bool = true
var _filter_field_opt: OptionButton
var _filter_val_edit: LineEdit
var _tree: Tree
var _status_label: Label

# Диалоги
var _array_dialog: Window
var _dict_dialog: Window
var _nested_editor: NestedObjectEditor = null
var _color_picker_popup: PopupPanel
var _color_picker: ColorPicker

const BTN_TABLE_REF = 50
var _ref_picker: TableRefPickerDialog = null

# Состояние
var _visible_entries: Array[DBEntry] = []
var _editing_entry: DBEntry = null
var _editing_field: String = ""

var _column_nav_opt: OptionButton

const COL_ID    = 0   # Всегда колонка 0

# ID кнопок, используемые внутри ячеек Tree.
const BTN_VEC2   = 10
const BTN_VEC3   = 11
const BTN_RES    = 20
const BTN_ARRAY  = 30
const BTN_NESTED = 31
const BTN_DICT   = 32
const BTN_COLOR  = 40
const BTN_DELETE = 99

# ──────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	# ── Панель инструментов ────────────────────────────────────────────────────
	_toolbar = HBoxContainer.new()
	add_child(_toolbar)

	var add_row_btn := Button.new()
	add_row_btn.text = "+ Row"
	add_row_btn.tooltip_text = "Add a new entry"
	add_row_btn.pressed.connect(_on_add_row)
	_toolbar.add_child(add_row_btn)

	var del_row_btn := Button.new()
	del_row_btn.text = "− Row"
	del_row_btn.tooltip_text = "Delete selected entry"
	del_row_btn.pressed.connect(_on_delete_row)
	_toolbar.add_child(del_row_btn)

	var dup_row_btn := Button.new()
	dup_row_btn.text = "⎘ Dup"
	dup_row_btn.tooltip_text = "Duplicate selected entry"
	dup_row_btn.pressed.connect(_on_duplicate_row)
	_toolbar.add_child(dup_row_btn)

	_toolbar.add_child(VSeparator.new())

	var filter_label := Label.new()
	filter_label.text = "Filter:"
	_toolbar.add_child(filter_label)

	_filter_field_opt = OptionButton.new()
	_filter_field_opt.custom_minimum_size.x = 110
	_filter_field_opt.item_selected.connect(func(_i): _rebuild_tree())
	_toolbar.add_child(_filter_field_opt)

	_filter_val_edit = LineEdit.new()
	_filter_val_edit.placeholder_text = "value…"
	_filter_val_edit.custom_minimum_size.x = 110
	_filter_val_edit.text_changed.connect(func(_t): _rebuild_tree())
	_toolbar.add_child(_filter_val_edit)

	_toolbar.add_child(VSeparator.new())

	var search_label := Label.new()
	search_label.text = "Search:"
	_toolbar.add_child(search_label)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "search all fields…"
	_search_edit.custom_minimum_size.x = 150
	_search_edit.text_changed.connect(func(_t): _rebuild_tree())
	_toolbar.add_child(_search_edit)

	var clear_btn := Button.new()
	clear_btn.text = "✕"
	clear_btn.tooltip_text = "Clear search/filter"
	clear_btn.pressed.connect(_on_clear_filter)
	_toolbar.add_child(clear_btn)

	var col_nav_row := HBoxContainer.new()
	add_child(col_nav_row)

	var col_label := Label.new()
	col_label.text = "Go to column:"
	col_nav_row.add_child(col_label)

	_column_nav_opt = OptionButton.new()
	_column_nav_opt.custom_minimum_size.x = 180
	_column_nav_opt.item_selected.connect(_on_column_nav_selected)
	col_nav_row.add_child(_column_nav_opt)

	var col_reset_btn := Button.new()
	col_reset_btn.text = "⟲"
	col_reset_btn.tooltip_text = "Reset horizontal scroll"
	col_reset_btn.pressed.connect(func():
		_column_nav_opt.selected = -1
		var h_bar := _tree.find_child("HScrollBar", true, false) as HScrollBar
		if h_bar:
			h_bar.value = 0.0
	)
	col_nav_row.add_child(col_reset_btn)

	# ── Tree (таблица) ──────────────────────────────────────────────────────────
	_tree = Tree.new()
	_tree.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.allow_rmb_select = true
	_tree.column_titles_visible = true            # ИСПРАВЛЕНИЕ: показывать заголовки колонок
	_tree.set_column_titles_visible(true)         #      (явно, для старых версий 4.x)
	_tree.item_edited.connect(_on_item_edited)
	_tree.button_clicked.connect(_on_tree_button_clicked)
	_tree.column_title_clicked.connect(_on_column_title_clicked)
	add_child(_tree)

	# ── Строка состояния ────────────────────────────────────────────────────────
	_status_label = Label.new()
	_status_label.text = "No table loaded."
	add_child(_status_label)

	# ── Диалоги ─────────────────────────────────────────────────────────────────
	_array_dialog = ArrayEditorDialog.new()
	_array_dialog.hide()
	add_child(_array_dialog)

	_dict_dialog = DictionaryEditorDialog.new()
	_dict_dialog.hide()
	add_child(_dict_dialog)

	_color_picker_popup = PopupPanel.new()
	_color_picker = ColorPicker.new()
	_color_picker.color_changed.connect(_on_color_picked)
	_color_picker_popup.add_child(_color_picker)
	add_child(_color_picker_popup)

	_nested_editor = NestedObjectEditor.new()
	_nested_editor.hide()
	add_child(_nested_editor)

	_ref_picker = TableRefPickerDialog.new()
	_ref_picker.hide()
	add_child(_ref_picker)

# ──────────────────────────────────────────────────────────────────────────────

func _populate_column_nav() -> void:
	_column_nav_opt.clear()
	if _table == null or _table.schema == null:
		return
	_column_nav_opt.add_item("ID (col 0)")
	for i: int in range(_table.schema.fields.size()):
		var f: DBFieldDef = _table.schema.fields[i]
		_column_nav_opt.add_item("%s  (col %d)" % [f.field_name, i + 1])

func _on_column_nav_selected(idx: int) -> void:
	if _tree == null:
		return

	var target_col := idx  # 0 – ID, 1+ – поля схемы

	# Получаем любой существующий TreeItem (первый дочерний элемент корня)
	var root := _tree.get_root()
	if root == null:
		return

	var item := root.get_first_child()
	if item == null:
		return

	# Сохраняем текущий режим выбора
	var old_mode := _tree.select_mode

	# Временно переключаем на SELECT_SINGLE для работы горизонтального скролла
	_tree.select_mode = Tree.SELECT_SINGLE

	# Устанавливаем фокус на нужную ячейку
	_tree.set_selected(item, target_col)

	# Это заставит Tree прокрутиться, чтобы ячейка была видна
	_tree.ensure_cursor_is_visible()

	# Возвращаем исходный режим
	_tree.select_mode = old_mode

func load_table(table: DBTable, db: DBDatabase) -> void:
	_table    = table
	_database = db

	if _database:
		_database.resolve_enum_refs()

	if _table != null and _table.schema != null:
		for e: DBEntry in _table.entries:
			e.schema_name = _table.schema.schema_name
			_table.schema.normalize_data(e.data, _database)

	_sort_field = ""
	_sort_asc   = true
	_search_edit.text = ""
	_filter_val_edit.text = ""
	_rebuild_filter_options()
	_rebuild_tree()

func clear() -> void:
	_table    = null
	_database = null
	_tree.clear()
	_status_label.text = "No table loaded."
	_filter_field_opt.clear()

# ──────────────────────────────────────────────────────────────────────────────
# Построение таблицы
# ──────────────────────────────────────────────────────────────────────────────

func _rebuild_filter_options() -> void:
	_filter_field_opt.clear()
	_filter_field_opt.add_item("(all)")
	if _table == null or _table.schema == null: return
	for f: DBFieldDef in _table.schema.fields:
		_filter_field_opt.add_item(f.field_name)

func _get_visible_entries() -> Array[DBEntry]:
	if _table == null: return []

	var entries: Array[DBEntry]

	var search := _search_edit.text.strip_edges()
	if not search.is_empty():
		entries = _table.search(search)
	elif not _sort_field.is_empty():
		entries = _table.sorted_by(_sort_field, _sort_asc)
	else:
		entries = _table.entries.duplicate()

	# применяем фильтр по полю
	var fi := _filter_field_opt.selected - 1   # 0 = "(all)"
	var fv := _filter_val_edit.text.strip_edges()
	if fi >= 0 and fi < _table.schema.fields.size() and not fv.is_empty():
		var fname: String = _table.schema.fields[fi].field_name
		var filtered: Array[DBEntry] = []
		for e: DBEntry in entries:
			if str(e.get_value(fname)).to_lower().contains(fv.to_lower()):
				filtered.append(e)
		entries = filtered

	return entries

func _rebuild_tree() -> void:
	_tree.clear()
	if _table == null or _table.schema == null:
		_status_label.text = "No table / schema loaded."
		return

	var schema: DBSchema = _table.schema
	var fields: Array[DBFieldDef] = schema.fields
	var n_cols := fields.size() + 2  # col 0 = ID, last col = actions

	_tree.columns = n_cols
	_tree.column_titles_visible = true

	# Колонка 0 — ID
	var id_title := "ID"
	if _sort_field == "_id":
		id_title += " " + ("▲" if _sort_asc else "▼")
	_tree.set_column_title(0, id_title)
	_tree.set_column_title_alignment(0, HORIZONTAL_ALIGNMENT_LEFT)
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 120)

	for i: int in range(fields.size()):
		var f: DBFieldDef = fields[i]
		var title := f.field_name
		if not f.description.strip_edges().is_empty():
			title += " ⓘ"
		if _sort_field == f.field_name:
			title += " " + ("▲" if _sort_asc else "▼")
		_tree.set_column_title(i + 1, title)
		_tree.set_column_title_alignment(i + 1, HORIZONTAL_ALIGNMENT_LEFT)
		_tree.set_column_expand(i + 1, false)                 # отключаем растяжение
		_tree.set_column_custom_minimum_width(i + 1, 150)     # минимальная ширина в пикселях
		_tree.set_column_clip_content(i + 1, true)

	_populate_column_nav()

	var action_col := fields.size() + 1
	_tree.set_column_title(action_col, "⚙")
	_tree.set_column_title_alignment(action_col, HORIZONTAL_ALIGNMENT_CENTER)
	_tree.set_column_expand(action_col, false)
	_tree.set_column_custom_minimum_width(action_col, 52)

	_visible_entries = _get_visible_entries()
	var root := _tree.create_item()

	for entry: DBEntry in _visible_entries:
		var item := _tree.create_item(root)
		_populate_row(item, entry, fields, action_col)

	_status_label.text = "Table: %s   |   Rows: %d / %d   |   Schema: %s" % [
		_table.table_name,
		_visible_entries.size(),
		_table.entries.size(),
		schema.schema_name
	]

func _populate_row(item: TreeItem, entry: DBEntry,
				   fields: Array[DBFieldDef], action_col: int) -> void:
	item.set_metadata(0, entry.entry_id)

	# Колонка 0 – ID (только чтение)
	item.set_text(0, entry.entry_id)
	item.set_editable(0, false)
	item.set_selectable(0, true)

	for i: int in range(fields.size()):
		var col := i + 1
		var f: DBFieldDef = fields[i]

		if not f.description.strip_edges().is_empty():
			item.set_tooltip_text(col, f.description.strip_edges())

		var val: Variant = entry.get_value(f.field_name)
		if val == null:
			val = f.get_default()

		match f.field_type:
			DBFieldDef.FieldType.INT:
				item.set_cell_mode(col, TreeItem.CELL_MODE_RANGE)
				item.set_range_config(col, -9999999, 9999999, 1)
				item.set_range(col, int(val))
				item.set_editable(col, true)

			DBFieldDef.FieldType.FLOAT:
				item.set_cell_mode(col, TreeItem.CELL_MODE_RANGE)
				item.set_range_config(col, -9999999.0, 9999999.0, 0.001, false)
				item.set_range(col, float(val))
				item.set_editable(col, true)

			DBFieldDef.FieldType.STRING:
				item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
				item.set_text(col, str(val))
				item.set_editable(col, true)

			DBFieldDef.FieldType.BOOL:
				item.set_cell_mode(col, TreeItem.CELL_MODE_CHECK)
				item.set_text(col, "")
				item.set_checked(col, bool(val))
				item.set_editable(col, true)

			DBFieldDef.FieldType.ENUM:
				item.set_cell_mode(col, TreeItem.CELL_MODE_RANGE)
				item.set_editable(col, true)
				if f.enum_values.size() > 0:
					item.set_text(col, ",".join(Array(f.enum_values)))
					item.set_range_config(col, 0,
							maxf(0, f.enum_values.size() - 1), 1)
					item.set_range(col, float(int(val)))
				else:
					item.set_text(col, "")
					item.set_range(col, 0)

			DBFieldDef.FieldType.VECTOR2:
				item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
				var v2: Vector2 = val if val is Vector2 else Vector2.ZERO
				item.set_text(col, "(%.3f, %.3f)" % [v2.x, v2.y])
				item.set_editable(col, false)
				item.add_button(col,
					get_theme_icon("Edit", "EditorIcons"), BTN_VEC2,
					false, "Edit Vector2")

			DBFieldDef.FieldType.VECTOR3:
				item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
				var v3: Vector3 = val if val is Vector3 else Vector3.ZERO
				item.set_text(col, "(%.3f, %.3f, %.3f)" % [v3.x, v3.y, v3.z])
				item.set_editable(col, false)
				item.add_button(col,
					get_theme_icon("Edit", "EditorIcons"), BTN_VEC3,
					false, "Edit Vector3")

			DBFieldDef.FieldType.COLOR:
				# ИСПРАВЛЕНИЕ: кастомная ячейка с кнопкой для выбора цвета; текст должен читаться.
				item.set_cell_mode(col, TreeItem.CELL_MODE_CUSTOM)
				item.set_editable(col, false)
				var c: Color = val if val is Color else Color.WHITE
				item.set_custom_bg_color(col, c)
				item.set_custom_color(col,
					Color.BLACK if c.get_luminance() > 0.5 else Color.WHITE)
				item.set_text(col, c.to_html(false))
				item.add_button(col,
					get_theme_icon("Edit", "EditorIcons"), BTN_COLOR,
					false, "Pick color")

			DBFieldDef.FieldType.RESOURCE_REF:
				item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
				item.set_text(col, str(val))
				item.set_editable(col, true)
				var folder_icon := get_theme_icon("Folder", "EditorIcons")
				if folder_icon == null:
					folder_icon = get_theme_icon("File", "EditorIcons")  # запасной вариант
				item.add_button(col,
					folder_icon, BTN_RES,
					false, "Browse resource")

			DBFieldDef.FieldType.ARRAY:
				item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
				var arr: Array = val if val is Array else []
				item.set_text(col, "[Array: %d]" % arr.size())
				item.set_editable(col, false)
				item.add_button(col,
					get_theme_icon("EditInternal", "EditorIcons"), BTN_ARRAY,
					false, "Edit Array")

			DBFieldDef.FieldType.NESTED_OBJECT:
				item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
				var d: Dictionary = val if val is Dictionary else {}
				item.set_text(col, "{Object: %d fields}" % d.size())
				item.set_editable(col, false)
				item.add_button(col,
					get_theme_icon("EditInternal", "EditorIcons"), BTN_NESTED,
					false, "Edit Object")

			DBFieldDef.FieldType.DICTIONARY:
				item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
				var dd: Dictionary = val if val is Dictionary else {}
				item.set_text(col, "{Dict: %d}" % dd.size())
				item.set_editable(col, false)
				item.add_button(col,
					get_theme_icon("EditInternal", "EditorIcons"), BTN_DICT,
					false, "Edit Dictionary")

			DBFieldDef.FieldType.TABLE_REF:
				item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
				var rid := str(val)
				item.set_text(col, rid if not rid.is_empty() else "(не задано)")
				item.set_editable(col, false)
				# Подсветим битую ссылку красным.
				if not rid.is_empty() and _database:
					var rt := _database.get_table(f.ref_table_name)
					if rt == null or rt.get_entry(rid) == null:
						item.set_custom_color(col, Color(1.0, 0.45, 0.45))
						item.set_tooltip_text(col, "Битая ссылка: '%s' нет в '%s'" % [rid, f.ref_table_name])
				item.add_button(col,
					get_theme_icon("Instance", "EditorIcons"), BTN_TABLE_REF,
					false, "Выбрать строку из таблицы '%s'" % f.ref_table_name)

	# Кнопки действий в последней колонке
	item.add_button(action_col,
		get_theme_icon("Remove", "EditorIcons"), BTN_DELETE, false, "Delete row")

# ──────────────────────────────────────────────────────────────────────────────
# Обработчики сигналов
# ──────────────────────────────────────────────────────────────────────────────

func _on_item_edited() -> void:
	var item := _tree.get_edited()
	var col   := _tree.get_edited_column()
	if item == null or col == 0: return
	if _table == null or _table.schema == null: return

	var entry_id: String = item.get_metadata(0)
	var entry := _table.get_entry(entry_id)
	if entry == null: return

	var field_idx := col - 1
	if field_idx < 0 or field_idx >= _table.schema.fields.size(): return
	var f: DBFieldDef = _table.schema.fields[field_idx]

	match f.field_type:
		DBFieldDef.FieldType.INT:
			entry.set_value(f.field_name, int(item.get_range(col)))
		DBFieldDef.FieldType.FLOAT:
			entry.set_value(f.field_name, item.get_range(col))
		DBFieldDef.FieldType.STRING:
			entry.set_value(f.field_name, item.get_text(col))
		DBFieldDef.FieldType.BOOL:
			entry.set_value(f.field_name, item.is_checked(col))
		DBFieldDef.FieldType.ENUM:
			entry.set_value(f.field_name, int(item.get_range(col)))
		DBFieldDef.FieldType.RESOURCE_REF:
			entry.set_value(f.field_name, item.get_text(col))
		DBFieldDef.FieldType.COLOR:
			# обрабатывается через кнопку выбора цвета
			pass

	data_changed.emit()

func _on_tree_button_clicked(item: TreeItem, col: int,
							  id: int, _mouse_btn: int) -> void:
	if _table == null: return
	var entry_id: String = item.get_metadata(0)
	var entry := _table.get_entry(entry_id)
	if entry == null: return

	# Кнопка удаления строки
	if id == BTN_DELETE:
		_table.remove_entry(entry_id)
		data_changed.emit()
		_rebuild_tree()
		return

	var field_idx := col - 1
	if _table.schema == null: return
	if field_idx < 0 or field_idx >= _table.schema.fields.size(): return
	var f: DBFieldDef = _table.schema.fields[field_idx]

	match id:
		BTN_VEC2:   _open_vector2_dialog(entry, f)
		BTN_VEC3:   _open_vector3_dialog(entry, f)
		BTN_RES:    _open_resource_browser(entry, f)
		BTN_ARRAY:  _open_array_editor(entry, f)
		BTN_NESTED: _open_nested_editor(entry, f)
		BTN_COLOR:  _open_color_picker(entry, f, item, col)
		BTN_DICT:   _open_dictionary_editor(entry, f)
		BTN_TABLE_REF: _open_table_ref_picker(entry, f)

func _open_color_picker(entry: DBEntry, f: DBFieldDef,
						item: TreeItem, col: int) -> void:
	_editing_entry = entry
	_editing_field = f.field_name
	var raw: Variant = entry.get_value(f.field_name)
	_color_picker.color = raw if raw is Color else Color.WHITE
	# ИСПРАВЛЕНИЕ: позиционирование в экранных координатах (popup-окна работают в screen space).
	var rect := _tree.get_item_area_rect(item, col)
	var gpos := _tree.get_screen_position() + rect.position + Vector2(0, rect.size.y)
	_color_picker_popup.popup(Rect2i(Vector2i(gpos), Vector2i(300, 360)))

func _on_color_picked(color: Color) -> void:
	if _editing_entry == null: return
	_editing_entry.set_value(_editing_field, color)
	data_changed.emit()
	_rebuild_tree()

func _on_column_title_clicked(col: int, _mouse_btn: int) -> void:
	if _table == null or _table.schema == null: return
	# Разрешаем сортировку по любому столбцу, включая 0 (ID)
	if col < 0 or col > _table.schema.fields.size(): return

	var fname: String
	if col == 0:
		fname = "_id"
	else:
		if col - 1 >= _table.schema.fields.size(): return
		fname = _table.schema.fields[col - 1].field_name

	if _sort_field == fname:
		# Если уже сортировали по убыванию – сбрасываем сортировку
		if not _sort_asc:
			_sort_field = ""
			_sort_asc = true
		else:
			# Была по возрастанию → переключаем на убывание
			_sort_asc = false
	else:
		# Сортируем по новому столбцу (возрастание)
		_sort_field = fname
		_sort_asc = true
	_rebuild_tree()

func _on_add_row() -> void:
	if _table == null: return
	_table.add_entry(_database)
	data_changed.emit()
	_rebuild_tree()

func _on_delete_row() -> void:
	var sel := _tree.get_selected()
	if sel == null: return
	var entry_id: String = sel.get_metadata(0)
	_table.remove_entry(entry_id)
	data_changed.emit()
	_rebuild_tree()

func _on_duplicate_row() -> void:
	var sel := _tree.get_selected()
	if sel == null: return
	var entry_id: String = sel.get_metadata(0)
	_table.duplicate_entry(entry_id)
	data_changed.emit()
	_rebuild_tree()

func _on_clear_filter() -> void:
	_search_edit.text = ""
	_filter_val_edit.text = ""
	_filter_field_opt.selected = 0
	_sort_field = ""
	_rebuild_tree()

# ──────────────────────────────────────────────────────────────────────────────
# Редакторы сложных полей
# ──────────────────────────────────────────────────────────────────────────────

func _open_vector2_dialog(entry: DBEntry, f: DBFieldDef) -> void:
	var raw: Variant = entry.get_value(f.field_name)
	var val: Vector2 = raw if raw is Vector2 else Vector2.ZERO
	var dlg := AcceptDialog.new()
	dlg.title = "Edit %s (Vector2)" % f.field_name
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_child(_make_label("X"))
	var ex := SpinBox.new(); ex.step = 0.001; ex.allow_lesser = true; ex.allow_greater = true
	ex.value = val.x; grid.add_child(ex)
	grid.add_child(_make_label("Y"))
	var ey := SpinBox.new(); ey.step = 0.001; ey.allow_lesser = true; ey.allow_greater = true
	ey.value = val.y; grid.add_child(ey)
	dlg.add_child(grid)
	add_child(dlg)
	dlg.popup_centered(Vector2i(260, 120))
	await dlg.confirmed
	entry.set_value(f.field_name, Vector2(ex.value, ey.value))
	data_changed.emit()
	_rebuild_tree()
	dlg.queue_free()

func _open_vector3_dialog(entry: DBEntry, f: DBFieldDef) -> void:
	var raw: Variant = entry.get_value(f.field_name)
	var val: Vector3 = raw if raw is Vector3 else Vector3.ZERO
	var dlg := AcceptDialog.new()
	dlg.title = "Edit %s (Vector3)" % f.field_name
	var grid := GridContainer.new()
	grid.columns = 2
	var ex := SpinBox.new(); ex.step = 0.001; ex.allow_lesser = true; ex.allow_greater = true
	var ey := SpinBox.new(); ey.step = 0.001; ey.allow_lesser = true; ey.allow_greater = true
	var ez := SpinBox.new(); ez.step = 0.001; ez.allow_lesser = true; ez.allow_greater = true
	for pair in [["X", ex], ["Y", ey], ["Z", ez]]:
		grid.add_child(_make_label(pair[0]))
		grid.add_child(pair[1])
	ex.value = val.x; ey.value = val.y; ez.value = val.z
	dlg.add_child(grid)
	add_child(dlg)
	dlg.popup_centered(Vector2i(260, 150))
	await dlg.confirmed
	entry.set_value(f.field_name, Vector3(ex.value, ey.value, ez.value))
	data_changed.emit()
	_rebuild_tree()
	dlg.queue_free()

func _open_table_ref_picker(entry: DBEntry, f: DBFieldDef) -> void:
	if _database == null:
		return
	if f.ref_table_name.is_empty():
		push_warning("[GD Database] У поля '%s' не задана целевая таблица (Reference Table)." % f.field_name)
		return
	_ref_picker.open(_database, f.ref_table_name, str(entry.get_value(f.field_name)))
	var result = await _ref_picker.ref_confirmed
	entry.set_value(f.field_name, str(result))
	data_changed.emit()
	_rebuild_tree()

func _open_resource_browser(entry: DBEntry, f: DBFieldDef) -> void:
	var dlg := EditorFileDialog.new()
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE

	# Всегда добавляем фильтры: если задан type_hint — показываем только его,
	# иначе показываем все ресурсы.
	if not f.resource_type_hint.is_empty():
		dlg.add_filter("*.*", f.resource_type_hint)
	else:
		dlg.add_filter("*.*", "All Resources")
		dlg.add_filter("*.tres,*.res,*.tscn,*.gd", "Godot Resources")

	add_child(dlg)
	dlg.popup_centered(Vector2i(800, 550))

	dlg.file_selected.connect(func(path: String) -> void:
		entry.set_value(f.field_name, path)
		data_changed.emit()
		_rebuild_tree()
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void:
		dlg.queue_free()
	)

func _open_dictionary_editor(entry: DBEntry, f: DBFieldDef) -> void:
	var raw: Variant = entry.get_value(f.field_name)
	var d: Dictionary = raw if raw is Dictionary else {}
	_dict_dialog.open(d, f, _database)
	var result = await _dict_dialog.confirmed_dictionary
	if result == null: return
	entry.set_value(f.field_name, result)
	data_changed.emit()
	_rebuild_tree()

func _open_array_editor(entry: DBEntry, f: DBFieldDef) -> void:
	var raw: Variant = entry.get_value(f.field_name)
	var arr: Array = raw if raw is Array else []
	_array_dialog.open(arr, f, _database)
	var result = await _array_dialog.confirmed_array
	if result == null: return
	entry.set_value(f.field_name, result)
	data_changed.emit()
	_rebuild_tree()

var _nested_entry: DBEntry = null
var _nested_field: DBFieldDef = null

func _open_nested_editor(entry: DBEntry, f: DBFieldDef) -> void:
	var raw: Variant = entry.get_value(f.field_name)
	var d: Dictionary = raw if raw is Dictionary else {}

	var nested_schema: DBSchema = null
	if _database and not f.nested_schema_name.is_empty():
		var nt := _database.get_table(f.nested_schema_name)
		if nt:
			nested_schema = nt.schema

	# снять возможные хвосты от прошлого открытия (persistent-редактор)
	if _nested_editor.object_confirmed.is_connected(_on_nested_confirmed):
		_nested_editor.object_confirmed.disconnect(_on_nested_confirmed)
	if _nested_editor.close_requested.is_connected(_on_nested_closed):
		_nested_editor.close_requested.disconnect(_on_nested_closed)

	# запоминаем, куда писать результат
	_nested_entry = entry
	_nested_field = f

	_nested_editor.object_confirmed.connect(_on_nested_confirmed, CONNECT_ONE_SHOT)
	_nested_editor.close_requested.connect(_on_nested_closed, CONNECT_ONE_SHOT)

	_nested_editor.open(d, nested_schema, _database)

func _on_nested_confirmed(result: Variant) -> void:
	# подтвердили — снимаем парный коннект на закрытие
	if _nested_editor.close_requested.is_connected(_on_nested_closed):
		_nested_editor.close_requested.disconnect(_on_nested_closed)
	if result != null and _nested_entry:
		_nested_entry.set_value(_nested_field.field_name, result)
		data_changed.emit()
		_rebuild_tree()
	_nested_entry = null
	_nested_field = null


func _on_nested_closed() -> void:
	# закрыли/отменили — снимаем парный коннект на подтверждение
	if _nested_editor.object_confirmed.is_connected(_on_nested_confirmed):
		_nested_editor.object_confirmed.disconnect(_on_nested_confirmed)
	_nested_entry = null
	_nested_field = null

# ──────────────────────────────────────────────────────────────────────────────

func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l
