@tool
class_name DBEntry
extends Resource

@export var entry_id: String = ""
@export var schema_name: String = ""
## Все значения полей хранятся здесь; ключи = имена полей.
@export var data: Dictionary = {}

# ──────────────────────────────────────────────────────────────────────────────

func get_value(field_name: String) -> Variant:
	return data.get(field_name, null)

func set_value(field_name: String, value: Variant) -> void:
	data[field_name] = value
	emit_changed()

func has_value(field_name: String) -> bool:
	return data.has(field_name)

func to_plain_dict() -> Dictionary:
	## Возвращает глубокую копию, подходящую для экспорта в JSON.
	var out: Dictionary = { "_id": entry_id, "_schema": schema_name }
	for key in data:
		var v: Variant = data[key]
		if v is Vector2:        v = { "x": v.x, "y": v.y }
		elif v is Vector3:      v = { "x": v.x, "y": v.y, "z": v.z }
		elif v is Color:        v = v.to_html(true)
		elif v is Array:        v = v.duplicate(true)
		elif v is Dictionary:   v = v.duplicate(true)
		out[key] = v
	return out

static func from_plain_dict(d: Dictionary) -> DBEntry:
	var e := DBEntry.new()
	e.entry_id   = d.get("_id", "")
	e.schema_name = d.get("_schema", "")
	for key in d:
		if key.begins_with("_"): continue
		e.data[key] = d[key]
	return e
