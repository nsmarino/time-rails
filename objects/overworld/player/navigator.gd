extends CharacterBody3D

## Exploration character controller with third-person camera
## Movement is relative to camera direction

@export_category("Movement")
@export var move_speed: float = 12.0
@export var vertical_speed: float = 8.0  # Fly mode vertical speed

@export_category("Gravity Mode")
@export var use_gravity: bool = false  # Toggle in Inspector
@export var gravity_strength: float = 30.0
@export var jump_velocity: float = 10.0
@export var air_control: float = 0.3  # Movement control while airborne (0-1)

@export_category("Camera")
@export var mouse_sensitivity: float = 0.003
@export var gamepad_look_sensitivity: float = 3.0

@export_category("Combat")
@export var default_weapon_scene: PackedScene
@export var aim_ray_length: float = 1000.0
@export var projectile_zero_distance: float = 60.0
@export var aim_ignore_hit_distance: float = 1.5
@export var min_muzzle_target_distance: float = 2.5
@export var min_muzzle_forward_dot: float = 0.2

@export_category("ADS")
@export var ads_camera_local_offset: Vector3 = Vector3(1.15, 0.2, 0.0)
@export var ads_right_shoulder: bool = true
@export var ads_transition_speed: float = 10.0
@export var ads_move_speed_multiplier: float = 0.55
@export var ads_spring_length: float = 4.5
@export var ads_fov: float = 40.0
@export var ads_fov_lerp_speed: float = 10.0
@export var ads_pitch_min_deg: float = -35.0
@export var ads_pitch_max_deg: float = 25.0
@export var ads_yaw_deadzone_deg: float = 12.0
@export var ads_root_turn_rate_deg: float = 120.0
@export var ads_elena_turn_lerp: float = 0.2
@export var hip_elena_reset_lerp: float = 0.15

@export_category("Dodge / Sprint")
@export var dodge_impulse_strength: float = 18.0
@export var ads_dodge_impulse_strength: float = 12.0
@export var dodge_duration: float = 0.18
@export var dodge_cooldown: float = 0.35
@export var sprint_move_speed_multiplier: float = 1.6
@export var sprint_spring_length_bonus: float = 0.75
@export var sprint_camera_lerp_speed: float = 8.0
@export var dodge_sfx_pitch_scale: float = 0.82

# Camera spring arm - add as child of this CharacterBody3D
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera_rig: Node3D = $SpringArm3D/CameraRig
@onready var camera: Camera3D = $SpringArm3D/CameraRig/Camera3D
@onready var elena: Node3D = $elena  # Player model - faces camera when moving
@onready var jump_sfx: AudioStreamPlayer3D = get_node_or_null("SFX/Jump") as AudioStreamPlayer3D
@onready var land_sfx: AudioStreamPlayer3D = get_node_or_null("SFX/Land") as AudioStreamPlayer3D
@onready var enter_aim_sfx: AudioStreamPlayer3D = get_node_or_null("SFX/EnterAim") as AudioStreamPlayer3D
@onready var dodge_sfx: AudioStreamPlayer3D = get_node_or_null("SFX/Dodge") as AudioStreamPlayer3D
@onready var dodge_burst: GPUParticles3D = get_node_or_null("DodgeBurst") as GPUParticles3D

var camera_rotation := Vector2.ZERO  # x = yaw, y = pitch
var pitch_limit := deg_to_rad(89.0)
var weapon_socket: Node3D = null
var weapon_aim_pivot: Node3D = null
var equipped_weapon: Node3D = null
var _pending_look_delta: Vector2 = Vector2.ZERO
var _is_ads_active: bool = false
var _camera_yaw_offset: float = 0.0
var _hip_camera_local_position: Vector3 = Vector3.ZERO
var _hip_spring_length: float = 0.0
var _hip_fov: float = 0.0
var _needs_elena_hip_reset: bool = false
var _has_floor_state: bool = false
var _was_on_floor: bool = false
var _dodge_timer: float = 0.0
var _dodge_cooldown_timer: float = 0.0
var _dodge_velocity: Vector3 = Vector3.ZERO
var _preserve_facing_during_dodge: bool = false


func _ready() -> void:
	# Capture mouse for camera control
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_hip_camera_local_position = camera.position
	_hip_spring_length = spring_arm.spring_length
	_hip_fov = camera.fov
	weapon_socket = _resolve_weapon_socket()
	weapon_aim_pivot = _resolve_weapon_aim_pivot()
	_equip_default_weapon()


