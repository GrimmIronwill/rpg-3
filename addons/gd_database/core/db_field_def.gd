@tool
class_name DBFieldDef
extends Resource

## Перечисляет все типы данных, которые может содержать колонка.
enum FieldType {
	INT,            ## 0
	FLOAT,          ## 1
	STRING,         ## 2
	BOOL,           ## 3
	ENUM,           ## 4
	VECTOR2,        ## 5
	VECTOR3,        ## 6
	COLOR,          ## 7
	RESOURCE_REF,   ## 8
	ARRAY,          ## 9
	NESTED_OBJECT,  ## 10
	DICTIONARY,     ## 11 – отображение ключ→значение (key=dict_key_type, value=dict_value_type)
	TABLE_REF       ## 12 – ссылка на строку другой таблицы (хранит entry_id)
}

# ── TABLE_REF ──────────────────────────────────────────────────────────────────
## Имя таблицы, на строки которой ссылается это поле.
@export var ref_table_name: String = ""


@export var field_name: String = "field"
@export var field_type: FieldType = FieldType.STRING
@export var default_value: Variant = null      # сериализуется как Variant
@export var required: bool = false
@export var description: String = ""

# ── ENUM ───────────────────────────────────────────────────────────────────────
@export var enum_values: PackedStringArray = PackedStringArray()
## Если не пусто и тип ENUM — значения берутся из другого поля.
## Формат ключа: "SchemaName/field_name". enum_values при этом кэшируется.
@export var enum_ref: String = ""

# ── ARRAY ──────────────────────────────────────────────────────────────────────
@export var array_element_type: FieldType = FieldType.STRING

# ── NESTED_OBJECT / RESOURCE_REF ───────────────────────────────────────────────
@export var nested_schema_name: String = ""   # схема для валидации вложенного объекта
@export var resource_type_hint: String = ""   # напр. "Texture2D"

# ── DICTIONARY ─────────────────────────────────────────────────────────────────
@export var dict_key_type: FieldType = FieldType.STRING
@export var dict_value_type: FieldType = FieldType.STRING
## enum-значения для КЛЮЧА, когда dict_key_type == ENUM.
## Значение-enum переиспользует общий enum_values / enum_ref.
@export var dict_key_enum_values: PackedStringArray = PackedStringArray()
## Ссылка на источник enum для КЛЮЧА словаря ("SchemaName/field_name").
## Аналог enum_ref, но для dict_key_type == ENUM.
@export var dict_key_enum_ref: String = ""

# ──────────────────────────────────────────────────────────────────────────────
func get_type_label() -> String:
	match field_type:
		FieldType.INT:           return "int"
		FieldType.FLOAT:         return "float"
		FieldType.STRING:        return "string"
		FieldType.BOOL:          return "bool"
		FieldType.ENUM:          return "enum[%s]" % ",".join(enum_values)
		FieldType.VECTOR2:       return "Vector2"
		FieldType.VECTOR3:       return "Vector3"
		FieldType.COLOR:         return "Color"
		FieldType.RESOURCE_REF:  return "Resource<%s>" % resource_type_hint
		FieldType.ARRAY:         return "Array<%s>" % _element_type_label()
		FieldType.NESTED_OBJECT: return "Object<%s>" % nested_schema_name
		FieldType.DICTIONARY:    return "Dict<%s, %s>" % [_key_type_label(), _value_type_label()]
		FieldType.TABLE_REF:     return "Ref<%s>" % ref_table_name
	return "?"

func _key_type_label() -> String:
	var tmp := DBFieldDef.new()
	tmp.field_type  = dict_key_type
	tmp.enum_values = dict_key_enum_values
	return tmp.get_type_label()

func _value_type_label() -> String:
	var tmp := DBFieldDef.new()
	tmp.field_type         = dict_value_type
	tmp.enum_values        = enum_values
	tmp.array_element_type = array_element_type
	tmp.nested_schema_name = nested_schema_name
	tmp.resource_type_hint = resource_type_hint
	return tmp.get_type_label()

func _element_type_label() -> String:
	var temp := DBFieldDef.new()
	temp.field_type = array_element_type
	return temp.get_type_label()

