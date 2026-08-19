@tool
extends Window
class_name ImportExportDlg
## JSON-импорт/экспорт для всей базы или отдельных таблиц.

var _database: DBDatabase = null
var _text_edit: TextEdit
var _table_opt: OptionButton
var _format_opt: OptionButton
var _status_label: Label
var _resource_mode_opt: OptionButton
var _resource_ext_opt: OptionButton

func _ready() -> void:
	title = "Import / Export"
	min_size = Vector2i(640, 520)
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

	var opt_row := HBoxContainer.new()
	vbox.add_child(opt_row)

	opt_row.add_child(_lbl("Table:"))
	_table_opt = OptionButton.new()
	_table_opt.custom_minimum_size.x = 180
	opt_row.add_child(_table_opt)

	opt_row.add_child(_lbl("  Format:"))
	_format_opt = OptionButton.new()
	_format_opt.add_item("JSON (full)")
	_format_opt.add_item("CSV (current table)")
	_format_opt.add_item("Resource (.tres/.res, current table)")
	_format_opt.item_selected.connect(_on_format_changed)
	opt_row.add_child(_format_opt)

	opt_row.add_child(_lbl("  Resource mode:"))

	_resource_mode_opt = OptionButton.new()
	_resource_mode_opt.add_item("Array / one file")
	_resource_mode_opt.add_item("Files per entry")
	opt_row.add_child(_resource_mode_opt)

	_resource_ext_opt = OptionButton.new()
	_resource_ext_opt.add_item(".tres")
	_resource_ext_opt.add_item(".res")
	opt_row.add_child(_resource_ext_opt)

	_on_format_changed(_format_opt.selected)


	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	var export_btn := Button.new(); export_btn.text = "▶ Export to Text"
	export_btn.pressed.connect(_on_export)
	btn_row.add_child(export_btn)
	var copy_btn := Button.new(); copy_btn.text = "⎘ Copy to Clipboard"
	copy_btn.pressed.connect(func(): DisplayServer.clipboard_set(_text_edit.text))
	btn_row.add_child(copy_btn)
	var save_btn := Button.new(); save_btn.text = "💾 Save to File…"
	save_btn.pressed.connect(_on_save_file)
	btn_row.add_child(save_btn)
	var load_btn := Button.new(); load_btn.text = "📂 Load from File…"
	load_btn.pressed.connect(_on_load_file)
	btn_row.add_child(load_btn)
	var import_btn := Button.new(); import_btn.text = "◀ Import from Text"
	import_btn.pressed.connect(_on_import)
	btn_row.add_child(import_btn)

	_text_edit = TextEdit.new()
	_text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_edit.custom_minimum_size.y = 300
	vbox.add_child(_text_edit)

	_status_label = Label.new()
	_status_label.text = ""
	vbox.add_child(_status_label)

func _on_format_changed(idx: int) -> void:
	var is_resource := idx == 2
	if _resource_mode_opt:
		_resource_mode_opt.visible = is_resource
	if _resource_ext_opt:
		_resource_ext_opt.visible = is_resource

func open(db: DBDatabase) -> void:
	_database = db
	_table_opt.clear()
	_table_opt.add_item("(All tables)")
	for tname: String in db.get_table_names():
		_table_opt.add_item(tname)
	_text_edit.text = ""
	_status_label.text = ""
	popup_centered()

# ── Экспорт ───────────────────────────────────────────────────────────────────

func _on_export() -> void:
	if _database == null: return
	if _format_opt.selected == 2:
		_status_label.text = "Resource export uses 'Save to File…'."
		return
	var fmt: int = _format_opt.selected
	var sel: int = _table_opt.selected

	if fmt == 0:   # JSON full
		var d: Dictionary
		if sel == 0:
			d = _database.to_json_dict()
		else:
			var tname: String = _table_opt.get_item_text(sel)
			d = _export_table_json(tname)
		_text_edit.text = JSON.stringify(d, "  ")
	else:          # CSV current table
		if sel == 0:
			_status_label.text = "Select a specific table for CSV export."
			return
		var tname: String = _table_opt.get_item_text(sel)
		_text_edit.text = _export_table_csv(tname)

	_status_label.text = "Exported. Copy or save to file."