func _input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_pending_look_delta.x -= event.relative.x * mouse_sensitivity
		_pending_look_delta.y -= event.relative.y * mouse_sensitivity
	
	# Toggle mouse capture with Escape
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	_update_ads_state()
	_update_dodge_cooldown(delta)
	_handle_sprint_input()
	_handle_camera_input(delta)
	_update_ads_camera(delta)
	_handle_combat_input()
	
	if use_gravity:
		_process_gravity_movement(delta)
	else:
		_process_fly_movement(delta)
	
	move_and_slide()
	_update_dodge(delta)
	_update_landing_sfx()
	_update_elena_facing(delta)
	_update_weapon_aim_pivot()


func _handle_camera_input(delta: float) -> void:
	var look_delta: Vector2 = _pending_look_delta
	_pending_look_delta = Vector2.ZERO

	# Gamepad camera look (right stick)
	look_delta.x -= Input.get_axis("LookLeft", "LookRight") * gamepad_look_sensitivity * delta
	look_delta.y -= Input.get_axis("LookUp", "LookDown") * gamepad_look_sensitivity * delta

	if _is_ads_active:
		_apply_ads_look(look_delta, delta)
	else:
		_apply_hip_look(look_delta)

	# Apply resolved camera rotation to spring arm
	spring_arm.rotation.y = _camera_yaw_offset if _is_ads_active else camera_rotation.x
	spring_arm.rotation.x = camera_rotation.y


func _handle_combat_input() -> void:
	if _is_dialogue_locked():
		return
	if not _is_ads_active:
		return
	if not equipped_weapon:
		return

	var trigger_pressed: bool = Input.is_action_pressed("CombatAttack")
	var trigger_just_pressed: bool = Input.is_action_just_pressed("CombatAttack")

	var wants_fire: bool = trigger_pressed
	if equipped_weapon.has_method("should_fire_for_input"):
		wants_fire = bool(equipped_weapon.call("should_fire_for_input", trigger_pressed, trigger_just_pressed))

	if wants_fire:
		equipped_weapon.try_fire(_get_camera_aim_direction())


func _handle_sprint_input() -> void:
	if _is_dialogue_locked():
		return
	if not Input.is_action_just_pressed("Sprint"):
		return
	if not is_on_floor():
		return
	if _dodge_cooldown_timer > 0.0:
		return

	_start_dodge()


func _start_dodge() -> void:
	var movement_direction: Vector3 = _get_movement_direction()
	movement_direction.y = 0.0
	_preserve_facing_during_dodge = movement_direction.length_squared() <= 0.0001

	var direction: Vector3 = _get_dodge_direction(movement_direction)
	if direction.length_squared() < 0.0001:
		return

	var impulse_strength: float = ads_dodge_impulse_strength if _is_ads_active else dodge_impulse_strength
	_dodge_velocity = direction.normalized() * impulse_strength
	_dodge_timer = dodge_duration
	_dodge_cooldown_timer = dodge_cooldown
	velocity.x = _dodge_velocity.x
	velocity.z = _dodge_velocity.z
	_play_sfx(dodge_sfx, dodge_sfx_pitch_scale)
	_emit_dodge_burst(direction)


func _get_dodge_direction(move_dir: Vector3 = Vector3.ZERO) -> Vector3:
	move_dir.y = 0.0
	if move_dir.length_squared() > 0.0001:
		return move_dir.normalized()

	var backward: Vector3 = camera.global_transform.basis.z
	backward.y = 0.0
	if backward.length_squared() > 0.0001:
		return backward.normalized()

	return -global_transform.basis.z


func _emit_dodge_burst(dodge_direction: Vector3) -> void:
	if not dodge_burst:
		return

	var emit_direction: Vector3 = -dodge_direction.normalized()
	dodge_burst.global_transform = Transform3D(
		Basis.looking_at(emit_direction, Vector3.UP),
		global_position + Vector3(0.0, 0.2, 0.0)
	)
	dodge_burst.visible = true
	dodge_burst.emitting = false
	dodge_burst.restart()
	dodge_burst.emitting = true


func _update_dodge(delta: float) -> void:
	if _dodge_timer <= 0.0:
		return

	_dodge_timer = maxf(_dodge_timer - delta, 0.0)
	if _dodge_timer <= 0.0:
		_dodge_velocity = Vector3.ZERO
		_preserve_facing_during_dodge = false


func _is_dodging() -> bool:
	return _dodge_timer > 0.0


