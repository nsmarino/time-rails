extends Node3D

## Main scene controller — registers navigator and overworld with GameManager.

## Seconds to wait after the player is killed before quitting. This window is
## where a death sequence (the HitReactComponent death burst, a "YOU DIED"
## animation, a greyscale shader, etc.) gets to play out before the game ends.
@export var death_quit_delay: float = 5.0

@onready var navigator: CharacterBody3D = $Level/Rail/RailFollow/PlayerRoot/Navigator
@onready var level: Node3D = $Level

# Guards against scheduling more than one quit if player_killed ever re-fires.
var _quitting: bool = false


func _ready() -> void:
	Events.player_killed.connect(_on_player_killed)
	_register_with_game_manager()


func _register_with_game_manager() -> void:
	await get_tree().process_frame

	if GameManager:
		GameManager.register_navigator(navigator)
		GameManager.register_overworld(level)
		print("[Main] Registered navigator, overworld, and lighting with GameManager")
	else:
		push_error("[Main] GameManager autoload not found!")


func _on_player_killed() -> void:
	if _quitting:
		return
	_quitting = true
	# Give the death sequence time to play, then quit. A zero/negative delay
	# quits immediately (create_timer requires a positive time).
	if death_quit_delay > 0.0:
		await get_tree().create_timer(death_quit_delay).timeout
	get_tree().quit()
