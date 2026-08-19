@tool
extends Camera2D
class_name PlayerCamera

## Желаемый видимый размер мира (в пикселях мира).
@export var CameraSize: Vector2 = Vector2(640, 480):
	set(value):
		CameraSize = value.max(Vector2.ONE) # защита от нуля/отрицательных
		_update_zoom()
		queue_redraw()

## Правый нижний угол лимита. Левый верхний всегда (0, 0).
@export var CameraLimit: Vector2i = Vector2i(480, 480):
	set(value):
		CameraLimit = value.max(Vector2i.ONE)
		queue_redraw()

@export_group("Smoothing")
@export var SmoothingEnabled: bool = true
@export_range(1.0, 30.0) var SmoothingSpeed: float = 10.0

@export_group("Peek")
## Разрешить "подглядывание" камерой в сторону курсора.
@export var PeekEnabled: bool = true
## Имя action в Input Map. Если такого action нет — фолбэк на Ctrl.
@export var PeekAction: StringName = &"camera_peek"
## Максимальное смещение камеры от игрока (в пикселях мира).
@export var PeekMaxDistance: float = 160.0:
	set(value):
		PeekMaxDistance = maxf(value, 0.0)
## Скорость возврата/выезда камеры при peek (отдельно от SmoothingSpeed).
@export_range(1.0, 30.0) var PeekSpeed: float = 8.0

@export_group("Debug")
@export var DrawLimitsInEditor: bool = true:
	set(value):
		DrawLimitsInEditor = value
		queue_redraw()

var _peeking: bool = false
var _peek_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Встроенные механизмы отключаем — всё делаем сами.
	position_smoothing_enabled = false
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_update_zoom()

	if Engine.is_editor_hint():
		return

	# top_level: камера перестаёт наследовать трансформ родителя,
	# но мы всё ещё можем читать его позицию как цель.
	top_level = true
	global_position = _clamp_to_limits(_get_target_position())

	# Пересчёт зума при изменении размера окна (важно при stretch mode = disabled).
	get_viewport().size_changed.connect(_update_zoom)


func _notification(what: int) -> void:
	# Если окно теряет фокус с зажатой клавишей — не залипаем в peek-режиме.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_peeking = false


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not PeekEnabled:
		return

	if InputMap.has_action(PeekAction):
		if event.is_action_pressed(PeekAction):
			_peeking = true
			get_viewport().set_input_as_handled()
		elif event.is_action_released(PeekAction):
			_peeking = false
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).keycode == KEY_CTRL:
		# Фолбэк, если action не назначен в Input Map.
		_peeking = (event as InputEventKey).pressed


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_update_peek_offset(delta)

	var target := _clamp_to_limits(_get_target_position() + _peek_offset)

	if SmoothingEnabled:
		# exp-lerp: скорость сглаживания не зависит от FPS
		global_position = global_position.lerp(target, 1.0 - exp(-SmoothingSpeed * delta))
	else:
		global_position = target


func _update_peek_offset(delta: float) -> void:
	var desired := Vector2.ZERO

	if PeekEnabled and _peeking:
		desired = _get_desired_peek_offset()

	# Плавно тянем текущее смещение к желаемому (и туда, и обратно).
	_peek_offset = _peek_offset.lerp(desired, 1.0 - exp(-PeekSpeed * delta))


func _get_desired_peek_offset() -> Vector2:
	var vp_size := get_viewport_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return Vector2.ZERO

	# Смещение курсора от центра экрана -> в мировые координаты (через zoom).
	var mouse_from_center := get_viewport().get_mouse_position() - vp_size * 0.5
	var world_offset := mouse_from_center / zoom

	# Ограничение по максимальной дистанции.
	return world_offset.limit_length(PeekMaxDistance)


func _get_target_position() -> Vector2:
	var parent := get_parent()
	if parent is Node2D:
		return (parent as Node2D).global_position
	return global_position


func _update_zoom() -> void:
	var base := _get_base_viewport_size()
	if base.x <= 0.0 or base.y <= 0.0:
		return
	zoom = base / CameraSize


func _get_base_viewport_size() -> Vector2:
	if Engine.is_editor_hint():
		return Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height")
		)
	return get_viewport_rect().size


func _clamp_to_limits(target: Vector2) -> Vector2:
	var half := CameraSize * 0.5
	var result := target

	# Если уровень уже, чем окно камеры — просто центрируем по этой оси.
	if float(CameraLimit.x) <= CameraSize.x:
		result.x = CameraLimit.x * 0.5
	else:
		result.x = clampf(target.x, half.x, CameraLimit.x - half.x)

	if float(CameraLimit.y) <= CameraSize.y:
		result.y = CameraLimit.y * 0.5
	else:
		result.y = clampf(target.y, half.y, CameraLimit.y - half.y)

	return result


# Визуализация лимитов в редакторе (жёлтая рамка).
func _draw() -> void:
	if not Engine.is_editor_hint() or not DrawLimitsInEditor:
		return
	var tl := to_local(Vector2.ZERO)
	var br := to_local(Vector2(CameraLimit))
	draw_rect(Rect2(tl, br - tl), Color.YELLOW, false, 2.0)
