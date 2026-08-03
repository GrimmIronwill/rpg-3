extends Node
class_name WorldBuilder

#region Параметры экспорта
@export_group("Генерация / Рандом")
@export var FullRandom : bool = false
@export var use_fixed_seed : bool = false
@export var world_seed : int = 0
@export var auto_generate_on_ready : bool = false

@export_group("Настройки мира")
@export var WorldSize : Vector2i = Vector2i(10, 10)
@export var ChunkSize : Vector2i = Vector2i(16, 16)
@export var TileSize : Vector2i = Vector2i(16, 16)
@export var StaticObjectsHolder : Node2D

@export_group("Биом")
## Активный биом (ресурс). Перетащи сюда .tres нужного биома.
@export var biome : BiomeGenerator
## Пул биомов для FullRandom — из него случайно выбирается один.
@export var biome_pool : Array[BiomeGenerator] = []

@export_group("Настройка рек")
@export_enum("None", "Left Top", "Top", "Right Top", "Left Middle", "Right Middle", "Left Bottom", "Bottom", "Right Bottom") var RiverStart : int = 0
@export_enum("None", "Left Top", "Top", "Right Top", "Left Middle", "Right Middle", "Left Bottom", "Bottom", "Right Bottom") var RiverEnd : int = 0

@export_group("Параметры реки")
@export var RiverWidth : int = 3
@export var RiverBlurWidth : int = 2
@export_range(0.0, 1.0) var RiverNoiseThreshold : float = 0.3
@export var WaypointCountMin : int = 2
@export var WaypointCountMax : int = 4

@export_group("Настройка деревьев")
@export var TreeScene : PackedScene
@export var MaxTreeCount: int = 20
@export var TreeBlockRadius: int = 2
@export var TreeBorderPadding: int = 2
@export var TreeTileSize: Vector2i = Vector2i(2, 2)
#endregion

#region Глобальные переменные
var grid: Array = []
var terrain_types: Array = []
var tree_map: Dictionary = {}
var total_size: Vector2i = Vector2i.ZERO
var noise: FastNoiseLite
var noise_secondary: FastNoiseLite
#endregion

## Типы тайлов — биомы ссылаются как WorldBuilder.TerrainType.WATER
enum TerrainType {
	GROUND = 0,
	WATER = 1,
	MUD = 2,
	SAND = 3,
	ROCK = 4,
	DUNGEON_FLOOR = 5,
	DUNGEON_WALL = 6,
	PATH = 7,
	DEEP_WATER = 8,
}


func _ready() -> void:
	noise = FastNoiseLite.new()
	noise.frequency = 0.1
	noise.fractal_octaves = 2

	noise_secondary = FastNoiseLite.new()
	noise_secondary.frequency = 0.05
	noise_secondary.fractal_octaves = 3

	if auto_generate_on_ready:
		generate_world()


func _setup_rng() -> void:
	if use_fixed_seed:
		seed(world_seed)
	else:
		randomize()
	noise.seed = randi()
	noise_secondary.seed = randi() + 42


## ════════════ ПУБЛИЧНАЯ ТОЧКА ВХОДА ════════════
func generate_world() -> void:
	_setup_rng()

	var active: BiomeGenerator = biome

	if FullRandom:
		_randomize_river()
		_randomize_trees()
		if not biome_pool.is_empty():
			active = biome_pool.pick_random()
		if active:
			active.randomize_params()

	if active == null:
		push_error("WorldBuilder: не назначен биом (biome / biome_pool пусты)!")
		return

	grid.clear()
	terrain_types.clear()
	tree_map.clear()

	if StaticObjectsHolder:
		for child in StaticObjectsHolder.get_children():
			child.queue_free()

	total_size = WorldSize * ChunkSize
	if total_size.x <= 0 or total_size.y <= 0:
		push_error("WorldSize или ChunkSize не могут быть <= 0!")
		return

	# Вся биомо-специфика — внутри ресурса. Билдер просто делегирует.
	active.generate(self)

	# ── Инициализация навигации ──
	if NavManager:
		NavManager.initialize_from_grid(grid, TileSize)
		NavManager.set_terrain(terrain_types)      # ← добавить (до деревьев!)
		NavManager.update_from_tree_map(tree_map)


	print("Генерация завершена. Биом: %s  Размер: %s" % [active.resource_name, str(total_size)])


