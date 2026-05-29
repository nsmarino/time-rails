extends CharacterBody3D

## Mecha pilot controller for the on-rails shooter prototype.
##
## - Left stick / IJKL moves the mecha within a fixed X/Y play box (no gravity).
## - Right stick steers a world-space AimTarget that rides a plane in front of
##   the camera; its travel is clamped to the camera's frustum at that depth.
## - CombatAttack fires the equipped weapon from the muzzle toward the AimTarget.
##
## The on-screen reticle (CombatUI) reads get_reticle_screen_position() each
## frame, so the crosshair and the world aim point can never desync.

@export_category("Movement")
## Movement speed in world units per second.
@export var move_speed: float = 12.0
## Minimum reachable X/Y in world units (the bottom-left of the play box).
@export var move_min: Vector2 = Vector2(-8.0, -6.0)
## Maximum reachable X/Y in world units (the top-right of the play box).
@export var move_max: Vector2 = Vector2(8.0, 6.0)

@export_category("Aiming")
## Reticle travel speed across the aim plane, in world units per second.
@export var aim_speed: float = 18.0
## Distance in front of the camera where the aim plane sits.
@export var aim_plane_distance: float = 30.0
## Scales the usable aim area relative to the full camera view (1.0 = full screen).
@export var aim_bounds_scale: float = 1.0

@export_category("Combat")
## Weapon instantiated and mounted to the WeaponSocket on ready.
@export var default_weapon_scene: PackedScene

@export_category("References")
## Active camera used for aiming/reticle projection. Falls back to the
## viewport's current camera when left empty.
@export var camera_path: NodePath
## World-space aim target node (parenting it to the camera works best). One is
## created under the camera automatically if this is left empty.
@export var aim_target_path: NodePath

@onready var weapon_socket: Node3D = $WeaponSocket

var _camera: Camera3D = null
var _aim_target: Node3D = null
var _equipped_weapon: Node3D = null
var _locked_z: float = 0.0


func _ready() -> void:
	_locked_z = global_position.z
	_resolve_camera()
	_resolve_aim_target()
	_equip_default_weapon()


func _physics_process(delta: float) -> void:
	_process_movement(delta)
	_process_aim(delta)
	_process_combat()


#region Movement

func _process_movement(_delta: float) -> void:
	var input := Vector2(
		Input.get_axis("MoveLeft", "MoveRight"),
		Input.get_axis("MoveDown", "MoveUp")
	)
	if input.length() > 1.0:
		input = input.normalized()

	velocity = Vector3(input.x, input.y, 0.0) * move_speed
	move_and_slide()

	# Hard-clamp to the play box and lock the rail depth.
	var pos := global_position
	pos.x = clampf(pos.x, move_min.x, move_max.x)
	pos.y = clampf(pos.y, move_min.y, move_max.y)
	pos.z = _locked_z
	global_position = pos

#endregion


#region Aiming

func _process_aim(delta: float) -> void:
	if not _aim_target or not _camera:
		return

	var look := Vector2(
		Input.get_axis("LookLeft", "LookRight"),
		Input.get_axis("LookDown", "LookUp")
	)
	if look.length() > 1.0:
		look = look.normalized()

	# AimTarget is parented to the camera, so we steer it in the camera's local
	# space and keep it pinned to the aim plane depth.
	var local := _aim_target.position
	local.z = -aim_plane_distance
	local.x += look.x * aim_speed * delta
	local.y += look.y * aim_speed * delta

	var extents := _get_aim_extents()
	local.x = clampf(local.x, -extents.x, extents.x)
	local.y = clampf(local.y, -extents.y, extents.y)
	_aim_target.position = local


## Frustum half-size (width, height) at the aim plane distance. Godot's
## Camera3D defaults to KEEP_HEIGHT, so fov is the vertical angle.
func _get_aim_extents() -> Vector2:
	var fov_rad := deg_to_rad(_camera.fov)
	var half_h := tan(fov_rad * 0.5) * aim_plane_distance
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := 1.0 if viewport_size.y == 0.0 else viewport_size.x / viewport_size.y
	var half_w := half_h * aspect
	return Vector2(half_w, half_h) * aim_bounds_scale

#endregion


#region Combat

func _process_combat() -> void:
	if not _equipped_weapon:
		return

	var pressed := Input.is_action_pressed("CombatAttack")
	var just := Input.is_action_just_pressed("CombatAttack")
	var wants_fire := pressed
	if _equipped_weapon.has_method("should_fire_for_input"):
		wants_fire = bool(_equipped_weapon.call("should_fire_for_input", pressed, just))

	if wants_fire:
		_equipped_weapon.try_fire(_get_aim_direction())


func _get_aim_direction() -> Vector3:
	if not _aim_target:
		return -global_transform.basis.z

	var muzzle := _get_muzzle_position()
	var dir := _aim_target.global_position - muzzle
	if dir.length_squared() < 0.0001:
		return -global_transform.basis.z
	return dir.normalized()


func _get_muzzle_position() -> Vector3:
	if _equipped_weapon and _equipped_weapon.has_node("Muzzle"):
		var m: Node = _equipped_weapon.get_node("Muzzle")
		if m is Node3D:
			return (m as Node3D).global_position
	if weapon_socket:
		return weapon_socket.global_position
	return global_position

#endregion


#region Reticle hookup (read by CombatUI)

func is_aiming() -> bool:
	return _camera != null and _aim_target != null


func get_reticle_screen_position() -> Vector2:
	if not is_aiming():
		return Vector2.ZERO
	return _camera.unproject_position(_aim_target.global_position)

#endregion


#region Setup helpers

func _resolve_camera() -> void:
	if camera_path != NodePath() and has_node(camera_path):
		var node: Node = get_node(camera_path)
		if node is Camera3D:
			_camera = node as Camera3D
	if not _camera:
		_camera = get_viewport().get_camera_3d()
	if not _camera:
		push_error("[MechaPlayer] No camera found for aiming.")


func _resolve_aim_target() -> void:
	if aim_target_path != NodePath() and has_node(aim_target_path):
		var node: Node = get_node(aim_target_path)
		if node is Node3D:
			_aim_target = node as Node3D
	if not _aim_target and _camera:
		var t := Node3D.new()
		t.name = "AimTarget"
		_camera.add_child(t)
		_aim_target = t
	if _aim_target:
		_aim_target.position.z = -aim_plane_distance


func _equip_default_weapon() -> void:
	if not default_weapon_scene:
		push_warning("[MechaPlayer] No default_weapon_scene assigned.")
		return
	if not weapon_socket:
		push_error("[MechaPlayer] WeaponSocket node missing.")
		return

	var inst: Node = default_weapon_scene.instantiate()
	if not (inst is Node3D) or not inst.has_method("try_fire"):
		push_error("[MechaPlayer] default_weapon_scene must be a Node3D exposing try_fire().")
		if inst:
			inst.queue_free()
		return

	_equipped_weapon = inst as Node3D
	weapon_socket.add_child(_equipped_weapon)
	if "owner_character" in _equipped_weapon:
		_equipped_weapon.owner_character = self

#endregion
