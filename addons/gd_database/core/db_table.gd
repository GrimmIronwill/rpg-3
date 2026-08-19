@tool
class_name DBTable
extends Resource
@export var table_name: String = "Table"
@export var schema: DBSchema = null
@export var entries: Array[DBEntry] = []
var _id_counter: int = 0
# ──────────────────────────────────────────────────────────────────────────────
func add_entry(db = null) -> DBEntry:
	var e := DBEntry.new()
	e.entry_id    = _new_id()
	e.schema_name = schema.schema_name if schema else ""
	e.data        = schema.make_default_data(db) if schema else {}
	entries.append(e)
	emit_changed()
	return e

func duplicate_entry(entry_id: String) -> DBEntry:
	var src := get_entry(entry_id)
	if src == null: return null
	var e := DBEntry.new()
	e.entry_id    = _new_id()
	e.schema_name = src.schema_name
	e.data        = src.data.duplicate(true)
	entries.append(e)
	emit_changed()
	return e

func remove_entry(entry_id: String) -> bool:
	for i: int in range(entries.size()):
		if entries[i].entry_id == entry_id:
			entries.remove_at(i)
			emit_changed()
			return true
	return false

func get_entry(entry_id: String) -> DBEntry:
	for e: DBEntry in entries:
		if e.entry_id == entry_id:
			return e
	return null

func get_entry_index(entry_id: String) -> int:
	for i: int in range(entries.size()):
		if entries[i].entry_id == entry_id:
			return i
	return -1

## Перемещает строку вверх или вниз.
func move_entry(entry_id: String, delta: int) -> void:
	var i := get_entry_index(entry_id)
	if i < 0: return
	var j := clampi(i + delta, 0, entries.size() - 1)
	if i == j: return
	var e: DBEntry = entries[i]
	entries.remove_at(i)
	entries.insert(j, e)
	emit_changed()

## Возвращает записи, соответствующие простому текстовому запросу по всем полям, приводимым к строке.
func search(query: String) -> Array[DBEntry]:
	if query.strip_edges().is_empty():
		return entries.duplicate()
	var q := query.to_lower()
	var out: Array[DBEntry] = []
	for e: DBEntry in entries:
		for v: Variant in e.data.values():
			if str(v).to_lower().contains(q):
				out.append(e)
				break
	return out

## Возвращает записи, где поле == значение (точное совпадение).
func filter(field_name: String, value: Variant) -> Array[DBEntry]:
	var out: Array[DBEntry] = []
	for e: DBEntry in entries:
		if e.get_value(field_name) == value:
			out.append(e)
	return out

## Возвращает отсортированную копию массива записей.
func sorted_by(field_name: String, ascending: bool = true) -> Array[DBEntry]:
	var copy: Array[DBEntry] = entries.duplicate()
	if field_name == "_id":
		# Сортировка по ID (строковое поле entry_id)
		copy.sort_custom(func(a: DBEntry, b: DBEntry) -> bool:
			if ascending:
				return a.entry_id < b.entry_id
			else:
				return a.entry_id > b.entry_id
		)
	else:
		copy.sort_custom(func(a: DBEntry, b: DBEntry) -> bool:
			var va: Variant = a.get_value(field_name)
			var vb: Variant = b.get_value(field_name)
			var sa: String = str(va) if va != null else ""
			var sb: String = str(vb) if vb != null else ""
			return sa < sb if ascending else sa > sb
		)
	return copy

# ИСПРАВЛЕНИЕ: гарантирует уникальность, чтобы перезагрузка/импорт не вызывали конфликтов с существующими ID.
func _new_id() -> String:
	var prefix := table_name.to_lower().replace(" ", "_")
	_id_counter += 1
	var candidate := "%s_%04d" % [prefix, _id_counter]
	while get_entry(candidate) != null:
		_id_counter += 1
		candidate = "%s_%04d" % [prefix, _id_counter]
	return candidate
