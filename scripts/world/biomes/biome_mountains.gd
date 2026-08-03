@tool
extends BiomeGenerator
class_name MountainsBiome

@export_group("Горы")
@export_range(0.0, 1.0) var rock_threshold : float = 0.6
@export_range(0.0, 1.0) var path_width : float = 0.15

func _init() -> void:
	allows_river = true
	tree_density_factor = 0.3

func randomize_params() -> void:
	rock_threshold = randf_range(0.5, 0.7)
	path_width = randf_range(0.10, 0.25)

func generate(builder) -> void:
	var T = WorldBuilder.TerrainType
	var size: Vector2i = builder.total_size
	builder.init_grid(1)
	builder.init_terrain_types(T.GROUND)

	for y in range(size.y):
		for x in range(size.x):
			var n = (builder.noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			if n > rock_threshold:
				builder.set_tile(x, y, 0, T.ROCK)

	_carve_paths(builder)
	_finish(builder)


func _carve_paths(builder) -> void:
	var T = WorldBuilder.TerrainType
	var size: Vector2i = builder.total_size
	var path_count := randi_range(2, 4)

	for i in range(path_count):
		var start := Vector2i(randi_range(0, size.x - 1), 0)
		var end := Vector2i(randi_range(0, size.x - 1), size.y - 1)
		var current := Vector2(start)
		var target := Vector2(end)
		var pw := int(path_width * 10.0) + 1

		while current.distance_to(target) > 2.0:
			var dir := current.direction_to(target).rotated(randf_range(-0.5, 0.5))
			current += dir * 1.5
			var cx := int(round(current.x))
			var cy := int(round(current.y))
			for dy in range(-pw, pw + 1):
				for dx in range(-pw, pw + 1):
					builder.set_tile(cx + dx, cy + dy, 1, T.PATH)
