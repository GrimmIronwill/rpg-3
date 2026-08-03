@tool
extends BiomeGenerator
class_name ForestBiome

func generate(builder) -> void:
	builder.init_grid(1)
	builder.init_terrain_types(WorldBuilder.TerrainType.GROUND)
	_finish(builder)   # река (если allows_river) + деревья
