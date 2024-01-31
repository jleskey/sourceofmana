@tool
extends Button

func _ready():
	if not Engine.is_editor_hint():
		return
	icon = EditorInterface.get_editor_theme().get_icon("Reload", "EditorIcons")

func _on_pressed():
	$"../../ItemList".refresh()