func _export_table_json(tname: String) -> Dictionary:
	var t := _database.get_table(tname)
	if t == null: return {}
	var rows: Array = []
	for e: DBEntry in t.entries:
		rows.append(e.to_plain_dict())
	return { "table": tname, "schema": t.schema.schema_name if t.schema else "", "entries": rows }

func _export_table_csv(tname: String) -> String:
	var t := _database.get_table(tname)
	if t == null or t.schema == null: return ""
	var lines: PackedStringArray = PackedStringArray()
	var headers := PackedStringArray(["_id"])
	for f: DBFieldDef in t.schema.fields:
		headers.append(f.field_name)
	lines.append(_csv_row(headers))
	for e: DBEntry in t.entries:
		var row := PackedStringArray([e.entry_id])
		for f: DBFieldDef in t.schema.fields:
			row.append(_csv_cell(e.get_value(f.field_name)))
		lines.append(_csv_row(row))
	return "\n".join(lines)

func _csv_row(cols: PackedStringArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for c in cols:
		if c.contains(",") or c.contains("\"") or c.contains("\n"):
			parts.append("\"" + c.replace("\"", "\"\"") + "\"")
		else:
			parts.append(c)
	return ",".join(parts)

func _csv_cell(v: Variant) -> String:
	if v == null: return ""
	if v is Color: return (v as Color).to_html(false)
	if v is Vector2: return "(%.4f,%.4f)" % [(v as Vector2).x, (v as Vector2).y]
	if v is Vector3: return "(%.4f,%.4f,%.4f)" % [(v as Vector3).x, (v as Vector3).y, (v as Vector3).z]
	if v is Array:   return "[%d items]" % (v as Array).size()
	return str(v)

# ── Импорт ────────────────────────────────────────────────────────────────────

func _on_import() -> void:
	if _database == null: return
	var raw := _text_edit.text.strip_edges()
	if raw.is_empty(): return

	var json := JSON.new()
	var err := json.parse(raw)
	if err != OK:
		_status_label.text = "JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return

	var data: Variant = json.get_data()
	if not (data is Dictionary):
		_status_label.text = "Expected a JSON object at root."
		return
	var d: Dictionary = data as Dictionary

	# Формат экспорта одной таблицы
	if d.has("entries") and d.has("table"):
		_import_table_json(d)
	# Экспорт всей базы
	elif d.has("tables"):
		for tname: String in d["tables"]:
			_import_table_json(d["tables"][tname], tname)
	else:
		_status_label.text = "Unrecognised JSON format."
		return
	_status_label.text = "Import complete."

func _import_table_json(td: Dictionary, override_name: String = "") -> void:
	var tname: String = override_name if not override_name.is_empty() else str(td.get("table", "imported"))
	var t := _database.get_table(tname)
	if t == null: return
	var entries: Array = td.get("entries", [])
	for row in entries:
		if not (row is Dictionary): continue
		var existing := t.get_entry(str(row.get("_id", "")))
		if existing:
			for key: String in row:
				if not key.begins_with("_"):
					existing.data[key] = row[key]
		else:
			var e := DBEntry.from_plain_dict(row)
			if e.entry_id.is_empty():
				e.entry_id = t._new_id()
			t.entries.append(e)
	t.emit_changed()

# ── Файловый ввод/вывод ───────────────────────────────────────────────────────

func _on_save_file() -> void:
	if _format_opt.selected == 2:
		_on_save_resource_file()
		return

	var dlg := EditorFileDialog.new()
	dlg.access   = EditorFileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dlg.add_filter("*.json", "JSON")
	dlg.add_filter("*.csv", "CSV")
	add_child(dlg)
	dlg.popup_centered(Vector2i(800, 550))
	dlg.file_selected.connect(func(path: String) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(_text_edit.text)
			f.close()
			_status_label.text = "Saved to %s" % path
		dlg.queue_free()
	)

func _on_save_resource_file() -> void:
	if _database == null:
		return

	var sel := _table_opt.selected
	if sel <= 0:
		_status_label.text = "Select a specific table for Resource export."
		return

	var tname := _table_opt.get_item_text(sel)
	var mode := _resource_mode_opt.selected

	if mode == 0:
		_open_save_table_resource_dialog(tname)
	else:
		_open_save_entries_resource_dialog(tname)


func _open_save_table_resource_dialog(tname: String) -> void:
	var dlg := EditorFileDialog.new()
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dlg.add_filter("*.tres", "Text Resource")
	dlg.add_filter("*.res", "Binary Resource")
	dlg.current_path = "res://%s.tres" % _safe_file_name(tname)

	add_child(dlg)
	dlg.popup_centered(Vector2i(800, 550))

	dlg.file_selected.connect(func(path: String) -> void:
		path = _ensure_resource_extension(path)

		var err := _export_table_as_resource(tname, path)
		if err == OK:
			_status_label.text = "Exported table '%s' to %s" % [tname, path]
		else:
			_status_label.text = "Resource export failed: %s" % error_string(err)

		dlg.queue_free()
	)

	dlg.canceled.connect(func() -> void:
		dlg.queue_free()
	)


func _open_save_entries_resource_dialog(tname: String) -> void:
	var dlg := EditorFileDialog.new()
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR

	add_child(dlg)
	dlg.popup_centered(Vector2i(800, 550))

	dlg.dir_selected.connect(func(dir_path: String) -> void:
		var ext := _resource_ext_opt.get_item_text(_resource_ext_opt.selected)
		var result := _export_entries_as_resources(tname, dir_path, ext)

		var count: int = result.get("count", 0)
		var errors: Array = result.get("errors", [])

		if errors.is_empty():
			_status_label.text = "Exported %d entries from '%s' to %s" % [count, tname, dir_path]
		else:
			_status_label.text = "Exported %d entries, errors: %d" % [count, errors.size()]
			for e in errors:
				push_warning(str(e))

		dlg.queue_free()
	)

	dlg.canceled.connect(func() -> void:
		dlg.queue_free()
	)


func _export_table_as_resource(tname: String, path: String) -> Error:
	var t := _database.get_table(tname)
	if t == null:
		return ERR_DOES_NOT_EXIST

	var export_res := DBTableExport.from_table(t)
	export_res.resource_path = path

	return ResourceSaver.save(export_res, path)


func _export_entries_as_resources(tname: String, dir_path: String, ext: String) -> Dictionary:
	var out := {
		"count": 0,
		"errors": [],
	}

	var t := _database.get_table(tname)
	if t == null:
		out["errors"].append("Table not found: %s" % tname)
		return out

	if not ext.begins_with("."):
		ext = "." + ext

	for e: DBEntry in t.entries:
		var safe_id := _safe_file_name(e.entry_id)
		var path := dir_path.path_join("%s%s" % [safe_id, ext])

		var export_res := DBEntryExport.from_entry(t, e)
		export_res.resource_path = path

		var err := ResourceSaver.save(export_res, path)
		if err == OK:
			out["count"] += 1
		else:
			out["errors"].append("%s → %s" % [path, error_string(err)])

	return out


func _ensure_resource_extension(path: String) -> String:
	var ext := path.get_extension().to_lower()
	if ext == "tres" or ext == "res":
		return path
	return path + ".tres"

func _safe_file_name(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		var ok := \
			(ch >= "A" and ch <= "Z") or \
			(ch >= "a" and ch <= "z") or \
			(ch >= "0" and ch <= "9") or \
			ch == "_" or ch == "-" or ch == "."

		out += ch if ok else "_"

	while out.contains("__"):
		out = out.replace("__", "_")

	out = out.strip_edges()

	if out.is_empty():
		out = "resource"

	return out

func _on_load_file() -> void:
	var dlg := EditorFileDialog.new()
	dlg.access    = EditorFileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dlg.add_filter("*.json", "JSON")
	dlg.add_filter("*.csv", "CSV")
	add_child(dlg)
	dlg.popup_centered(Vector2i(800, 550))
	dlg.file_selected.connect(func(path: String) -> void:
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			_text_edit.text = f.get_as_text()
			f.close()
		dlg.queue_free()
	)

func _lbl(t: String) -> Label:
	var l := Label.new(); l.text = t; return l
