extends Node2D

@export var amount_of_enemies : int = 100
@export var WorldGen : WorldBuilder
@export var Tilemap : TileMapLayer
@export var AICharHolder : Node
var AIs : Array[Character_Demo_Enemy_1]
@export var ItemsHolder : Node

func _ready():
	WorldGen.generate_world()

	for y in range(WorldGen.grid.size()):          # перебираем строки (ось Y)
		for x in range(WorldGen.grid[y].size()):   # перебираем столбцы в строке (ось X)
			var val = WorldGen.grid[y][x]
			if val == 0:
				Tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))  # Вода
			else:
				Tilemap.set_cell(Vector2i(x, y), 0, Vector2i(randi_range(0, 3), 2))  # Земля

	for i in amount_of_enemies:
		var enemy = Character_Demo_Enemy_1.new()
		AICharHolder.add_child(enemy)
		AIs.append(enemy)
		enemy.position = _choose_random_position()

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var sword = ItemPickup.new()
	sword.item = DBLoader.WeaponBase[0]
	ItemsHolder.add_child(sword)
	sword.position = Vector2(16,16)

	var belt = ItemPickup.new()
	belt.item = DBLoader.ContainerBase[0]
	ItemsHolder.add_child(belt)
	belt.position = Vector2(16,16)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		for e in get_tree().get_nodes_in_group("enemies"):
			if e is Enemy: e.debug_draw = not e.debug_draw

func _choose_random_position() -> Vector2i:
	var grid_size_tiles = WorldGen.total_size - Vector2i(1,1)

	var random_tile = Vector2i(
		randi_range(0, grid_size_tiles.x),
		randi_range(0, grid_size_tiles.y)
	)

	random_tile = Vector2i(random_tile * WorldGen.TileSize)

	return random_tile + Vector2i(WorldGen.TileSize * 0.5)
