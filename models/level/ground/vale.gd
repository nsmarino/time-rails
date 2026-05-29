extends Node3D

## Drives NavCharacter / NavCharacter2 to wander on the NavigationRegion3D using NavigationAgent3D + RVO avoidance.

@export var wander_speed: float = 4.0
@export var turn_speed: float = 10.0
@export var min_wander_distance: float = 6.0
@export var random_point_attempts: int = 12

var _wanderers: Array[Wanderer] = []
var _spawns_captured: bool = false


func _ready() -> void:
	_wanderers = [
		Wanderer.new($NavCharacter, $NavCharacter/NavigationAgent3D),
		Wanderer.new($NavCharacter2, $NavCharacter2/NavigationAgent3D),
	]
	for w: Wanderer in _wanderers:
		w.agent.velocity_computed.connect(_on_velocity_computed.bind(w))
	# After the whole scene tree and transforms are finalized (including instancing parents).
	call_deferred("_capture_scene_spawns_and_reset_bodies")


func _capture_scene_spawns_and_reset_bodies() -> void:
	for w: Wanderer in _wanderers:
		w.scene_spawn_global = w.character.global_transform.origin
		# Lock to editor / scene placement before any navigation queries or movement.
		w.character.global_position = w.scene_spawn_global
		w.character.velocity = Vector3.ZERO
		w.agent.set_velocity_forced(Vector3.ZERO)
	_spawns_captured = true


func _physics_process(delta: float) -> void:
	if not _spawns_captured or _wanderers.is_empty():
		return

	var map_rid: RID = _wanderers[0].agent.get_navigation_map()
	if not map_rid.is_valid():
		return
	if NavigationServer3D.map_get_iteration_id(map_rid) == 0:
		return

	for w: Wanderer in _wanderers:
		# NavigationAgent3D.max_speed defaults to 10 and caps RVO output; keep it aligned with wander_speed.
		w.agent.max_speed = wander_speed

		if not w.initialized:
			w.initialized = true
			# Re-assert pose the frame we start pathing (covers anything that moved the body before nav sync).
			w.character.global_position = w.scene_spawn_global
			w.character.velocity = Vector3.ZERO
			w.agent.set_velocity_forced(Vector3.ZERO)
			_pick_destination(w)

		if w.agent.is_navigation_finished():
			_pick_destination(w)

		var next_pos: Vector3 = w.agent.get_next_path_position()
		var move_dir: Vector3 = w.character.global_position.direction_to(next_pos)
		move_dir.y = 0.0

		var desired_velocity: Vector3 = Vector3.ZERO
		if move_dir.length_squared() > 0.0001:
			move_dir = move_dir.normalized()
			desired_velocity = move_dir * wander_speed
			_face_movement(w, move_dir, delta)

		w.agent.set_velocity(desired_velocity)


func _on_velocity_computed(safe_velocity: Vector3, wanderer: Wanderer) -> void:
	safe_velocity.y = 0.0
	wanderer.character.velocity = safe_velocity
	wanderer.character.move_and_slide()


func _pick_destination(w: Wanderer) -> void:
	var map_rid: RID = w.agent.get_navigation_map()
	if not map_rid.is_valid() or NavigationServer3D.map_get_iteration_id(map_rid) == 0:
		return

	var origin: Vector3 = w.character.global_position

	for _i in random_point_attempts:
		var candidate: Vector3 = NavigationServer3D.map_get_random_point(
			map_rid, w.agent.navigation_layers, true
		)
		if origin.distance_squared_to(candidate) >= min_wander_distance * min_wander_distance:
			w.agent.target_position = candidate
			return

	w.agent.target_position = NavigationServer3D.map_get_closest_point(
		map_rid, origin + Vector3(min_wander_distance, 0.0, 0.0)
	)


func _face_movement(w: Wanderer, horizontal_dir: Vector3, delta: float) -> void:
	var target_rotation: float = atan2(horizontal_dir.x, horizontal_dir.z)
	w.character.rotation.y = lerp_angle(
		w.character.rotation.y, target_rotation, delta * turn_speed
	)


class Wanderer:
	var character: CharacterBody3D
	var agent: NavigationAgent3D
	var scene_spawn_global: Vector3 = Vector3.ZERO
	var initialized: bool = false

	func _init(p_character: CharacterBody3D, p_agent: NavigationAgent3D) -> void:
		character = p_character
		agent = p_agent
