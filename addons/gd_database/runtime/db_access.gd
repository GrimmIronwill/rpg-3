extends Node
class_name DBAccess
## Runtime read-API для ресурсов DBDatabase, созданных редактором.
##
## Назначение: в игре быстро доставать целые строки выбранной таблицы
## с уже приведёнными к нужному типу значениями (int/float/bool/string,
## Vector2/Vector3, Color, enum→int, Array<T>, NESTED_OBJECT и т.д.).
##
## Использование как синглтона (рекомендуется):
##   Project Settings → Autoload → добавить этот файл под именем "DB".
##   Потом в любом месте:
##       DB.load_database("res://data/my_database.tres")
##       var hero := DB.get_row("Heroes", "heroes_0001")
##       for row in DB.get_rows("Items"): ...
##
## Или как обычный объект без autoload:
##       var db := DBAccess.open("res://data/my_database.tres")
##       var rows := db.get_rows("Items")

# Эмитится после успешной загрузки/перезагрузки базы.
signal database_loaded(database_name: String)

var _db: DBDatabase = null
var _source_path: String = ""

# ──────────────────────────────────────────────────────────────────────────────
# Загрузка / источник
# ──────────────────────────────────────────────────────────────────────────────

## Фабрика для использования без autoload. Возвращает готовый экземпляр
## (или экземпляр без загруженной базы, если путь неверный — проверяй is_loaded()).
static func open(source) -> DBAccess:
	var inst := DBAccess.new()
	inst.load_database(source)
	return inst

## Принимает либо путь (String) к .tres/.res, либо уже готовый DBDatabase.
## Возвращает true при успехе.
func load_database(source) -> bool:
	if source is DBDatabase:
		_db = source
		_source_path = _db.resource_path
		emit_signal("database_loaded", _db.database_name)
		return true

	if source is String:
		var path: String = source
		if path.is_empty():
			push_error("[DBAccess] Empty database path.")
			return false
		if not ResourceLoader.exists(path):
			push_error("[DBAccess] Resource not found: %s" % path)
			return false
		var res := ResourceLoader.load(path)
		if res is DBDatabase:
			_db = res
			_source_path = path
			emit_signal("database_loaded", _db.database_name)
			return true
		push_error("[DBAccess] Resource is not a DBDatabase: %s" % path)
		return false

	push_error("[DBAccess] load_database expects a path String or a DBDatabase, got: %s" % typeof(source))
	return false

