@tool
extends BiomeGenerator
class_name DesertBiome

@export_group("Пустыня")
@export_range(0.0, 1.0) var rock_density : float = 0.05
@export_range(0.0, 1.0) var oasis_chance : float = 0.15
@export var dune_frequency : float = 0.03

func _init() -> void:
	allows_river = false
	tree_density_factor = 0.15

func randomize_params() -> void:
	rock_density = randf_range(0.02, 0.12)
	oasis_chance = randf_range(0.10, 0.30)
	dune_frequency = randf_range(0.02, 0.06)

func generate(builder) -> void:
	var T = WorldBuilder.TerrainType
	var size: Vector2i = builder.total_size
	builder.init_grid(1)
	builder.init_terrain_types(T.SAND)

	for y in range(size.y):
		for x in range(size.x):
			var n = (builder.noise.get_noise_2d(float(x) * dune_frequency * 10.0, float(y) * dune_frequency * 10.0) + 1.0) * 0.5
			if n > (1.0 - rock_density):
				builder.set_tile(x, y, 0, T.ROCK)

	var oasis_count := maxi(int(size.x * size.y * oasis_chance / 1000.0), 1)
	if size.x > 10 and size.y > 10:
		for i in range(oasis_count):
			var cx := randi_range(8, size.x - 8)
			var cy := randi_range(8, size.y - 8)
			var radius := randi_range(3, 6)
			for dy in range(-radius - 2, radius + 3):
				for dx in range(-radius - 2, radius + 3):
					var px := cx + dx
					var py := cy + dy
					if not builder.is_in_bounds(px, py):
						continue
					var dist_sq := dx * dx + dy * dy
					if dist_sq <= radius * radius:
						builder.set_tile(px, py, 0, T.WATER)
					elif dist_sq <= (radius + 2) * (radius + 2):
						builder.set_tile(px, py, 1, T.GROUND)

	_finish(builder)
