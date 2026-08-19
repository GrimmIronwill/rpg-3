@tool
class_name DBSchema
extends Resource

@export var schema_name: String = "Schema"
@export var description: String = ""
@export var fields: Array[DBFieldDef] = []

# ──────────────────────────────────────────────────────────────────────────────

func get_field(name: String) -> DBFieldDef:
	for f: DBFieldDef in fields:
		if f.field_name == name:
			return f
	return null

func has_field(name: String) -> bool:
	return get_field(name) != null

func add_field(field: DBFieldDef) -> bool:
	if has_field(field.field_name):
		return false
	fields.append(field)
	emit_changed()
	return true

func remove_field(name: String) -> bool:
	for i: int in range(fields.size()):
		if fields[i].field_name == name:
			fields.remove_at(i)
			emit_changed()
			return true
	return false

func move_field(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or from_idx >= fields.size(): return
	if to_idx < 0 or to_idx >= fields.size(): return
	var f: DBFieldDef = fields[from_idx]
	fields.remove_at(from_idx)
	fields.insert(to_idx, f)
	emit_changed()

func get_field_names() -> PackedStringArray:
	var out := PackedStringArray()
	for f: DBFieldDef in fields:
		out.append(f.field_name)
	return out

## Создаёт свежий Dictionary данных со всеми значениями по умолчанию.
## Если передан db, поля NESTED_OBJECT с nested_schema_name разворачиваются
## с использованием дефолтов указанной схемы.
func make_default_data(db = null, _depth: int = 8) -> Dictionary:
	var d: Dictionary = {}
	for f: DBFieldDef in fields:
		d[f.field_name] = _make_field_default(f, db, _depth)
	return d


## Дополняет существующий dict ключами схемы; добавляет недостающие, сохраняет лишние.
func normalize_data(data: Dictionary, db = null, _depth: int = 8) -> Dictionary:
	for f: DBFieldDef in fields:
		if not data.has(f.field_name):
			data[f.field_name] = _make_field_default(f, db, _depth)
	return data


func _make_field_default(f: DBFieldDef, db = null, _depth: int = 8) -> Variant:
	if f == null:
		return null

	f.sanitize()

	# Если пользователь явно задал default_value — используем его.
	if f.default_value != null:
		var explicit: Variant = f.coerce(f.default_value)

		# Если это вложенный объект и default_value — Dictionary,
		# можно дополнить отсутствующие поля дефолтами вложенной схемы.
		if f.field_type == DBFieldDef.FieldType.NESTED_OBJECT \
				and explicit is Dictionary \
				and db != null \
				and _depth > 0 \
				and not f.nested_schema_name.is_empty():

			var nested_schema: DBSchema = db.get_schema_by_name_or_table(f.nested_schema_name)
			if nested_schema != null:
				var nested_data: Dictionary = explicit.duplicate(true)
				return nested_schema.normalize_data(nested_data, db, _depth - 1)

		return _dup_default(explicit)

	# Главное исправление: дефолт для NESTED_OBJECT берём из связанной схемы.
	if f.field_type == DBFieldDef.FieldType.NESTED_OBJECT \
			and db != null \
			and _depth > 0 \
			and not f.nested_schema_name.is_empty():

		var nested_schema: DBSchema = db.get_schema_by_name_or_table(f.nested_schema_name)
		if nested_schema != null:
			return nested_schema.make_default_data(db, _depth - 1)

	return _dup_default(f.get_default())


func _dup_default(v: Variant) -> Variant:
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	return v
