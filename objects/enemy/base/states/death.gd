extends FseAIState

@export var death_timer: float = 2.0


func on_enter() -> void:
	super.on_enter()
	if animator and enemy_data:
		animator.play(enemy_data.anim_receive_hit)

	if character is FseEnemy:
		(character as FseEnemy).notify_died()


func update(_delta: float) -> void:
	if character is FseEnemy:
		var fe: FseEnemy = character as FseEnemy
		fe.velocity = Vector3.ZERO
		fe.move_and_slide()
	else:
		character.velocity = Vector3.ZERO
		character.move_and_slide()


func check_transition(_delta: float) -> Array:
	if duration_longer_than(death_timer):
		character.queue_free()
	return [false, ""]