func _update_dodge_cooldown(delta: float) -> void:
	if _dodge_cooldown_timer <= 0.0:
		return

	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)


func _get_movement_direction() -> Vector3:
	if _is_dialogue_locked():
		return Vector3.ZERO
	
	# Movement input (left stick / WASD)
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("MoveLeft", "MoveRight")
	input_dir.y = Input.get_axis("MoveForward", "MoveBackward")
	
	# Get camera's forward and right vectors (flattened for horizontal movement)
	var cam_basis := spring_arm.global_transform.basis
	var forward := -cam_basis.z
	var right := cam_basis.x
	
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	
	# Calculate movement direction
	var move_dir := Vector3.ZERO
	move_dir += forward * -input_dir.y  # Forward/backward
	move_dir += right * input_dir.x      # Left/right
	
	if move_dir.length() > 0:
		move_dir = move_dir.normalized()
	
	return move_dir


func _process_fly_movement(_delta: float) -> void:
	var move_dir := _get_movement_direction()
	var vertical_input := 0.0 if _is_dialogue_locked() else Input.get_axis("FlyDown", "FlyUp")
	var current_move_speed: float = _get_current_move_speed()
	
	if _is_dodging():
		velocity.x = _dodge_velocity.x
		velocity.z = _dodge_velocity.z
	else:
		velocity.x = move_dir.x * current_move_speed
		velocity.z = move_dir.z * current_move_speed
	velocity.y = vertical_input * vertical_speed


func _process_gravity_movement(delta: float) -> void:
	var move_dir := _get_movement_direction()
	var on_floor := is_on_floor()
	var current_move_speed: float = _get_current_move_speed()
	
	# Apply gravity
	if not on_floor:
		velocity.y -= gravity_strength * delta
	
	# Jump (use FlyUp action or Jump action)
	var wants_jump := false
	if not _is_dialogue_locked():
		wants_jump = Input.is_action_just_pressed("FlyUp") or Input.is_action_just_pressed("Jump")
	if wants_jump and on_floor:
		velocity.y = jump_velocity
		_play_sfx(jump_sfx)
	
	# Horizontal movement (reduced control in air)
	var control := 1.0 if on_floor else air_control
	var target_velocity_x := move_dir.x * current_move_speed
	var target_velocity_z := move_dir.z * current_move_speed
	
	if _is_dodging():
		velocity.x = _dodge_velocity.x
		velocity.z = _dodge_velocity.z
	else:
		velocity.x = lerp(velocity.x, target_velocity_x, control)
		velocity.z = lerp(velocity.z, target_velocity_z, control)


func _update_landing_sfx() -> void:
	var on_floor: bool = is_on_floor()
	if use_gravity and _has_floor_state and not _was_on_floor and on_floor:
		_play_sfx(land_sfx)

	_was_on_floor = on_floor
	_has_floor_state = true


func _play_sfx(player: AudioStreamPlayer3D, pitch_scale: float = 1.0) -> void:
	if not player:
		return

	player.stop()
	player.pitch_scale = pitch_scale
	player.play()


func _update_elena_facing(_delta: float) -> void:
	if _is_dodging() and _preserve_facing_during_dodge:
		return

	if _is_ads_active:
		var aim_dir: Vector3 = -camera.global_transform.basis.z
		aim_dir.y = 0.0
		if aim_dir.length_squared() > 0.0001:
			var target_global_yaw: float = atan2(aim_dir.x, aim_dir.z)
			var target_local_yaw: float = target_global_yaw - global_rotation.y
			elena.rotation.y = lerp_angle(elena.rotation.y, target_local_yaw, ads_elena_turn_lerp)
		return

	# Rotate player model to face movement direction only when in motion
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.5:
		if _needs_elena_hip_reset:
			elena.rotation.y = lerp_angle(elena.rotation.y, 0.0, hip_elena_reset_lerp)
			if absf(wrapf(elena.rotation.y, -PI, PI)) < 0.02:
				elena.rotation.y = 0.0
				_needs_elena_hip_reset = false
		return

	var move_dir := Vector3(velocity.x, 0, velocity.z).normalized()
	if move_dir.length_squared() < 0.01:
		return

	var move_global_yaw: float = atan2(move_dir.x, move_dir.z)
	var move_local_yaw: float = move_global_yaw - global_rotation.y
	elena.rotation.y = move_local_yaw
	_needs_elena_hip_reset = false


func _is_dialogue_locked() -> bool:
	return Events and Events.is_dialogue_active


