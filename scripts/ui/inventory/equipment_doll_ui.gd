@tool
class_name EquipmentDollUI
extends Control
## Кукла игрока. Слоты — отдельные узлы EquipmentSlotUI, ищутся рекурсивно
## на ЛЮБОМ уровне вложенности под этим узлом — раскладывай как хочешь.
## Если слотов в сцене нет — в рантайме создаётся дефолтная раскладка.
## В редакторе поставь галку build_slots_in_editor, чтобы создать недостающие
## слоты как узлы сцены и растащить их вручную.

signal unequip_requested(slot_id: int)

@export var cell_size : int = 52
@export var cell_gap : int = 6

## Кнопка-галка: создать недостающие слоты в редакторе (сохранятся в сцену).
@export var build_slots_in_editor : bool = false:
	set(v):
		build_slots_in_editor = false
		if v and Engine.is_editor_hint() and is_inside_tree():
			_create_missing_slots(true)

const ES = GameEnums.EquipSlot

## Дефолтная раскладка (колонка, ряд) — используется только при авто-создании.
const LAYOUT := {
	ES.HEAD_PRIMARY:    Vector2i(2, 0),
	ES.HEAD_SECONDARY:  Vector2i(3, 0),
	ES.AMULET:          Vector2i(1, 1),
	ES.TORSO_PRIMARY:   Vector2i(2, 1),
	ES.TORSO_SECONDARY: Vector2i(3, 1),
	ES.BACK:            Vector2i(4, 1),
	ES.HAND_1:          Vector2i(0, 2),
	ES.ARMS:            Vector2i(1, 2),
	ES.BODY_SLOT_1:     Vector2i(2, 2),
	ES.BODY_SLOT_2:     Vector2i(3, 2),
	ES.GLOVES:          Vector2i(4, 2),
	ES.HAND_2:          Vector2i(5, 2),
	ES.RING_1:          Vector2i(0, 3),
	ES.RING_2:          Vector2i(1, 3),
	ES.BELT:            Vector2i(2, 3),
	ES.LEGS_PRIMARY:    Vector2i(3, 3),
	ES.RING_3:          Vector2i(4, 3),
	ES.RING_4:          Vector2i(5, 3),
	ES.POCKET_1:        Vector2i(1, 4),
	ES.LEGS_SECONDARY:  Vector2i(2, 4),
	ES.FEET:            Vector2i(3, 4),
	ES.POCKET_2:        Vector2i(4, 4),
}

const COL_BG := Color(0, 0, 0, 0.35)

var equipment : PlayerEquipment:
	set(v):
		equipment = v
		_wire_slots()   # PlayerInventory может назначить куклу ДО _ready — ок

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # клики ловят сами слоты
	if not Engine.is_editor_hint() and get_slots().is_empty():
		_create_missing_slots(false)
	_wire_slots()

## Все слоты на любой глубине вложенности.
func get_slots() -> Array[EquipmentSlotUI]:
	var out : Array[EquipmentSlotUI] = []
	_collect(self, out)
	return out

func _collect(node: Node, out: Array[EquipmentSlotUI]) -> void:
	for c in node.get_children():
		if c is EquipmentSlotUI:
			out.append(c)
		_collect(c, out)

func _wire_slots() -> void:
	for s in get_slots():
		s.equipment = equipment
		if not s.unequip_requested.is_connected(_on_slot_unequip):
			s.unequip_requested.connect(_on_slot_unequip)

func _on_slot_unequip(slot_id: int) -> void:
	unequip_requested.emit(slot_id)

## Создаёт недостающие слоты. persist=true — сохранить в сцену (редактор).
func _create_missing_slots(persist: bool) -> void:
	var have := {}
	for s in get_slots():
		have[s.slot_id] = true

	var maxc := Vector2i.ZERO
	for slot_id in LAYOUT:
		var c : Vector2i = LAYOUT[slot_id]
		maxc.x = maxi(maxc.x, c.x + 1)
		maxc.y = maxi(maxc.y, c.y + 1)
		if have.has(slot_id):
			continue
		var s := EquipmentSlotUI.new()
		s.name = "Slot_" + GameEnums.equip_slot_label(slot_id)
		s.slot_id = slot_id
		s.cell_size = cell_size
		s.position = Vector2(
			cell_gap + c.x * (cell_size + cell_gap),
			cell_gap + c.y * (cell_size + cell_gap))
		add_child(s)
		if persist:
			s.owner = get_tree().edited_scene_root

	custom_minimum_size = Vector2(
		maxc.x * (cell_size + cell_gap) + cell_gap,
		maxc.y * (cell_size + cell_gap) + cell_gap)
	_wire_slots()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)

## Включить/выключить подсветку всех слотов (item = null — выключить).
func _set_drag_preview(item: Item) -> void:
	for s in get_slots():
		s.preview_item = item

## Слот куклы под глобальной позицией курсора (или null).
func _slot_at_global(pos: Vector2) -> EquipmentSlotUI:
	for s in get_slots():
		if s.is_visible_in_tree() and s.get_global_rect().has_point(pos):
			return s
	return null
