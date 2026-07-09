extends Node3D

## Main scene controller — registers navigator and overworld with GameManager
## and runs the level-wide end states:
##   - Death: player_killed → delayed quit (death sequence plays out).
##   - Victory: any door-unlocked FseExitRail reports completion on the Events
##     bus → the rig keeps flying straight while the screen fades to black,
##     then the game exits.
## The door → exit-rail handoff itself lives on the rails (levels/exit_rail.gd),
## wired per-door in the Inspector.

## Seconds to wait after the player is killed before quitting. This window is
## where a death sequence (the HitReactComponent death burst, a "YOU DIED"
## animation, a greyscale shader, etc.) gets to play out before the game ends.
@export var death_quit_delay: float = 5.0

@export_category("Victory")
## Seconds the fade-to-black takes once an exit rail ends.
@export var victory_fade_duration: float = 3.0
## Extra hold on full black before the game exits.
@export var victory_quit_delay: float = 0.5

@onready var navigator: CharacterBody3D = $Level/Rail/RailFollow/PlayerRoot/Navigator
@onready var rail_follow: PathFollow3D = $Level/Rail/RailFollow
@onready var player_root: Node3D = $Level/Rail/RailFollow/PlayerRoot
@onready var level: Node3D = $Level
@onready var fade_rect: ColorRect = $FadeLayer/FadeRect

# Guards against scheduling more than one quit if player_killed ever re-fires.
var _quitting: bool = false

var _victory: bool = false
var _fly_dir: Vector3 = Vector3.FORWARD
var _fly_speed: float = 20.0


func _ready() -> void:
	Events.player_killed.connect(_on_player_killed)
	Events.exit_rail_completed.connect(_on_exit_rail_completed)
	_register_with_game_manager()


func _physics_process(delta: float) -> void:
	if _victory:
		# The exit rail has ended; keep the rig flying straight while the fade
		# rolls. (The follower's progress is clamped at the rail end, so the
		# motion continues on PlayerRoot.)
		player_root.global_position += _fly_dir * _fly_speed * delta


## An exit rail reports the rig reached its end: fly on, fade to black, quit.
func _on_exit_rail_completed(_rail: Node) -> void:
	if _victory:
		return
	_victory = true
	_fly_dir = -rail_follow.global_transform.basis.z
	if "speed" in rail_follow:
		_fly_speed = rail_follow.speed
	print("[Main] Victory! Exit rail complete — fading out.")
	var tween: Tween = create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, victory_fade_duration)
	tween.tween_interval(maxf(victory_quit_delay, 0.01))
	tween.tween_callback(get_tree().quit)


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