func _get_current_move_speed() -> float:
	if _is_ads_active:
		return move_speed * ads_move_speed_multiplier
	if _is_sprinting():
		return move_speed * sprint_move_speed_multiplier
	return move_speed


func _is_sprinting() -> bool:
	if _is_dialogue_locked():
		return false
	if _is_ads_active:
		return false
	if _is_dodging():
		return false
	return is_on_floor() and Input.is_action_pressed("Sprint")


func _update_ads_state() -> void:
	var wants_ads: bool = not _is_dialogue_locked() and Input.is_action_pressed("AimDownSights")
	if wants_ads == _is_ads_active:
		return

	_is_ads_active = wants_ads
	if _is_ads_active:
		_enter_ads_mode()
	else:
		_exit_ads_mode()


func _enter_ads_mode() -> void:
	_play_sfx(enter_aim_sfx)
	# Fold current spring-arm yaw into the character so ADS starts centered.
	rotation.y += spring_arm.rotation.y
	camera_rotation.x = 0.0
	_camera_yaw_offset = 0.0
	camera_rotation.y = clamp(camera_rotation.y, _get_ads_pitch_min(), _get_ads_pitch_max())


func _exit_ads_mode() -> void:
	_play_sfx(enter_aim_sfx, 1.08)
	camera_rotation.x = _camera_yaw_offset
	_camera_yaw_offset = 0.0
	camera_rotation.y = clamp(camera_rotation.y, -pitch_limit, pitch_limit)
	_needs_elena_hip_reset = true


func _update_ads_camera(delta: float) -> void:
	var target: Vector3 = _get_ads_camera_target_local_position() if _is_ads_active else _hip_camera_local_position
	var target_spring_length: float = _get_target_spring_length()
	var target_fov: float = ads_fov if _is_ads_active else _hip_fov
	var t: float = clampf(ads_transition_speed * delta, 0.0, 1.0)
	var spring_lerp_speed: float = ads_transition_speed if _is_ads_active else sprint_camera_lerp_speed
	var spring_t: float = clampf(spring_lerp_speed * delta, 0.0, 1.0)
	var fov_t: float = clampf(ads_fov_lerp_speed * delta, 0.0, 1.0)
	camera.position = camera.position.lerp(target, t)
	spring_arm.spring_length = lerpf(spring_arm.spring_length, target_spring_length, spring_t)
	camera.fov = lerpf(camera.fov, target_fov, fov_t)


func _get_target_spring_length() -> float:
	if _is_ads_active:
		return ads_spring_length
	if _is_sprinting():
		return _hip_spring_length + sprint_spring_length_bonus
	return _hip_spring_length


func _apply_hip_look(look_delta: Vector2) -> void:
	camera_rotation.x += look_delta.x
	camera_rotation.y = clamp(camera_rotation.y + look_delta.y, -pitch_limit, pitch_limit)


func _apply_ads_look(look_delta: Vector2, delta: float) -> void:
	camera_rotation.y = clamp(camera_rotation.y + look_delta.y, _get_ads_pitch_min(), _get_ads_pitch_max())
	_camera_yaw_offset += look_delta.x

	var deadzone: float = deg_to_rad(ads_yaw_deadzone_deg)
	var max_turn: float = deg_to_rad(ads_root_turn_rate_deg) * delta

	if _camera_yaw_offset > deadzone:
		var overflow_right: float = _camera_yaw_offset - deadzone
		var turn_right: float = min(overflow_right, max_turn)
		rotation.y += turn_right
		_camera_yaw_offset -= turn_right
	elif _camera_yaw_offset < -deadzone:
		var overflow_left: float = _camera_yaw_offset + deadzone
		var turn_left: float = max(overflow_left, -max_turn)
		rotation.y += turn_left
		_camera_yaw_offset -= turn_left


func _get_ads_pitch_min() -> float:
	return deg_to_rad(ads_pitch_min_deg)


func _get_ads_pitch_max() -> float:
	return deg_to_rad(ads_pitch_max_deg)


func is_ads_active() -> bool:
	return _is_ads_active


func _get_ads_camera_target_local_position() -> Vector3:
	var shoulder_sign: float = 1.0 if ads_right_shoulder else -1.0
	var offset: Vector3 = ads_camera_local_offset
	offset.x = absf(offset.x) * shoulder_sign
	return _hip_camera_local_position + offset