## ════════════ РАНДОМ РЕК / ДЕРЕВЬЕВ (общее) ════════════

func _randomize_river() -> void:
	if randf() < 0.15:
		RiverStart = 0
		RiverEnd = 0
		return

	RiverStart = randi_range(1, 8)
	if randf() < 0.7:
		RiverEnd = _opposite_boundary(RiverStart)
	else:
		RiverEnd = randi_range(1, 8)
		while RiverEnd == RiverStart:
			RiverEnd = randi_range(1, 8)

	RiverWidth = randi_range(2, 5)
	RiverBlurWidth = randi_range(1, 4)
	RiverNoiseThreshold = randf_range(0.2, 0.6)
	WaypointCountMin = randi_range(2, 3)
	WaypointCountMax = WaypointCountMin + randi_range(1, 3)


func _randomize_trees() -> void:
	MaxTreeCount = randi_range(10, 40)
	TreeBlockRadius = randi_range(1, 3)
	TreeBorderPadding = randi_range(1, 3)


func _opposite_boundary(index: int) -> int:
	match index:
		1: return 8
		2: return 7
		3: return 6
		4: return 5
		5: return 4
		6: return 3
		7: return 2
		8: return 1
	return 0


## ════════════ ПРИМИТИВЫ СЕТКИ (зовут биомы) ════════════

func init_grid(fill_value: int = 1) -> void:
	grid.resize(total_size.y)
	for y in total_size.y:
		var row: Array = []
		row.resize(total_size.x)
		for x in total_size.x:
			row[x] = fill_value
		grid[y] = row


func init_terrain_types(default_type: int) -> void:
	terrain_types.resize(total_size.y)
	for y in range(total_size.y):
		var row: Array = []
		row.resize(total_size.x)
		for x in range(total_size.x):
			row[x] = default_type
		terrain_types[y] = row


func set_tile(x: int, y: int, walkable: int, terrain: int) -> void:
	if y < 0 or y >= grid.size() or x < 0 or x >= grid[y].size():
		return
	grid[y][x] = walkable
	terrain_types[y][x] = terrain


func is_in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and y < total_size.y and x < total_size.x


func has_river() -> bool:
	return RiverStart > 0 and RiverEnd > 0 and RiverStart != RiverEnd


func get_terrain_type(x: int, y: int) -> int:
	if terrain_types.is_empty():
		return TerrainType.GROUND
	if y < 0 or y >= terrain_types.size():
		return TerrainType.GROUND
	if x < 0 or x >= terrain_types[y].size():
		return TerrainType.GROUND
	return terrain_types[y][x]


## ════════════ РЕКА (общий примитив) ════════════

func _get_boundary_point(enum_index: int, size: Vector2i) -> Vector2i:
	var w: int = size.x - 1
	var h: int = size.y - 1
	match enum_index:
		1: return Vector2i(0, 0)
		2: return Vector2i(w / 2, 0)
		3: return Vector2i(w, 0)
		4: return Vector2i(0, h / 2)
		5: return Vector2i(w, h / 2)
		6: return Vector2i(0, h)
		7: return Vector2i(w / 2, h)
		8: return Vector2i(w, h)
	return Vector2i.ZERO


func _point_to_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _point_to_polyline_distance(p: Vector2, polyline: Array[Vector2]) -> float:
	var min_dist: float = INF
	for i in range(polyline.size() - 1):
		var d: float = _point_to_segment_distance(p, polyline[i], polyline[i + 1])
		if d < min_dist:
			min_dist = d
	return min_dist


