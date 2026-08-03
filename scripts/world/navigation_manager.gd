class_name NavigationManager
extends Node

## ═══════════════════════════════════════════
##     МЕНЕДЖЕР НАВИГАЦИИ (ASTAR)
## ═══════════════════════════════════════════
##
## Добавить в Project → AutoLoad как "NavManager"
##
## Создаёт AStarGrid2D при генерации мира.
## Враги используют get_path() для обхода препятствий.

## ═══════════════════════════════════════════
##              НАСТРОЙКИ
## ═══════════════════════════════════════════

## Разрешить диагональное движение
@export var allow_diagonal : bool = true

## Вес диагонального движения (1.414 = реалистичный)
@export var diagonal_weight : float = 1.414

## Размер ячейки в пикселях (должен совпадать с TileSize)
@export var cell_size : Vector2i = Vector2i(32, 32)

## ═══════════════════════════════════════════
##              РАНТАЙМ
## ═══════════════════════════════════════════

var _astar : AStarGrid2D = null
var _grid_size : Vector2i = Vector2i.ZERO
var _initialized : bool = false
var _terrain : Array = []


## ═══════════════════════════════════════════
##            ИНИЦИАЛИЗАЦИЯ
## ═══════════════════════════════════════════

## Вызывается из WorldBuilder после генерации мира
func initialize_from_grid(grid: Array, tile_size: Vector2i) -> void:
	if grid.is_empty():
		push_error("NavigationManager: пустая сетка!")
		return

	cell_size = tile_size
	var height : int = grid.size()
	var width : int = grid[0].size()
	_grid_size = Vector2i(width, height)

	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, width, height)
	_astar.cell_size = Vector2(cell_size)
	_astar.offset = Vector2(cell_size) * 0.5

	if allow_diagonal:
		_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	else:
		_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER

	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN

	_astar.update()

	# Помечаем непроходимые ячейки
	for y in range(height):
		for x in range(width):
			var cell_value : int = grid[y][x]
			if cell_value == 0:
				_astar.set_point_solid(Vector2i(x, y), true)

	_initialized = true
	prints("NavigationManager: инициализирован. Размер:", _grid_size, "Ячейка:", cell_size)


## Обновить проходимость из tree_map (деревья)
func update_from_tree_map(tree_map: Dictionary) -> void:
	if not _initialized:
		return

	for cell in tree_map:
		if cell is Vector2i:
			if _is_valid_cell(cell):
				_astar.set_point_solid(cell, true)


## ═══════════════════════════════════════════
##         ПОИСК ПУТИ
## ═══════════════════════════════════════════

## Получить путь из мировых координат
func get_path_world(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	if not _initialized:
		return PackedVector2Array()

	var from_cell := world_to_cell(from_world)
	var to_cell := world_to_cell(to_world)

	# Клампим в пределы сетки
	from_cell = _clamp_cell(from_cell)
	to_cell = _clamp_cell(to_cell)

	# Если начальная или конечная точка непроходима — ищем ближайшую проходимую
	if _astar.is_point_solid(from_cell):
		from_cell = _find_nearest_walkable(from_cell)
	if _astar.is_point_solid(to_cell):
		to_cell = _find_nearest_walkable(to_cell)

	if from_cell == Vector2i(-1, -1) or to_cell == Vector2i(-1, -1):
		return PackedVector2Array()

	var path := _astar.get_point_path(from_cell, to_cell)
	return path


## Получить следующую точку пути (для простого следования)
func get_next_path_point(from_world: Vector2, to_world: Vector2) -> Vector2:
	var path := get_path_world(from_world, to_world)
	if path.size() < 2:
		return to_world
	return path[1]


## Проверить, проходима ли ячейка
func is_walkable_world(world_pos: Vector2) -> bool:
	if not _initialized:
		return true

	var cell := world_to_cell(world_pos)
	if not _is_valid_cell(cell):
		return false
	return not _astar.is_point_solid(cell)


## ═══════════════════════════════════════════
##     ДИНАМИЧЕСКОЕ ОБНОВЛЕНИЕ
## ═══════════════════════════════════════════

## Заблокировать ячейку (поставили объект)
func set_solid_world(world_pos: Vector2, solid: bool = true) -> void:
	if not _initialized:
		return
	var cell := world_to_cell(world_pos)
	if _is_valid_cell(cell):
		_astar.set_point_solid(cell, solid)


## Заблокировать прямоугольную область
func set_area_solid(origin_cell: Vector2i, size: Vector2i, solid: bool = true) -> void:
	if not _initialized:
		return
	for y in range(size.y):
		for x in range(size.x):
			var cell := origin_cell + Vector2i(x, y)
			if _is_valid_cell(cell):
				_astar.set_point_solid(cell, solid)


## Установить вес ячейки (для предпочтения определённых путей)
func set_weight_world(world_pos: Vector2, weight: float) -> void:
	if not _initialized:
		return
	var cell := world_to_cell(world_pos)
	if _is_valid_cell(cell):
		_astar.set_point_weight_scale(cell, weight)


## Вызывается из WorldBuilder. Вода становится проходимой, но "дорогой" для A*.
func set_terrain(terrain_types: Array) -> void:
	_terrain = terrain_types
	if not _initialized: return
	for y in range(mini(_terrain.size(), _grid_size.y)):
		for x in range(mini((_terrain[y] as Array).size(), _grid_size.x)):
			var cell := Vector2i(x, y)
			match _terrain[y][x]:
				WorldBuilder.TerrainType.WATER:
					_astar.set_point_solid(cell, false)
					_astar.set_point_weight_scale(cell, 2.5)
				WorldBuilder.TerrainType.DEEP_WATER:
					_astar.set_point_solid(cell, false)
					_astar.set_point_weight_scale(cell, 4.0)

func get_terrain_world(world_pos: Vector2) -> int:
	if _terrain.is_empty(): return WorldBuilder.TerrainType.GROUND
	var cell := world_to_cell(world_pos)
	if cell.y < 0 or cell.y >= _terrain.size(): return WorldBuilder.TerrainType.GROUND
	if cell.x < 0 or cell.x >= (_terrain[cell.y] as Array).size(): return WorldBuilder.TerrainType.GROUND
	return _terrain[cell.y][cell.x]

## ═══════════════════════════════════════════
##              УТИЛИТЫ
## ═══════════════════════════════════════════

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / float(cell_size.x))),
		int(floor(world_pos.y / float(cell_size.y)))
	)


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		float(cell.x) * float(cell_size.x) + float(cell_size.x) * 0.5,
		float(cell.y) * float(cell_size.y) + float(cell_size.y) * 0.5
	)


func _is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _grid_size.x and cell.y < _grid_size.y


func _clamp_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(cell.x, 0, _grid_size.x - 1),
		clampi(cell.y, 0, _grid_size.y - 1)
	)


func _find_nearest_walkable(cell: Vector2i) -> Vector2i:
	# Спиральный поиск
	for radius in range(1, 20):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate := cell + Vector2i(dx, dy)
				if _is_valid_cell(candidate) and not _astar.is_point_solid(candidate):
					return candidate
	return Vector2i(-1, -1)


func is_initialized() -> bool:
	return _initialized


func get_grid_size() -> Vector2i:
	return _grid_size
