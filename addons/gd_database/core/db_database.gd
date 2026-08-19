@tool
class_name DBDatabase
extends Resource

@export var database_name: String = "MyDatabase"
@export var version: String = "1.0.0"
## имя_таблицы (String) → DBTable
@export var tables: Dictionary = {}

# ──────────────────────────────────────────────────────────────────────────────

func create_table(table_name: String, schema: DBSchema) -> DBTable:
	if tables.has(table_name):
		push_warning("[GD Database] Table '%s' already exists." % table_name)
		return tables[table_name]
	var t := DBTable.new()
	t.table_name = table_name
	t.schema     = schema
	tables[table_name] = t
	emit_changed()
	return t

func remove_table(table_name: String) -> void:
	if tables.erase(table_name):
		emit_changed()

func get_table(table_name: String) -> DBTable:
	return tables.get(table_name, null) as DBTable

func has_table(name: String) -> bool:
	return tables.has(name)

func rename_table(old_name: String, new_name: String) -> bool:
	if not tables.has(old_name) or tables.has(new_name):
		return false
	var t: DBTable = tables[old_name]
	t.table_name = new_name
	tables[new_name] = t
	tables.erase(old_name)
	# ИСПРАВЛЕНИЕ: обновляем TABLE_REF-поля во всех схемах.
	for tname: String in tables:
		var tbl: DBTable = tables[tname]
		if tbl == null or tbl.schema == null:
			continue
		for f: DBFieldDef in tbl.schema.fields:
			if f.ref_table_name == old_name:
				f.ref_table_name = new_name
	emit_changed()
	return true

func get_table_names() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in tables:
		out.append(k)
	return out

## Экспортирует всю базу во вложенный Dictionary для JSON-сериализации.
func to_json_dict() -> Dictionary:
	var out: Dictionary = {
		"database_name": database_name,
		"version": version,
		"tables": {}
	}
	for tname: String in tables:
		var t: DBTable = tables[tname]
		var rows: Array = []
		for e: DBEntry in t.entries:
			rows.append(e.to_plain_dict())
		out["tables"][tname] = {
			"schema": t.schema.schema_name if t.schema else "",
			"entries": rows
		}
	return out

## Все ENUM-поля, пригодные как переиспользуемый источник.
## Возвращает { "SchemaName/field_name": PackedStringArray }.
func collect_enum_sources() -> Dictionary:
	var out: Dictionary = {}
	for tname: String in tables:
		var t: DBTable = tables[tname]
		if t == null or t.schema == null:
			continue
		for f: DBFieldDef in t.schema.fields:
			# Источник — только «самостоятельный» enum (не ссылка) с непустыми значениями.
			if f.field_type == DBFieldDef.FieldType.ENUM and f.enum_ref.is_empty() and f.enum_values.size() > 0:
				out["%s/%s" % [t.schema.schema_name, f.field_name]] = f.enum_values
	return out

func get_enum_values_for_ref(ref: String) -> PackedStringArray:
	return collect_enum_sources().get(ref, PackedStringArray())

## Подтягивает enum_values во все ссылающиеся ENUM-поля из их источников.
## Зови после загрузки, перед сохранением и перед показом таблицы.
func resolve_enum_refs() -> void:
	var sources := collect_enum_sources()
	for tname: String in tables:
		var t: DBTable = tables[tname]
		if t == null or t.schema == null:
			continue
		for f: DBFieldDef in t.schema.fields:
			f.sanitize()
			var is_enum := f.field_type == DBFieldDef.FieldType.ENUM
			var is_enum_array := f.field_type == DBFieldDef.FieldType.ARRAY \
				and f.array_element_type == DBFieldDef.FieldType.ENUM
			var is_enum_dict_value := f.field_type == DBFieldDef.FieldType.DICTIONARY \
				and f.dict_value_type == DBFieldDef.FieldType.ENUM
			if (is_enum or is_enum_array or is_enum_dict_value) and not f.enum_ref.is_empty():
				if sources.has(f.enum_ref):
					f.enum_values = sources[f.enum_ref]
				else:
					push_warning("[GD Database] enum_ref '%s' не найден (поле %s)." % [f.enum_ref, f.field_name])

			# ИСПРАВЛЕНИЕ: enum-КЛЮЧ словаря по ссылке (Dictionary или Array<Dictionary>).
			var dict_like := f.field_type == DBFieldDef.FieldType.DICTIONARY \
				or (f.field_type == DBFieldDef.FieldType.ARRAY \
					and f.array_element_type == DBFieldDef.FieldType.DICTIONARY)
			if dict_like and f.dict_key_type == DBFieldDef.FieldType.ENUM \
					and not f.dict_key_enum_ref.is_empty():
				if sources.has(f.dict_key_enum_ref):
					f.dict_key_enum_values = sources[f.dict_key_enum_ref]
				else:
					push_warning("[GD Database] dict_key_enum_ref '%s' не найден (поле %s)." % [f.dict_key_enum_ref, f.field_name])

func get_schema_by_name_or_table(name: String) -> DBSchema:
	if name.is_empty():
		return null

	# Сначала пробуем как имя таблицы.
	var t := get_table(name)
	if t != null and t.schema != null:
		return t.schema

	# Потом пробуем как schema_name.
	for tname: String in tables:
		var table: DBTable = tables[tname]
		if table != null and table.schema != null and table.schema.schema_name == name:
			return table.schema

	return null
