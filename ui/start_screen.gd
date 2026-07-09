extends Control

## Minimal start screen: Play loads the game scene, Quit exits. The game
## returns here on death and on victory (see levels/main.gd), so this is the
## run's reset point — re-entering main.tscn gives a completely fresh run.
##
## main.tscn stays the editor's run/main_scene for now; flip
## application/run/main_scene to this screen when packaging builds for
## collaborators.

## Scene loaded when Play is pressed.
@export_file("*.tscn") var game_scene_path: String = "res://main.tscn"

@onready var play_button: Button = $CenterContainer/VBoxContainer/PlayButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton


func _ready() -> void:
	# The game runs with the mouse captured; release it so the menu is usable
	# when we come back from a death/victory reset.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	# Land focus on Play so keyboard/gamepad menu nav (ui_up/down/accept) works
	# without a mouse.
	play_button.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(game_scene_path)


func _on_quit_pressed() -> void:
	get_tree().quit()
