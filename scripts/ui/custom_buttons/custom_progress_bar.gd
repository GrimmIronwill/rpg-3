@tool
extends ProgressBar
class_name CustomProgressBar

## Формат текста. Доступные плейсхолдеры:
## {0} — value, {1} — min_value, {2} — max_value, {3} — процент (0..100)
@export var text_format: String = "{0} / {2}":
	set(v):
		text_format = v
		_refresh()

## Дополнительный минимальный размер (складывается по max с размером лейбла)
@export var extra_min_size: Vector2 = Vector2.ZERO:
	set(v):
		extra_min_size = v
		_update_min_size()

var label: Label


func _init() -> void:
	show_percentage = false


func _ready() -> void:
	_create_label()

	# Реакция на изменение value
	if not value_changed.is_connected(_on_value_changed):
		value_changed.connect(_on_value_changed)
	# Reaction на изменение min_value / max_value / step / page (сигнал Range.changed)
	if not changed.is_connected(_refresh):
		changed.connect(_refresh)

	_refresh()


func _create_label() -> void:
	if is_instance_valid(label):
		return

	label = Label.new()
	label.name = "TextLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = false

	# INTERNAL_MODE_FRONT: узел не попадёт в дерево сцены и не будет сохранён в .tscn
	add_child(label, false, Node.INTERNAL_MODE_FRONT)

	# Растянуть на весь прямоугольник: якоря (0,0,1,1) + нулевые отступы
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if not label.minimum_size_changed.is_connected(_update_min_size):
		label.minimum_size_changed.connect(_update_min_size)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_update_min_size()


func _on_value_changed(_v: float) -> void:
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(label):
		return
	label.text = _make_text()
	_update_min_size()


## Переопредели при необходимости
func _make_text() -> String:
	var percent: float = 0.0
	if not is_equal_approx(max_value, min_value):
		percent = (value - min_value) / (max_value - min_value) * 100.0
	return text_format.format([
	value,
	min_value,
	max_value,
	snappedf(percent, 0.1),
	])


func _update_min_size() -> void:
	if not is_instance_valid(label):
		return
	# ВАЖНО: у ProgressBar get_minimum_size() реализован в C++ и НЕ вызывает
	# скриптовый _get_minimum_size(), поэтому минимальный размер задаём
	# через custom_minimum_size. Итоговый минимум = max(custom, собственный минимум бара).
	var ms: Vector2 = label.get_combined_minimum_size()
	custom_minimum_size = Vector2(
		maxf(ms.x, extra_min_size.x),
		maxf(ms.y, extra_min_size.y)
	)
