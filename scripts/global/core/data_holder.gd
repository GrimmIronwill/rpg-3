extends Node

signal data_changed(key: String, new_value: Variant, old_value: Variant)
signal data_erased(key: String)
signal data_cleared()

const SAVE_PATH := "user://data_holder.save"

var _data: Dictionary = {}


func _ready() -> void:
	var err := load_from_disk()
	if err == ERR_FILE_NOT_FOUND:
		# First launch – create an empty save file so it exists from now on.
		print("DataHolder: no save found, creating new one at %s" % SAVE_PATH)
		save_to_disk()
	elif err != OK:
		push_warning("DataHolder: failed to load save (err %s). Starting fresh." % err)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save_to_disk()

func store_data(key: String, value: Variant) -> String:
	var old_value: Variant = _data.get(key)
	_data[key] = value
	data_changed.emit(key, value, old_value)
	return key

func erase_data(key: String) -> bool:
	if not _data.has(key):
		return false
	_data.erase(key)
	data_erased.emit(key)
	return true

func has_data(key: String) -> bool:
	return _data.has(key)

func get_data(key: String, default: Variant = null) -> Variant:
	return _data.get(key, default)

## Typed getters – safer than relying on Variant casts everywhere.
func get_int(key: String, default: int = 0) -> int:
	var v: Variant = _data.get(key, default)
	return int(v) if v != null else default

func get_float(key: String, default: float = 0.0) -> float:
	var v: Variant = _data.get(key, default)
	return float(v) if v != null else default

func get_string(key: String, default: String = "") -> String:
	var v: Variant = _data.get(key, default)
	return str(v) if v != null else default

func get_bool(key: String, default: bool = false) -> bool:
	var v: Variant = _data.get(key, default)
	return bool(v) if v != null else default

func clear() -> void:
	_data.clear()
	data_cleared.emit()

func keys() -> Array:
	return _data.keys()

## --- Persistence ---------------------------------------------------------

func save_to_disk(path: String = SAVE_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("DataHolder: cannot open %s (err %s)" % [path, FileAccess.get_open_error()])
		return FileAccess.get_open_error()
	file.store_var(_data)
	return OK

func load_from_disk(path: String = SAVE_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var loaded: Variant = file.get_var()
	if typeof(loaded) == TYPE_DICTIONARY:
		_data = loaded
		return OK
	return ERR_FILE_CORRUPT
