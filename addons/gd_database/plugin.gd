@tool
extends EditorPlugin
var _editor_panel: Control = null

func _enter_tree() -> void:
	_editor_panel = DatabaseEditor.new()
	_editor_panel.set_plugin(self)
	add_control_to_bottom_panel(_editor_panel, "GD Database")
	print("[GD Database] Plugin loaded.")

func _exit_tree() -> void:
	if _editor_panel:
		remove_control_from_bottom_panel(_editor_panel)
		_editor_panel.queue_free()
		_editor_panel = null

func _handles(object: Object) -> bool:
	return object is DBDatabase

func _edit(object: Object) -> void:
	if object is DBDatabase:
		_editor_panel.load_database(object as DBDatabase)
		make_bottom_panel_item_visible(_editor_panel)

func _apply_changes() -> void:
	if _editor_panel:
		_editor_panel.save_current_database()