func generate_river() -> void:
	var start_pos: Vector2i = _get_boundary_point(RiverStart, total_size)
	var end_pos: Vector2i = _get_boundary_point(RiverEnd, total_size)

	var control_points: Array[Vector2] = []
	control_points.append(Vector2(start_pos))

	var waypoint_count: int = randi_range(WaypointCountMin, WaypointCountMax)
	var river_dir: Vector2 = Vector2(end_pos - start_pos).normalized()
	var perp: Vector2 = Vector2(-river_dir.y, river_dir.x)
	var river_length: float = Vector2(end_pos - start_pos).length()
	var max_perp_offset: float = minf(river_length * 0.15, minf(total_size.x, total_size.y) * 0.15)

	var current_offset: float = 0.0
	for i in range(waypoint_count):
		var t: float = float(i + 1) / float(waypoint_count + 1)
		var base_point: Vector2 = Vector2(start_pos).lerp(Vector2(end_pos), t)
		var drift: float = randf_range(-max_perp_offset * 0.6, max_perp_offset * 0.6)
		current_offset = clampf(current_offset + drift, -max_perp_offset, max_perp_offset)
		var offset_point: Vector2 = base_point + perp * current_offset
		offset_point.x = clampf(offset_point.x, 0.0, float(total_size.x - 1))
		offset_point.y = clampf(offset_point.y, 0.0, float(total_size.y - 1))
		control_points.append(offset_point)

	control_points.append(Vector2(end_pos))

	var polyline: Array[Vector2] = _catmull_rom_chain(control_points, 20)
	var max_radius: float = float(RiverWidth + RiverBlurWidth)

	var bb_min := Vector2(INF, INF)
	var bb_max := Vector2(-INF, -INF)
	for p in polyline:
		bb_min.x = minf(bb_min.x, p.x); bb_min.y = minf(bb_min.y, p.y)
		bb_max.x = maxf(bb_max.x, p.x); bb_max.y = maxf(bb_max.y, p.y)

	var x_start: int = maxi(int(floor(bb_min.x - max_radius)), 0)
	var x_end: int = mini(int(ceil(bb_max.x + max_radius)), total_size.x - 1)
	var y_start: int = maxi(int(floor(bb_min.y - max_radius)), 0)
	var y_end: int = mini(int(ceil(bb_max.y + max_radius)), total_size.y - 1)

	for py in range(y_start, y_end + 1):
		for px in range(x_start, x_end + 1):
			var dist: float = _point_to_polyline_distance(Vector2(px, py), polyline)
			if dist <= float(RiverWidth):
				set_tile(px, py, 0, TerrainType.WATER)
			elif dist <= max_radius:
				var edge_factor: float = (dist - float(RiverWidth)) / float(RiverBlurWidth)
				var noise_val: float = (noise.get_noise_2d(float(px), float(py)) + 1.0) * 0.5
				var threshold: float = lerpf(0.8, RiverNoiseThreshold, edge_factor)
				if noise_val < threshold:
					set_tile(px, py, 0, TerrainType.WATER)


func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


func _catmull_rom_chain(points: Array[Vector2], segments_per_span: int = 20) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if points.size() < 2:
		for p in points:
			result.append(p)
		return result

	var extended: Array[Vector2] = []
	extended.append(points[0] + (points[0] - points[1]))
	for p in points:
		extended.append(p)
	extended.append(points[-1] + (points[-1] - points[-2]))

	for i in range(1, extended.size() - 2):
		for s in range(segments_per_span):
			var t: float = float(s) / float(segments_per_span)
			result.append(_catmull_rom(extended[i - 1], extended[i], extended[i + 1], extended[i + 2], t))

	result.append(points[-1])
	return result


## ════════════ ДЕРЕВЬЯ (общий примитив) ════════════

