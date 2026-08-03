extends Node

const resource : DBDatabase = preload("res://data/GlobalDatabase.tres")
const ItemsTable = "Items"
const EquipmentTable = "Equipment"
const WeaponsTable = "Weapons"
const ConsumablesTable = "Consumables"
const CharacterStatsTable = "CharacterStats"
const RandomTable = "RandomTable"
const ContainerTable = "Containers"

var ItemBase : Array[Item]
var EquipmentBase : Array[ItemEquipment]
var WeaponBase : Array[ItemWeapon]
var ConsumablesBase : Array[ItemConsumable]
var CharacterStatsBase : Array[CharacterStats]
var RandomBase : Array
var ContainerBase : Array[ItemContainer]

func _ready():
	_load_database(resource)

func _load_database(path : DBDatabase) -> void:
	DB.load_database(path)

	ItemBase = _populate_items()
	EquipmentBase = _populate_equipment()
	WeaponBase = _populate_weapon()
	ConsumablesBase = _populate_consumable()
	CharacterStatsBase = _populate_character_stats()
	RandomBase = _populate_random()
	ContainerBase = _populate_containers()

func _populate_items() -> Array[Item]:
	var arr : Array[Item]

	for row in DB.get_rows(ItemsTable):
		var item = Item.new()
		item.fill_from_dict(row)
		arr.append(item)

	return arr

func _populate_equipment() -> Array[ItemEquipment]:
	var arr : Array[ItemEquipment]

	for row in DB.get_rows(EquipmentTable):
		var item = ItemEquipment.new()
		item.fill_from_dict(row)
		arr.append(item)

	return arr

func _populate_weapon() -> Array[ItemWeapon]:
	var arr : Array[ItemWeapon]

	for row in DB.get_rows(WeaponsTable):
		var item = ItemWeapon.new()
		item.fill_from_dict(row)
		arr.append(item)

	return arr

func _populate_consumable() -> Array[ItemConsumable]:
	var arr : Array[ItemConsumable]

	for row in DB.get_rows(ConsumablesTable):
		var item = ItemConsumable.new()
		item.fill_from_dict(row)
		arr.append(item)

	return arr

func _populate_character_stats() -> Array[CharacterStats]:
	var arr : Array[CharacterStats]

	for row in DB.get_rows(CharacterStatsTable):
		var item = CharacterStats.new()
		item.fill_from_dict(row)
		arr.append(item)

	return arr

func _populate_random():
	var arr : Array

	for row in DB.get_rows(RandomTable):
		arr.append(row)

	return arr

func _populate_containers() -> Array[ItemContainer]:
	var arr : Array[ItemContainer]

	for row in DB.get_rows(ContainerTable):
		var item = ItemContainer.new()
		item.fill_from_dict(row)
		arr.append(item)

	return arr