## Возвращает нулевое значение для данного типа поля.
func get_default() -> Variant:
	if default_value != null:
		return default_value
	match field_type:
		FieldType.INT:           return 0
		FieldType.FLOAT:         return 0.0
		FieldType.STRING:        return ""
		FieldType.BOOL:          return false
		FieldType.ENUM:          return 0
		FieldType.VECTOR2:       return Vector2.ZERO
		FieldType.VECTOR3:       return Vector3.ZERO
		FieldType.COLOR:         return Color.WHITE
		FieldType.RESOURCE_REF:  return ""
		FieldType.ARRAY:         return []
		FieldType.NESTED_OBJECT: return {}
		FieldType.DICTIONARY:    return {}
		FieldType.TABLE_REF:     return ""
	return null

## Приводит сырой Variant к правильному типу для этого поля.
func coerce(value: Variant) -> Variant:
	match field_type:
		FieldType.INT:           return int(value) if value != null else 0
		FieldType.FLOAT:         return float(value) if value != null else 0.0
		FieldType.STRING:        return str(value) if value != null else ""
		FieldType.BOOL:          return bool(value) if value != null else false
		FieldType.ENUM:
			if value is int: return clampi(value, 0, maxi(0, enum_values.size() - 1))
			if value is String and value in enum_values: return enum_values.find(value)
			return 0
		FieldType.VECTOR2:
			if value is Vector2:
				return value
			if value is Dictionary:
				return Vector2(
					float(value.get("x", 0)),
					float(value.get("y", 0))
				)
			if value is String:
				var clean = value.strip_edges().replace("(", "").replace(")", "")
				var parts = clean.split(",", false)
				if parts.size() >= 2:
					return Vector2(float(parts[0]), float(parts[1]))
			return Vector2.ZERO

		FieldType.VECTOR3:
			if value is Vector3:
				return value
			if value is Dictionary:
				return Vector3(
					float(value.get("x", 0)),
					float(value.get("y", 0)),
					float(value.get("z", 0))
				)
			if value is String:
				var clean = value.strip_edges().replace("(", "").replace(")", "")
				var parts = clean.split(",", false)
				if parts.size() >= 3:
					return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
			return Vector3.ZERO

		FieldType.COLOR:
			if value is Color:
				return value
			if value is Dictionary:
				return Color(
					float(value.get("r", 1)),
					float(value.get("g", 1)),
					float(value.get("b", 1)),
					float(value.get("a", 1))
				)
			return Color.WHITE

		FieldType.RESOURCE_REF:  return str(value) if value != null else ""
		FieldType.ARRAY:
			if value is Array: return value
			return []
		FieldType.NESTED_OBJECT:
			if value is Dictionary: return value
			return {}
		FieldType.DICTIONARY:
			if value is Dictionary: return value
			return {}
		FieldType.TABLE_REF:     return str(value) if value != null else ""

	return value

static func format_value_for_display(value: Variant) -> String:
	if value is Vector2:
		return "(%.3f, %.3f)" % [value.x, value.y]
	if value is Vector3:
		return "(%.3f, %.3f, %.3f)" % [value.x, value.y, value.z]
	return str(value)

## Чинит свойства, которые могли десериализоваться как null
## (старые .tres, сохранённые до появления dict_* / array_element_type).
func sanitize() -> void:
	if typeof(field_type) != TYPE_INT:           field_type = FieldType.STRING
	if typeof(array_element_type) != TYPE_INT:   array_element_type = FieldType.STRING
	if typeof(dict_key_type) != TYPE_INT:        dict_key_type = FieldType.STRING
	if typeof(dict_value_type) != TYPE_INT:      dict_value_type = FieldType.STRING
	if typeof(enum_values) != TYPE_PACKED_STRING_ARRAY:
		enum_values = PackedStringArray()
	if typeof(dict_key_enum_values) != TYPE_PACKED_STRING_ARRAY:
		dict_key_enum_values = PackedStringArray()
	if typeof(ref_table_name) != TYPE_STRING:
		ref_table_name = ""
