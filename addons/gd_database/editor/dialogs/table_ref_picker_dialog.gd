@tool
extends Window
class_name TableRefPickerDialog
## Выбор строки (entry_id) из указанной таблицы для полей типа TABLE_REF.

signal ref_confirmed(entry_id: String)

var _table: DBTable = null
var _current_id: String = ""
var _ui_built := false

var _search: LineEdit
var _list: ItemList
var _status: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if _ui_built: return
	_ui_built = true
	title = "Pick Row"
	min_size = Vector2i(460, 420)
	if not close_requested.is_connected(_on_cancel):
		close_requested.connect(_on_cancel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_search = LineEdit.new()
	_search.placeholder_text = "Поиск по ID и полям…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refresh_list())
	vbox.add_child(_search)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.y = 260
	_list.item_activated.connect(func(_i): _on_ok())   # двойной клик = выбрать
	vbox.add_child(_list)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(_status)

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	var clear_btn := Button.new(); clear_btn.text = "✕ Очистить ссылку"
	clear_btn.tooltip_text = "Убрать ссылку (пустой ID)"
	clear_btn.pressed.connect(func() -> void:
		hide()
		ref_confirmed.emit("")
	)
	btn_row.add_child(clear_btn)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(sp)
	var cancel_btn := Button.new(); cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)
	var ok_btn := Button.new(); ok_btn.text = "OK"
	ok_btn.pressed.connect(_on_ok)
	btn_row.add_child(ok_btn)

# ──────────────────────────────────────────────────────────────────────────────

func open(db: DBDatabase, table_name: String, current_id: String = "") -> void:
	_build_ui()
	_table = db.get_table(table_name) if db else null
	_current_id = current_id
	_search.text = ""
	if _table == null:
		title = "Pick Row — таблица '%s' не найдена" % table_name
	else:
		title = "Pick Row — %s" % table_name
	_refresh_list()
	popup_centered(Vector2i(480, 460))
	_search.grab_focus()

func _refresh_list() -> void:
	_list.clear()
	if _table == null:
		_status.text = "Таблица не найдена."
		return
	var q := _search.text.strip_edges().to_lower()
	var select_idx := -1
	for e: DBEntry in _table.entries:
		var label := _entry_label(e)
		if not q.is_empty() and not label.to_lower().contains(q):
			continue
		_list.add_item(label)
		var idx := _list.item_count - 1
		_list.set_item_metadata(idx, e.entry_id)
		if e.entry_id == _current_id:
			select_idx = idx
	if select_idx >= 0:
		_list.select(select_idx)
		_list.ensure_current_is_visible()
	_status.text = "Строк: %d" % _list.item_count

## ID + предпросмотр первых «простых» полей строки.
func _entry_label(e: DBEntry) -> String:
	var parts := PackedStringArray()
	if _table.schema:
		for f: DBFieldDef in _table.schema.fields:
			if parts.size() >= 3:
				break
			var v: Variant = e.get_value(f.field_name)
			if v == null:
				continue
			match f.field_type:
				DBFieldDef.FieldType.ARRAY, DBFieldDef.FieldType.DICTIONARY, \
				DBFieldDef.FieldType.NESTED_OBJECT:
					continue
				DBFieldDef.FieldType.ENUM:
					if v is int and v >= 0 and v < f.enum_values.size():
						parts.append(f.enum_values[v])
				_:
					parts.append(DBFieldDef.format_value_for_display(v))
	if parts.is_empty():
		return e.entry_id
	return "%s   —   %s" % [e.entry_id, ", ".join(parts)]

func _on_ok() -> void:
	var idxs := _list.get_selected_items()
	if idxs.is_empty():
		push_warning("[Table Ref] Сначала выбери строку.")
		return
	var id := str(_list.get_item_metadata(idxs[0]))
	hide()
	ref_confirmed.emit(id)

func _on_cancel() -> void:
	hide()
