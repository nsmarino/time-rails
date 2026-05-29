extends BaseAIState
class_name FseAIState

## Open-field FSE enemy state helpers (navigation + RVO).

@export var animation: String = ""

var player: CharacterBody3D
var character: CharacterBody3D
var animator: AnimationPlayer
var spawn_point: Vector3
var nav_agent: NavigationAgent3D
var attack_area: Area3D
var enemy_data: FseEnemyData


func on_enter() -> void:
	Events.enemy_state_changed.emit(character, state_name)


func get_distance_to_player() -> float:
	if player:
		return character.global_position.distance_to(player.global_position)
	return 999.0


func navigate_to(target: Vector3, speed: float, delta: float) -> void:
	if nav_agent:
		nav_agent.max_speed = speed

	var ground_target: Vector3 = Vector3(target.x, character.global_position.y, target.z)
	var current_pos: Vector3 = character.global_position

	var direct_distance: float = current_pos.distance_to(ground_target)
	if direct_distance < 0.5:
		stop_with_avoidance()
		return

	var direction: Vector3
	var use_direct_movement: bool = false

	if nav_agent:
		var map_rid: RID = nav_agent.get_navigation_map()
		if map_rid.is_valid() and NavigationServer3D.map_get_iteration_id(map_rid) == 0:
			stop_with_avoidance()
			return

		nav_agent.target_position = ground_target

		if nav_agent.is_target_reachable() and not nav_agent.is_navigation_finished():
			var next_pos: Vector3 = nav_agent.get_next_path_position()
			direction = (next_pos - current_pos)
			direction.y = 0

			if direction.length() < 0.1:
				use_direct_movement = true
			else:
				direction = direction.normalized()
		else:
			use_direct_movement = true
	else:
		use_direct_movement = true

	if use_direct_movement:
		direction = (ground_target - current_pos)
		direction.y = 0
		if direction.length() > 0.1:
			direction = direction.normalized()
		else:
			stop_with_avoidance()
			return

	var desired_velocity: Vector3 = direction * speed

	var target_rotation: float = atan2(direction.x, direction.z)
	character.rotation.y = lerp_angle(character.rotation.y, target_rotation, delta * 10.0)

	move_with_avoidance(desired_velocity)


func move_away_from(target: Vector3, speed: float, delta: float) -> void:
	if nav_agent:
		nav_agent.max_speed = speed

	var direction: Vector3 = (character.global_position - target).normalized()
	direction.y = 0

	if direction.length() < 0.1:
		stop_with_avoidance()
		return

	var target_rotation: float = atan2(direction.x, direction.z)
	character.rotation.y = lerp_angle(character.rotation.y, target_rotation, delta * 10.0)

	var desired_velocity: Vector3 = direction * speed
	move_with_avoidance(desired_velocity)


func face_player(delta: float) -> void:
	if player:
		var direction: Vector3 = (player.global_position - character.global_position).normalized()
		direction.y = 0
		if direction.length() > 0.1:
			var target_rotation: float = atan2(direction.x, direction.z)
			character.rotation.y = lerp_angle(character.rotation.y, target_rotation, delta * 10.0)


func move_with_avoidance(desired_velocity: Vector3) -> void:
	if nav_agent and nav_agent.avoidance_enabled:
		nav_agent.set_velocity(desired_velocity)
	else:
		character.velocity = desired_velocity
		character.move_and_slide()


func stop_with_avoidance() -> void:
	if nav_agent and nav_agent.avoidance_enabled:
		nav_agent.set_velocity(Vector3.ZERO)
	else:
		character.velocity = Vector3.ZERO
		character.move_and_slide()
