@tool
extends BiomeGenerator
class_name SwampBiome

@export_group("Болото")
@export_range(0.0, 1.0) var water_threshold : float = 0.35
@export_range(0.0, 1.0) var mud_threshold : float = 0.55
@export var pool_count : int = 8
@export var pool_radius_range : Vector2i = Vector2i(3, 8)

func _init() -> void:
	allows_river = false
	tree_density_factor = 0.4

func randomize_params() -> void:
	water_threshold = randf_range(0.25, 0.45)
	mud_threshold = randf_range(water_threshold + 0.1, 0.7)
	pool_count = randi_range(4, 12)
	pool_radius_range = Vector2i(randi_range(2, 4), randi_range(5, 9))

func generate(builder) -> void:
	var T = WorldBuilder.TerrainType
	var size: Vector2i = builder.total_size
	builder.init_grid(1)
	builder.init_terrain_types(T.MUD)

	for y in range(size.y):
		for x in range(size.x):
			var n = (builder.noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			if n < water_threshold:
				builder.set_tile(x, y, 0, T.WATER)
			elif n < mud_threshold:
				builder.set_tile(x, y, 1, T.MUD)
			else:
				builder.set_tile(x, y, 1, T.GROUND)

	if size.x > 10 and size.y > 10:
		for i in range(pool_count):
			var cx := randi_range(5, size.x - 5)
			var cy := randi_range(5, size.y - 5)
			var radius := randi_range(pool_radius_range.x, pool_radius_range.y)
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var px := cx + dx
					var py := cy + dy
					if not builder.is_in_bounds(px, py):
						continue
					var dist_sq := dx * dx + dy * dy
					var radius_sq := radius * radius
					if dist_sq <= radius_sq * 0.5:
						builder.set_tile(px, py, 0, T.DEEP_WATER)
					elif dist_sq <= radius_sq:
						var edge_noise = (builder.noise.get_noise_2d(float(px) * 3.0, float(py) * 3.0) + 1.0) * 0.5
						if edge_noise < 0.6:
							builder.set_tile(px, py, 0, T.WATER)

	_finish(builder)
