@tool
extends Resource
class_name DatabaseItem

# Ключи, под которыми в данных из БД лежат словари с параметрами родительских классов.
# item_data       -> данные родителя Item (для ItemEquipment, ItemConsumable)
# equipment_data   -> данные родителя ItemEquipment (для ItemWeapon)
const PARENT_DATA_KEYS := ["item_data", "equipment_data"]
const KEYS_TO_IGNORE := ["_id", "_schema"]

func fill_from_dict(data: Dictionary) -> void:
	# name -> описание свойства (тип нужен для конвертации путей в ресурсы)
	var valid_props: Dictionary = {}
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE:
			valid_props[prop.name] = prop

	for key in data:
		if key in KEYS_TO_IGNORE:
			continue

		if key in PARENT_DATA_KEYS:
			var parent_data = data[key]
			if parent_data is Dictionary:
				fill_from_dict(parent_data)
			else:
				push_warning("Ключ '%s' ожидался как Dictionary, а пришло: %s"
					% [key, type_string(typeof(parent_data))])
			continue

		if key in valid_props:
			set(key, _convert_value(valid_props[key], data[key]))
		else:
			push_warning("Нет такой переменной: " + key)

## Строка-путь -> Resource, если свойство ожидает объект (Texture2D и т.п.)
func _convert_value(prop: Dictionary, value: Variant) -> Variant:
	# Строка-путь -> Resource, если свойство ожидает объект.
	if prop.type == TYPE_OBJECT and value is String:
		if value.is_empty():
			return null

		if ResourceLoader.exists(value):
			return ResourceLoader.load(value)

		push_warning(
			"Ресурс не найден: %s (поле %s)"
			% [value, prop.name]
		)
		return null

	# Обычный Array из БД -> типизированный Array свойства.
	if prop.type == TYPE_ARRAY and value is Array:
		var current: Variant = get(prop.name)

		if current is Array and current.is_typed():
			var typed_array: Array = current.duplicate(true)
			typed_array.clear()
			typed_array.assign(value)
			return typed_array

		return value.duplicate(true)

	# Обычный Dictionary из БД -> типизированный Dictionary свойства.
	if prop.type == TYPE_DICTIONARY and value is Dictionary:
		return _convert_dictionary_property(prop.name, value)

	return value

func _convert_dictionary_property(
	property_name: StringName,
	source: Dictionary
) -> Dictionary:
	var current: Variant = get(property_name)

	# Если свойство почему-либо не содержит Dictionary,
	# возвращаем хотя бы независимую копию исходных данных.
	if not (current is Dictionary):
		return source.duplicate(true)

	# duplicate() сохраняет информацию о типах Dictionary[K, V].
	var result: Dictionary = current.duplicate(true)
	result.clear()

	if result.is_typed():
		# assign() переносит данные в типизированный словарь и приводит
		# ключи/значения к его типам, например:
		# Dictionary[int, float],
		# Dictionary[int, Vector2].
		result.assign(source)
	else:
		result = source.duplicate(true)

	return result

func get_all_variables(debug : bool = true) -> Array[String]:
	var arr : Array[String]

	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE:
			arr.append(prop.name)
			if debug:
				prints(prop.name, " = ", get(prop.name))

	return arr

func get_all_variables_text(debug : bool = false) -> String:
	var str = ""
	var vars = get_all_variables(debug)

	for i in vars:
		str += i + "\n"

	return str

func print_all_variables() -> void:
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE:
			var value = get(prop.name)
			var type_name := type_string(typeof(value))
			prints(prop.name, "=", "(" + type_name + ")", value)
