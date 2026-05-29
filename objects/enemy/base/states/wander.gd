extends FseAIState

@export var min_wander_distance: float = 6.0
@export var random_point_attempts: int = 12

var _wander_initialized: bool = false


func on_enter() -> void:
	super.on_enter()
	_wander_initialized = false
	if animator and enemy_data:
		animator.play(enemy_data.anim_locomotion)


func update(delta: float) -> void:
	if not nav_agent:
		stop_with_avoidance()
		return

	var map_rid: RID = nav_agent.get_navigation_map()
	if not map_rid.is_valid() or NavigationServer3D.map_get_iteration_id(map_rid) == 0:
		stop_with_avoidance()
		return

	if not _wander_initialized:
		_wander_initialized = true
		_pick_destination()

	if nav_agent.is_navigation_finished():
		_pick_destination()

	var speed: float = enemy_data.speed if enemy_data else 3.0
	var next_pos: Vector3 = nav_agent.get_next_path_position()
	var move_dir: Vector3 = character.global_position.direction_to(next_pos)
	move_dir.y = 0.0
	if move_dir.length_squared() > 0.0001:
		move_dir = move_dir.normalized()
		navigate_to(next_pos, speed, delta)
	else:
		stop_with_avoidance()


func _pick_destination() -> void:
	var map_rid: RID = nav_agent.get_navigation_map()
	if not map_rid.is_valid() or NavigationServer3D.map_get_iteration_id(map_rid) == 0:
		return

	var origin: Vector3 = character.global_position
	for _i in random_point_attempts:
		var candidate: Vector3 = NavigationServer3D.map_get_random_point(
			map_rid, nav_agent.navigation_layers, true
		)
		if origin.distance_squared_to(candidate) >= min_wander_distance * min_wander_distance:
			nav_agent.target_position = candidate
			return

	nav_agent.target_position = NavigationServer3D.map_get_closest_point(
		map_rid, origin + Vector3(min_wander_distance, 0.0, 0.0)
	)


func check_transition(_delta: float) -> Array:
	if not player:
		return [false, ""]

	var pursue_range: float = enemy_data.pursue_range if enemy_data else 15.0
	if get_distance_to_player() <= pursue_range:
		return [true, "pursue"]

	return [false, ""]
