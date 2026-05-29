extends BaseAIState

## Idle state - loops Idle animation when character is standing still

var animator: AnimationPlayer

const MOVE_THRESHOLD: float = 0.5


func _init() -> void:
	state_name = "idle"


func on_enter() -> void:
	if animator:
		animator.play("Idle")
		if Engine.is_editor_hint() == false:
			print("[IdleState] on_enter: playing Idle animation (animator=%s)" % (animator != null))
	else:
		if Engine.is_editor_hint() == false:
			print("[IdleState] on_enter: no animator, cannot play Idle")


func check_transition(_delta: float) -> Array:
	if not owner_node is CharacterBody3D:
		return [false, ""]

	var navigator: CharacterBody3D = owner_node
	var horizontal_speed := Vector2(navigator.velocity.x, navigator.velocity.z).length()
	if horizontal_speed >= MOVE_THRESHOLD:
		if Engine.is_editor_hint() == false:
			print("[IdleState] check_transition: speed=%.2f >= %.2f -> transitioning to locomotion" % [horizontal_speed, MOVE_THRESHOLD])
		return [true, "locomotion"]
	return [false, ""]