func generate_trees_scaled(factor: float) -> void:
	if factor <= 0.0:
		return
	var saved_max := MaxTreeCount
	MaxTreeCount = int(MaxTreeCount * factor)
	generate_trees()
	MaxTreeCount = saved_max


func generate_trees() -> void:
	if not TreeScene or not StaticObjectsHolder or MaxTreeCount <= 0:
		return

	var tw: int = TreeTileSize.x
	var th: int = TreeTileSize.y

	var candidates: Array[Vector2i] = []
	for y in range(total_size.y - th + 1):
		for x in range(total_size.x - tw + 1):
			var origin := Vector2i(x, y)
			if _is_tree_footprint_valid(origin, tw, th):
				candidates.append(origin)
	candidates.shuffle()

	var placed_count: int = 0
	for origin in candidates:
		if placed_count >= MaxTreeCount:
			break
		if _can_place_tree_multi(origin, tw, th, TreeBlockRadius):
			for ly in range(th):
				for lx in range(tw):
					tree_map[origin + Vector2i(lx, ly)] = origin
			var tree_instance = TreeScene.instantiate()
			StaticObjectsHolder.add_child(tree_instance)
			var pixel_origin := Vector2(origin * TileSize)
			var pixel_size := Vector2(TreeTileSize * TileSize)
			tree_instance.position = pixel_origin + pixel_size * 0.5
			placed_count += 1


func _is_tree_footprint_valid(origin: Vector2i, tw: int, th: int) -> bool:
	for ly in range(th):
		for lx in range(tw):
			var cell := origin + Vector2i(lx, ly)
			if not is_land(cell):
				return false
			if not _is_far_from_world_border(cell, TreeBorderPadding):
				return false
	return true


func _can_place_tree_multi(origin: Vector2i, tw: int, th: int, radius: int) -> bool:
	var check_min := origin - Vector2i(radius, radius)
	var check_max := origin + Vector2i(tw - 1 + radius, th - 1 + radius)
	for cy in range(check_min.y, check_max.y + 1):
		for cx in range(check_min.x, check_max.x + 1):
			var check_cell := Vector2i(cx, cy)
			if cx >= origin.x and cx < origin.x + tw and cy >= origin.y and cy < origin.y + th:
				continue
			if not tree_map.has(check_cell):
				continue
			if _min_dist_sq_to_footprint(check_cell, origin, tw, th) <= radius * radius:
				return false
	return true


func _min_dist_sq_to_footprint(point: Vector2i, origin: Vector2i, tw: int, th: int) -> int:
	var nearest_x: int = clampi(point.x, origin.x, origin.x + tw - 1)
	var nearest_y: int = clampi(point.y, origin.y, origin.y + th - 1)
	var dx: int = point.x - nearest_x
	var dy: int = point.y - nearest_y
	return dx * dx + dy * dy


func _is_far_from_world_border(cell: Vector2i, padding: int) -> bool:
	if not _is_inside_grid(cell):
		return false
	var width: int = grid[0].size()
	var height: int = grid.size()
	return (cell.x >= padding and cell.y >= padding
		and cell.x <= width - 1 - padding and cell.y <= height - 1 - padding)


func is_land(cell: Vector2i) -> bool:
	if not _is_inside_grid(cell):
		return false
	return grid[cell.y][cell.x] == 1


func _is_inside_grid(cell: Vector2i) -> bool:
	if grid.is_empty():
		return false
	return cell.x >= 0 and cell.y >= 0 and cell.y < grid.size() and cell.x < grid[0].size()


func is_cell_area_free(origin_cell: Vector2i, region_size: Vector2i) -> bool:
	if origin_cell.x < 0 or origin_cell.y < 0:
		return false
	if origin_cell.x + region_size.x > total_size.x or origin_cell.y + region_size.y > total_size.y:
		return false
	for y in range(region_size.y):
		for x in range(region_size.x):
			var cell := origin_cell + Vector2i(x, y)
			if not is_land(cell):
				return false
			if tree_map.has(cell):
				return false
	return true
