@tool
extends Enemy
class_name Character_Demo_Enemy_1
## Вся пошаговая логика живёт в Enemy (машина состояний внутри:
## Idle / Alert / Aggro / Search). Здесь — только пресет параметров.

func _init() -> void:
	vision_range = 320.0
	vision_angle_deg = 120.0
	memory_turns = 3
	search_turns = 3
	alert_turns = 3
	wander_chance = 0.4
