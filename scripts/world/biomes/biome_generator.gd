@tool
extends Resource
class_name BiomeGenerator

## Базовый класс биома. Наследники переопределяют generate().
## Сохраняй конкретные биомы как .tres и кидай в WorldBuilder.

@export_group("Общее поведение биома")
## Можно ли поверх биома рисовать реку (forest/mountains — да, dungeon — нет)
@export var allows_river : bool = true
## Множитель количества деревьев для этого биома (0.0 = без деревьев)
@export var tree_density_factor : float = 1.0


## Главный метод. ОБЯЗАН быть переопределён в наследнике.
## builder — это WorldBuilder, через него доступны grid/terrain_types/шум/примитивы.
func generate(_builder) -> void:
	push_error("BiomeGenerator.generate() должен быть переопределён в наследнике!")


## Рандомизация параметров биома (для FullRandom). Переопределяется при необходимости.
func randomize_params() -> void:
	pass


## Хелпер: дёргается из generate() в конце, чтобы единообразно повесить реку + деревья.
func _finish(builder) -> void:
	if allows_river and builder.has_river():
		builder.generate_river()
	builder.generate_trees_scaled(tree_density_factor)
