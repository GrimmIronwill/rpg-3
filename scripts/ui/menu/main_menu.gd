extends Control

## -- Профили
@export var ProfileCounter : VBoxContainer
@export var ProfileAddButton : Button
const ProfileTemplate : Dictionary = {
	"name" : "", ## Генерируется по текущей дате.
	"characters" : [], ## Список всех персонажей игрока
	"Resources" : {}, ## Ресурсы, которые имеет игрок
	"AdditionalData" : {}, ## Дамп для прочих неопределенных параметров
}
var profiles : Dictionary = {} ## Тут хранятся все профили.
var profile_key : String = "" ## Тут хранится ключ выбранного профиля

func _ready() -> void:
	_load_profiles()

## Выход.
func _exit() -> void:
	get_tree().quit()

## Загрузка всех профилей.
func _load_profiles():
	var _p = DataHolder.get_data("profile", null)
	if _p == null:
		return
	else:
		profiles = _p


func _on_add_pressed() -> void:
	var profile_name = Time.get_datetime_string_from_system(false, true)
	profile_name = profile_name.substr(0, profile_name.length() - 3)

	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size.y = 40

	var button = Button.new()
	button.text = profile_name
	button.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(button)

	var delete = Button.new()
	delete.text = "X"
	delete.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	delete.custom_minimum_size.x = 40
	hbox.add_child(delete)

	var new_profile = ProfileTemplate.duplicate(true)
	new_profile.name = profile_name

	ProfileCounter.add_child(hbox)
	ProfileCounter.move_child(ProfileAddButton, ProfileCounter.get_child_count() - 1)
