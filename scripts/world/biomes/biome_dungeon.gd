@tool
extends BiomeGenerator
class_name DungeonBiome

@export_group("Подземелье")
@export var room_count : int = 8
@export var room_size_min : Vector2i = Vector2i(4, 4)
@export var room_size_max : Vector2i = Vector2i(10, 8)
@export var corridor_width : int = 2

func _init() -> void:
	allows_river = false
	tree_density_factor = 0.0   # деревьев нет

func randomize_params() -> void:
	room_count = randi_range(5, 12)
	room_size_min = Vector2i(randi_range(3, 5), randi_range(3, 5))
	room_size_max = Vector2i(randi_range(8, 12), randi_range(7, 10))
	corridor_width = randi_range(1, 3)

func generate(builder) -> void:
	var T = WorldBuilder.TerrainType
	var size: Vector2i = builder.total_size

	builder.init_grid(0)                       # всё непроходимо...
	builder.init_terrain_types(T.DUNGEON_WALL) # ...и стены

	var rooms: Array[Rect2i] = []
	for i in range(room_count * 3):
		if rooms.size() >= room_count:
			break
		var max_rw: int = mini(room_size_max.x, size.x - 4)
		var max_rh: int = mini(room_size_max.y, size.y - 4)
		var min_rw: int = clampi(room_size_min.x, 1, max_rw)
		var min_rh: int = clampi(room_size_min.y, 1, max_rh)
		if max_rw < 1 or max_rh < 1:
			break
		var rw := randi_range(min_rw, max_rw)
		var rh := randi_range(min_rh, max_rh)
		if size.x - rw - 2 < 2 or size.y - rh - 2 < 2:
			continue
		var rx := randi_range(2, size.x - rw - 2)
		var ry := randi_range(2, size.y - rh - 2)
		var room := Rect2i(rx, ry, rw, rh)

		var overlaps := false
		for existing in rooms:
			if room.grow(2).intersects(existing):
				overlaps = true
				break
		if overlaps:
			continue
		rooms.append(room)

		for y in range(room.position.y, room.end.y):
			for x in range(room.position.x, room.end.x):
				builder.set_tile(x, y, 1, T.DUNGEON_FLOOR)

	for i in range(rooms.size() - 1):
		var ca := rooms[i].position + rooms[i].size / 2
		var cb := rooms[i + 1].position + rooms[i + 1].size / 2
		_carve_corridor(builder, ca, cb)

	# подземелье без реки и деревьев — _finish не вызываем


func _carve_corridor(builder, from: Vector2i, to: Vector2i) -> void:
	var T = WorldBuilder.TerrainType
	var current := from
	var half_w := corridor_width / 2

	while current.x != to.x:
		for dy in range(-half_w, half_w + 1):
			builder.set_tile(current.x, current.y + dy, 1, T.DUNGEON_FLOOR)
		current.x += signi(to.x - current.x)
	while current.y != to.y:
		for dx in range(-half_w, half_w + 1):
			builder.set_tile(current.x + dx, current.y, 1, T.DUNGEON_FLOOR)
		current.y += signi(to.y - current.y)
