extends FseAIState


func on_enter() -> void:
	super.on_enter()
	if animator and enemy_data:
		animator.play(enemy_data.anim_locomotion)


func update(delta: float) -> void:
	if not player:
		stop_with_avoidance()
		return

	var speed: float = enemy_data.speed if enemy_data else 3.0
	navigate_to(player.global_position, speed, delta)


func check_transition(_delta: float) -> Array:
	if not player:
		return [false, ""]

	var attack_range: float = enemy_data.attack_range if enemy_data else 2.0
	if get_distance_to_player() <= attack_range:
		return [true, "attack"]

	var leash: float = enemy_data.leash_radius if enemy_data else 40.0
	var dist_from_home: float = character.global_position.distance_to(spawn_point)
	if dist_from_home > leash:
		return [true, "wander"]

	return [false, ""]
