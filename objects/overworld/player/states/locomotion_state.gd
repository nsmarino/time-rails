extends BaseAIState

## Locomotion state - loops Walk animation when character is moving

var animator: AnimationPlayer

const MOVE_THRESHOLD: float = 0.5


func _init() -> void:
	state_name = "locomotion"


func on_enter() -> void:
	if animator:
		animator.play("Run")
		if Engine.is_editor_hint() == false:
			print("[LocomotionState] on_enter: playing Run animation (animator=%s)" % (animator != null))
	else:
		if Engine.is_editor_hint() == false:
			print("[LocomotionState] on_enter: no animator, cannot play Walk")


func check_transition(_delta: float) -> Array:
	if not owner_node is CharacterBody3D:
		return [false, ""]

	var navigator: CharacterBody3D = owner_node
	var horizontal_speed := Vector2(navigator.velocity.x, navigator.velocity.z).length()
	if horizontal_speed < MOVE_THRESHOLD:
		if Engine.is_editor_hint() == false:
			print("[LocomotionState] check_transition: speed=%.2f < %.2f -> transitioning to idle" % [horizontal_speed, MOVE_THRESHOLD])
		return [true, "idle"]
	return [false, ""]