## Перечитать базу с диска (если грузили из файла).
func reload() -> bool:
	if _source_path.is_empty():
		push_warning("[DBAccess] No source path to reload from.")
		return false
	# Принудительно мимо кэша, чтобы подхватить изменения на диске.
	var res := ResourceLoader.load(_source_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res is DBDatabase:
		_db = res
		emit_signal("database_loaded", _db.database_name)
		return true
	push_error("[DBAccess] Reload failed: %s" % _source_path)
	return false

func is_loaded() -> bool:
	return _db != null

## Прямой доступ к ресурсу, если вдруг нужен (может вернуть null).
func get_database() -> DBDatabase:
	return _db

func get_database_name() -> String:
	return _db.database_name if _db else ""

func get_version() -> String:
	return _db.version if _db else ""

func get_source_path() -> String:
	return _source_path

# ──────────────────────────────────────────────────────────────────────────────
# Интроспекция: таблицы / схемы / поля
# ──────────────────────────────────────────────────────────────────────────────

## Все имена таблиц.
func get_table_names() -> PackedStringArray:
	if _db == null:
		return PackedStringArray()
	return _db.get_table_names()

func has_table(table_name: String) -> bool:
	return _db != null and _db.has_table(table_name)

## Уникальные имена схем, реально используемых таблицами.
func get_schema_names() -> PackedStringArray:
	var out := PackedStringArray()
	if _db == null:
		return out
	for tname in _db.get_table_names():
		var t := _db.get_table(tname)
		if t and t.schema and not out.has(t.schema.schema_name):
			out.append(t.schema.schema_name)
	return out

## Карта "имя таблицы → имя схемы".
func get_table_schema_map() -> Dictionary:
	var out := {}
	if _db == null:
		return out
	for tname in _db.get_table_names():
		var t := _db.get_table(tname)
		out[tname] = t.schema.schema_name if (t and t.schema) else ""
	return out

func get_schema(table_name: String) -> DBSchema:
	var t := _get_table_checked(table_name)
	return t.schema if (t and t.schema) else null

## Имена полей таблицы (без служебного _id).
func get_field_names(table_name: String) -> PackedStringArray:
	var s := get_schema(table_name)
	return s.get_field_names() if s else PackedStringArray()

## true, если в таблице есть поле с таким именем.
func has_field(table_name: String, field_name: String) -> bool:
	var s := get_schema(table_name)
	return s != null and s.has_field(field_name)

## Карта "поле → текстовая метка типа" (удобно для отладки/инспекции).
func describe_table(table_name: String) -> Dictionary:
	var out := {}
	var s := get_schema(table_name)
	if s == null:
		return out
	for f: DBFieldDef in s.fields:
		out[f.field_name] = f.get_type_label()
	return out

# ──────────────────────────────────────────────────────────────────────────────
# Количество / id
# ──────────────────────────────────────────────────────────────────────────────

func get_row_count(table_name: String) -> int:
	var t := _get_table_checked(table_name)
	return t.entries.size() if t else 0

## Все entry_id таблицы (в порядке хранения).
func get_ids(table_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	var t := _get_table_checked(table_name)
	if t == null:
		return out
	for e: DBEntry in t.entries:
		out.append(e.entry_id)
	return out

func has_row(table_name: String, entry_id: String) -> bool:
	var t := _get_table_checked(table_name)
	return t != null and t.get_entry(entry_id) != null

# ──────────────────────────────────────────────────────────────────────────────
# Получение строк (с приведением типов)
# ──────────────────────────────────────────────────────────────────────────────

## Одна строка по entry_id. Возвращает Dictionary с приведёнными типами:
##   { "_id": ..., "_schema": ..., <field_name>: <coerced value>, ... }
## Если строки нет — пустой Dictionary.
func get_row(table_name: String, entry_id: String) -> Dictionary:
	var t := _get_table_checked(table_name)
	if t == null:
		return {}
	var e := t.get_entry(entry_id)
	if e == null:
		push_warning("[DBAccess] Row '%s' not found in table '%s'." % [entry_id, table_name])
		return {}
	return _coerce_row(t, e)

## Строка по индексу (0..count-1).
func get_row_at(table_name: String, index: int) -> Dictionary:
	var t := _get_table_checked(table_name)
	if t == null:
		return {}
	if index < 0 or index >= t.entries.size():
		push_warning("[DBAccess] Index %d out of range in '%s'." % [index, table_name])
		return {}
	return _coerce_row(t, t.entries[index])

## Все строки таблицы как Array[Dictionary] (типизированные значения).
func get_rows(table_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := _get_table_checked(table_name)
	if t == null:
		return out
	for e: DBEntry in t.entries:
		out.append(_coerce_row(t, e))
	return out

## Карта "entry_id → строка" — удобно для быстрых выборок по id.
func get_rows_by_id(table_name: String) -> Dictionary:
	var out := {}
	var t := _get_table_checked(table_name)
	if t == null:
		return out
	for e: DBEntry in t.entries:
		out[e.entry_id] = _coerce_row(t, e)
	return out

## Одно значение поля строки (с приведением типа). default — что вернуть, если нет.
func get_value(table_name: String, entry_id: String, field_name: String, default: Variant = null) -> Variant:
	var t := _get_table_checked(table_name)
	if t == null:
		return default
	var e := t.get_entry(entry_id)
	if e == null:
		return default
	if t.schema:
		var f := t.schema.get_field(field_name)
		if f:
			return _coerce_field(f, e.data.get(field_name, f.get_default()))
	# Нет схемы / поля — отдаём сырое значение.
	return e.data.get(field_name, default)

## Колонка целиком: значения одного поля по всем строкам.
func get_column(table_name: String, field_name: String) -> Array:
	var out: Array = []
	var t := _get_table_checked(table_name)
	if t == null or t.schema == null:
		return out
	var f := t.schema.get_field(field_name)
	if f == null:
		push_warning("[DBAccess] Field '%s' not in table '%s'." % [field_name, table_name])
		return out
	for e: DBEntry in t.entries:
		out.append(_coerce_field(f, e.data.get(field_name, f.get_default())))
	return out

# ──────────────────────────────────────────────────────────────────────────────
# Выборки / фильтры
# ──────────────────────────────────────────────────────────────────────────────

## Точное совпадение поля со значением (значение сравнивается уже приведённым).
func find_rows(table_name: String, field_name: String, value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := _get_table_checked(table_name)
	if t == null or t.schema == null:
		return out
	var f := t.schema.get_field(field_name)
	if f == null:
		push_warning("[DBAccess] Field '%s' not in table '%s'." % [field_name, table_name])
		return out
	var target: Variant = _coerce_field(f, value)
	for e: DBEntry in t.entries:
		var cur: Variant = _coerce_field(f, e.data.get(field_name, f.get_default()))
		if cur == target:
			out.append(_coerce_row(t, e))
	return out

## Первая подходящая строка или {} (удобно, когда поле — уникальный ключ).
func find_first(table_name: String, field_name: String, value: Variant) -> Dictionary:
	var rows := find_rows(table_name, field_name, value)
	return rows[0] if rows.size() > 0 else {}

## Произвольный предикат. Callable получает уже приведённую строку (Dictionary)
## и должен вернуть bool. Пример:
##   DB.where("Heroes", func(r): return r["hp"] > 100 and r["element"] == 0)
func where(table_name: String, predicate: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not predicate.is_valid():
		push_error("[DBAccess] where() got an invalid Callable.")
		return out
	var t := _get_table_checked(table_name)
	if t == null:
		return out
	for e: DBEntry in t.entries:
		var row := _coerce_row(t, e)
		if bool(predicate.call(row)):
			out.append(row)
	return out

## Текстовый поиск по всем полям (как в редакторе), результат — типизированные строки.
func search(table_name: String, query: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := _get_table_checked(table_name)
	if t == null:
		return out
	for e: DBEntry in t.search(query):
		out.append(_coerce_row(t, e))
	return out

## Отсортированные строки по полю. ascending=false — по убыванию.
## field_name == "_id" сортирует по entry_id.
func get_rows_sorted(table_name: String, field_name: String, ascending: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := _get_table_checked(table_name)
	if t == null:
		return out
	for e: DBEntry in t.sorted_by(field_name, ascending):
		out.append(_coerce_row(t, e))
	return out

## Резолвит TABLE_REF-поле: возвращает строку ЦЕЛЕВОЙ таблицы (или {}).
## Пример: var rnd := DB.get_ref_row("Items", "items_0003", "random_params")
func get_ref_row(table_name: String, entry_id: String, field_name: String) -> Dictionary:
	var s := get_schema(table_name)
	if s == null:
		return {}
	var f := s.get_field(field_name)
	if f == null or f.field_type != DBFieldDef.FieldType.TABLE_REF:
		push_warning("[DBAccess] '%s.%s' — не Table Ref поле." % [table_name, field_name])
		return {}
	var ref_id := str(get_value(table_name, entry_id, field_name, ""))
	if ref_id.is_empty():
		return {}
	return get_row(f.ref_table_name, ref_id)

# ──────────────────────────────────────────────────────────────────────────────
# Внутреннее: проверки и приведение типов
# ──────────────────────────────────────────────────────────────────────────────

func _get_table_checked(table_name: String) -> DBTable:
	if _db == null:
		push_error("[DBAccess] No database loaded. Call load_database() first.")
		return null
	var t := _db.get_table(table_name)
	if t == null:
		push_warning("[DBAccess] Table '%s' not found." % table_name)
	return t

## Превращает DBEntry в Dictionary с типизированными значениями.
func _coerce_row(t: DBTable, e: DBEntry) -> Dictionary:
	var out := {
		"_id": e.entry_id,
		"_schema": e.schema_name,
	}
	if t.schema == null:
		# Схемы нет — отдаём сырую копию данных.
		for k in e.data:
			out[k] = e.data[k]
		return out
	for f: DBFieldDef in t.schema.fields:
		var raw: Variant = e.data.get(f.field_name, f.get_default())
		out[f.field_name] = _coerce_field(f, raw)
	return out

## Приводит одно значение к типу поля. Корректно обрабатывает массивы
## (приводит каждый элемент) и восстанавливает Vector/Color из dict'ов,
## которые могли прийти после импорта из JSON.
func _coerce_field(f: DBFieldDef, raw: Variant) -> Variant:
	match f.field_type:
		DBFieldDef.FieldType.ARRAY:
			var src: Array = raw if raw is Array else []
			var elem := DBFieldDef.new()
			elem.field_type         = f.array_element_type
			elem.enum_values        = f.enum_values
			elem.resource_type_hint = f.resource_type_hint
			var arr: Array = []
			for v in src:
				arr.append(elem.coerce(v))
			return arr
		DBFieldDef.FieldType.NESTED_OBJECT:
			return raw.duplicate(true) if raw is Dictionary else {}
		DBFieldDef.FieldType.DICTIONARY:
			return raw.duplicate(true) if raw is Dictionary else {}
		_:
			return f.coerce(raw)

## Список строковых значений ENUM-поля.
func get_enum_values(table_name: String, field_name: String) -> PackedStringArray:
	var s := get_schema(table_name)
	if s == null:
		return PackedStringArray()
	var f := s.get_field(field_name)
	if f == null or f.field_type != DBFieldDef.FieldType.ENUM:
		return PackedStringArray()
	return f.enum_values

## Индекс (то, что лежит в БД) → строковая подпись.
func enum_label(table_name: String, field_name: String, index: int) -> String:
	var vals := get_enum_values(table_name, field_name)
	return vals[index] if index >= 0 and index < vals.size() else ""

## Строковая подпись → индекс (-1, если нет).
func enum_index(table_name: String, field_name: String, label: String) -> int:
	return get_enum_values(table_name, field_name).find(label)