func _update_weapon_aim_pivot() -> void:
	if not weapon_aim_pivot:
		return

	var aim_direction: Vector3 = _get_camera_aim_direction() if _is_ads_active else _get_weapon_forward_direction()
	if aim_direction.length_squared() < 0.0001:
		return

	var pivot_transform: Transform3D = weapon_aim_pivot.global_transform
	pivot_transform.origin = _get_weapon_trail_origin(aim_direction)

	if not _is_ads_active:
		pivot_transform.basis = weapon_socket.global_transform.basis if weapon_socket else global_transform.basis
		weapon_aim_pivot.global_transform = pivot_transform
		return

	pivot_transform.basis = Basis.looking_at(aim_direction.normalized(), Vector3.UP)
	weapon_aim_pivot.global_transform = pivot_transform


func _get_weapon_forward_direction() -> Vector3:
	if equipped_weapon and equipped_weapon.has_node("Muzzle"):
		var muzzle_node: Node = equipped_weapon.get_node("Muzzle")
		if muzzle_node is Node3D:
			return -muzzle_node.global_transform.basis.z

	if weapon_socket:
		return -weapon_socket.global_transform.basis.z

	return -global_transform.basis.z


func _get_weapon_muzzle_position() -> Vector3:
	if equipped_weapon and equipped_weapon.has_node("Muzzle"):
		var muzzle_node: Node = equipped_weapon.get_node("Muzzle")
		if muzzle_node is Node3D:
			return (muzzle_node as Node3D).global_position

	if weapon_socket:
		return weapon_socket.global_position

	return global_position + Vector3(0, 1.5, 0)


func _get_weapon_trail_origin(direction: Vector3) -> Vector3:
	var offset: float = 0.0
	if equipped_weapon:
		var offset_value: Variant = equipped_weapon.get("muzzle_spawn_offset")
		if offset_value != null:
			offset = float(offset_value)

	return _get_weapon_muzzle_position() + direction.normalized() * offset


func _equip_default_weapon() -> void:
	if not default_weapon_scene:
		push_warning("[Navigator] No default weapon scene assigned.")
		return
	if not weapon_socket:
		push_error("[Navigator] WeaponSocket not found in navigator scene.")
		return

	var inst: Node = default_weapon_scene.instantiate()
	if not inst.has_method("try_fire"):
		push_error("[Navigator] default_weapon_scene root must expose try_fire().")
		return
	if not inst is Node3D:
		push_error("[Navigator] default_weapon_scene root must inherit Node3D.")
		return

	equipped_weapon = inst as Node3D
	weapon_socket.add_child(equipped_weapon)
	equipped_weapon.owner_character = self


func _resolve_weapon_socket() -> Node3D:
	if elena and elena.has_node("WeaponSocket"):
		var socket: Node = elena.get_node("WeaponSocket")
		if socket is Node3D:
			return socket as Node3D

	if has_node("WeaponSocket"):
		var root_socket: Node = get_node("WeaponSocket")
		if root_socket is Node3D:
			return root_socket as Node3D

	return null


func _resolve_weapon_aim_pivot() -> Node3D:
	if weapon_socket and weapon_socket.has_node("WeaponAimPivot"):
		var pivot: Node = weapon_socket.get_node("WeaponAimPivot")
		if pivot is Node3D:
			return pivot as Node3D

	return null


func _get_camera_aim_direction() -> Vector3:
	var origin: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_transform.basis.z
	var target: Vector3 = origin + forward * aim_ray_length

	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [self]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var hit_position: Vector3 = result["position"]
		if origin.distance_to(hit_position) <= aim_ignore_hit_distance:
			target = origin + forward * projectile_zero_distance
		else:
			target = hit_position
	else:
		# TPS zeroing: when nothing is hit, converge toward a practical distance
		# instead of an extreme far point to reduce muzzle/camera parallax drift.
		target = origin + forward * projectile_zero_distance

	var muzzle_origin: Vector3 = _get_weapon_muzzle_position()
	if muzzle_origin.distance_to(target) < min_muzzle_target_distance:
		target = muzzle_origin + forward * min_muzzle_target_distance

	var aim_direction: Vector3 = target - muzzle_origin
	if aim_direction.length_squared() < 0.0001:
		return forward

	aim_direction = aim_direction.normalized()
	if aim_direction.dot(forward) < min_muzzle_forward_dot:
		return forward

	return aim_direction


## Stub for FSE enemy melee; expand with HP if you add a combat resource to the navigator.
func receive_attack(_damage: int) -> void:
	pass
