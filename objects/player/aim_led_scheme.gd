extends Node
class_name AimLedScheme

## The AIM-LED control scheme (Star Fox 64 / Panzer Dragoon): the reticle is the
## only directly-driven element (right stick + mouse), the ship follows a
## scaled-down copy of it, and the camera reacts to where you're aiming.
##
## This is a swappable child component of the player hub (mecha_player.gd). The
## hub ticks it via update(delta) — the scheme does NOT self-process, because
## its internal order is load-bearing: evade → aim → camera → ship (the ship is
## positioned relative to the banked camera, so the camera must rotate first).
## The hub consumes only the port methods:
##   update(delta), set_active(bool),
##   get_aim_world_point() -> Vector3        (weapon convergence point)
##   get_reticle_screen_position() -> Vector2 (HUD crosshair + homing anchor)
##   is_evading() -> bool                     (fire gate)
##   is_aiming() -> bool
## A different scheme (e.g. a ship-led Star Fox SNES scheme) implements the same
## ports and swaps in without touching the hub, weapons, homing, or the HUD.
##
## The AimTarget node is an implementation detail of THIS scheme (a world-space
## home for the steerable cursor, parented to the camera); the hub resolves it
## from the rig and injects it via setup().

@export_category("Movement")
## Distance in front of the camera where the ship plane sits (its rail depth).
@export var player_plane_distance: float = 10.0
## Fraction of the visible view the ship may roam (1.0 = full screen edges).
@export var move_bounds_scale: float = 0.85

@export_category("Aiming")
## Reticle cursor speed across the aim plane, in world units per second.
@export var aim_speed: float = 18.0
## Distance in front of the camera where the aim plane sits.
@export var aim_plane_distance: float = 30.0
## Fraction of the visible view the reticle may roam (1.0 = full screen edges).
@export var aim_bounds_scale: float = 1.0
## Mouse aim sensitivity (world units of cursor movement per pixel of mouse motion).
@export var mouse_aim_sensitivity: float = 0.06
## How fast the reticle eases back toward center when there's no input
## (per second). 0 = fully persistent (Panzer Dragoon); raise for a Star Fox
## springy return.
@export var recenter_rate: float = 0.0

@export_category("Ship Follow")
## The ship targets the reticle position scaled by this (0..1), so the reticle
## can reach the screen edge while the ship only drifts partway. This is the
## ship's reachable sub-box.
@export var ship_follow_fraction: float = 0.6
## How snappily the ship eases toward its follow target (higher = tighter).
@export var ship_follow_lerp: float = 18.0
## World units the ship sits *below* the reticle so it doesn't occlude the
## target. Fades out as the reticle drops into the lower screen half (otherwise
## aiming down would push the ship off the bottom edge).
@export var ship_below_offset: float = 1.0
## Max cosmetic roll (deg) of the ship mesh as it banks into a horizontal turn.
@export var ship_bank_max_deg: float = 20.0
## Max cosmetic pitch (deg) — the nose tilts up/down toward a vertical aim.
@export var ship_pitch_max_deg: float = 12.0
## Max cosmetic yaw (deg) — the nose turns left/right toward a horizontal aim.
@export var ship_yaw_max_deg: float = 12.0
## How fast the cosmetic ship lean eases toward its target.
@export var ship_visual_lerp: float = 10.0

@export_category("Camera React")
## Max camera roll (bank) in degrees from horizontal aim offset. Subtle by
## default (Star Fox); raise for Panzer Dragoon's dramatic horizon tilt.
@export var camera_roll_max_deg: float = 8.0
## Max camera pitch in degrees from vertical aim offset.
@export var camera_pitch_max_deg: float = 5.0
## Max camera yaw in degrees from horizontal aim offset.
@export var camera_yaw_max_deg: float = 3.0
## How fast the camera reaction eases toward its target angle.
@export var camera_react_lerp: float = 6.0

@export_category("Evade")
## A left/right flick of the LEFT STICK triggers an evade: the ship slides
## laterally to a peak and springs back while spinning a full pirouette about its
## up axis (a "screw" spin, not a screen-plane cartwheel). Firing is
## disabled until it completes; aiming and the camera react keep running. An evade
## always runs to completion — the stick must re-center before another can fire.
## Total duration of one evade (seconds).
@export var evade_duration: float = 0.5
## Peak lateral slide distance (world units on the ship plane).
@export var evade_lateral_distance: float = 4.0
## Number of full barrel rolls performed over the evade.
@export var evade_spins: float = 1.0
## Degrees added to the camera FOV during the evade (pull-back cue); eased out as
## the evade starts and back in as it ends.
@export var evade_fov_pullback: float = 8.0
## Left-stick X magnitude that triggers an evade.
@export var evade_trigger_deadzone: float = 0.5
## The stick X must fall back below this before another evade can trigger (so a
## held stick doesn't re-fire).
@export var evade_rearm_threshold: float = 0.2

# Injected by the hub's setup() — the ship body this scheme drives, the rig
# camera, and the AimTarget node (this scheme's world-space cursor home).
var _body: CharacterBody3D = null
var _camera: Camera3D = null
var _aim_target: Node3D = null

var _active: bool = true

# Cursor positions in camera-local X/Y (their plane depth is applied on use).
# _aim_cursor is directly driven; _ship_cursor follows it.
var _aim_cursor: Vector2 = Vector2.ZERO
var _ship_cursor: Vector2 = Vector2.ZERO

# Eased camera reaction and cosmetic ship lean, both Euler radians
# (pitch=x, yaw=y, roll=z).
var _camera_react: Vector3 = Vector3.ZERO
var _ship_lean: Vector3 = Vector3.ZERO

# Accumulated mouse motion since the last aim integration (cleared per frame).
var _pending_mouse_delta: Vector2 = Vector2.ZERO

# Barrel-roll evade state. _evade_dir is -1 (left) / +1 (right) / 0 (idle); while
# nonzero an evade is running. _evade_t counts up to evade_duration. _evade_armed
# gates re-triggering until the stick re-centers. _evade_frozen_lean is the ship
# lean captured at trigger time — the way OUT preserves it, the way BACK lerps to
# the live lean so the ship ends correctly oriented for the current aim.
var _evade_dir: float = 0.0
var _evade_t: float = 0.0
var _evade_armed: bool = true
var _evade_frozen_lean: Vector3 = Vector3.ZERO
var _base_fov: float = 70.0


## Called by the hub on ready. The scheme owns the AimTarget from here on.
func setup(body: CharacterBody3D, camera: Camera3D, aim_target: Node3D) -> void:
	_body = body
	_camera = camera
	_aim_target = aim_target
	if _camera:
		_base_fov = _camera.fov
	if _aim_target:
		_aim_target.position = Vector3(0.0, 0.0, -aim_plane_distance)


## Lifecycle broadcast (hub calls this on death). This scheme has no visuals of
## its own; deactivating just stops input from accumulating.
func set_active(active: bool) -> void:
	_active = active
	set_process_input(active)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Y is inverted: pushing the mouse up moves the reticle up (which is +Y locally).
		_pending_mouse_delta.x += event.relative.x * mouse_aim_sensitivity
		_pending_mouse_delta.y -= event.relative.y * mouse_aim_sensitivity


## Per-frame tick, driven by the hub. Order is load-bearing: the camera banks
## from the aim (step 3), then the ship positions itself relative to the banked
## camera (step 4).
func update(delta: float) -> void:
	if not _active:
		return
	_update_evade(delta)
	_process_aim(delta)
	_process_camera(delta)
	_process_ship(delta)


#region Ports (consumed by the hub)

func is_aiming() -> bool:
	return _camera != null and _aim_target != null


## True while an evade is running — the hub gates firing on this.
func is_evading() -> bool:
	return _evade_dir != 0.0


## The world point shots converge on: the AimTarget's position.
func get_aim_world_point() -> Vector3:
	if _aim_target:
		return _aim_target.global_position
	if _body:
		return _body.global_position - _body.global_transform.basis.z * aim_plane_distance
	return Vector3.ZERO


## The reticle's screen position — the HUD crosshair and the homing anchor.
func get_reticle_screen_position() -> Vector2:
	if not is_aiming():
		return Vector2.ZERO
	return _camera.unproject_position(_aim_target.global_position)

#endregion


## Edge-triggers a barrel-roll evade on a left/right flick of the left stick and
## advances any active evade timer. An evade always runs to completion (no hold,
## no cancel); the stick must relax below evade_rearm_threshold before another can
## fire. The motion itself (lateral slide + roll) is applied in _process_ship.
func _update_evade(delta: float) -> void:
	var x := Input.get_axis("MoveLeft", "MoveRight")

	if _evade_dir != 0.0:
		_evade_t += delta
		if _evade_t >= evade_duration:
			_evade_dir = 0.0
			_evade_t = 0.0
	elif _evade_armed and absf(x) > evade_trigger_deadzone:
		_evade_dir = signf(x)
		_evade_t = 0.0
		_evade_armed = false
		# Freeze the orientation at trigger time; the way back lerps off this.
		_evade_frozen_lean = _ship_lean

	# Re-arm only once the stick relaxes back toward center.
	if absf(x) < evade_rearm_threshold:
		_evade_armed = true


#region Aiming (the directly-driven element)

func _process_aim(delta: float) -> void:
	if not _aim_target or not _camera:
		return

	var look := Vector2(
		Input.get_axis("LookLeft", "LookRight"),
		Input.get_axis("LookDown", "LookUp")
	)
	if look.length() > 1.0:
		look = look.normalized()

	var moved := look.length_squared() > 0.0001 or _pending_mouse_delta.length_squared() > 0.0001

	# Stick integrates by speed; mouse delta is already in world units.
	_aim_cursor += look * aim_speed * delta
	_aim_cursor += _pending_mouse_delta
	_pending_mouse_delta = Vector2.ZERO

	# Ease back toward center when idle (0 = fully persistent).
	if not moved and recenter_rate > 0.0:
		var t := clampf(recenter_rate * delta, 0.0, 1.0)
		_aim_cursor = _aim_cursor.lerp(Vector2.ZERO, t)

	var aim_extents := _frustum_extents(aim_plane_distance, aim_bounds_scale)
	_aim_cursor.x = clampf(_aim_cursor.x, -aim_extents.x, aim_extents.x)
	_aim_cursor.y = clampf(_aim_cursor.y, -aim_extents.y, aim_extents.y)

	# AimTarget is a child of the camera; its local position is the cursor. Its
	# world position is derived from the camera transform when read, so it tracks
	# the camera bank applied later this frame.
	_aim_target.position = Vector3(_aim_cursor.x, _aim_cursor.y, -aim_plane_distance)

#endregion


#region Camera reaction (reacts to aim)

func _process_camera(delta: float) -> void:
	if not _camera:
		return

	var n := _normalized_aim()
	# Local rotation, so it composes additively on top of any rail orientation
	# the camera's parent (PlayerRoot) may have on curved rails.
	var target := Vector3(
		n.y * deg_to_rad(camera_pitch_max_deg),   # pitch (X): aim up -> look up
		-n.x * deg_to_rad(camera_yaw_max_deg),    # yaw (Y): look toward aim
		-n.x * deg_to_rad(camera_roll_max_deg)    # roll (Z): bank into the turn
	)
	# The camera keeps reacting to aim through an evade (no neutral snap).
	var t := clampf(camera_react_lerp * delta, 0.0, 1.0)
	_camera_react = _camera_react.lerp(target, t)
	_camera.rotation = _camera_react

	# Pull the FOV back slightly during an evade as a "whoa, dodging" cue; eases
	# out as it starts and back to base as it ends.
	var fov_target := _base_fov + (evade_fov_pullback if _evade_dir != 0.0 else 0.0)
	_camera.fov = lerpf(_camera.fov, fov_target, clampf(camera_react_lerp * delta, 0.0, 1.0))

#endregion


#region Ship follow

func _process_ship(delta: float) -> void:
	if not _camera or not _body:
		return

	# Ease toward the reticle's screen position, scaled by ship_follow_fraction.
	# The cursors live on planes at different depths (aim_plane_distance vs.
	# player_plane_distance), so convert by the distance ratio — a cursor value
	# divided by its plane distance is the on-screen angle. Without this the ship
	# overshoots off-screen, since the same value spans a wider angle up close.
	var box := _frustum_extents(player_plane_distance, move_bounds_scale)
	var plane_ratio := player_plane_distance / maxf(aim_plane_distance, 0.001)
	var ship_target := _aim_cursor * plane_ratio * ship_follow_fraction

	# Drop the ship below the reticle so it doesn't occlude the target. The offset
	# is full when the reticle is centered or in the upper half, and fades to zero
	# as the reticle reaches the bottom edge — so aiming down doesn't shove the
	# ship off-screen or re-occlude the target.
	var aim_y := _normalized_aim().y  # +1 top, -1 bottom
	ship_target.y -= ship_below_offset * clampf(remap(aim_y, -1.0, 0.0, 0.0, 1.0), 0.0, 1.0)

	var t := clampf(ship_follow_lerp * delta, 0.0, 1.0)
	_ship_cursor = _ship_cursor.lerp(ship_target, t)

	# Evade progress 0..1 (only meaningful while _evade_dir != 0).
	var is_evade := _evade_dir != 0.0
	var p := clampf(_evade_t / maxf(evade_duration, 0.001), 0.0, 1.0)

	# The ship keeps following the reticle; the evade adds a lateral slide that
	# peaks mid-evade (sin) and returns to zero, so it lands back on the current
	# aim position with no snap.
	var final_cursor := _ship_cursor
	if is_evade:
		final_cursor.x += _evade_dir * evade_lateral_distance * sin(p * PI)
	final_cursor.x = clampf(final_cursor.x, -box.x, box.x)
	final_cursor.y = clampf(final_cursor.y, -box.y, box.y)

	# Cosmetic lean: the nose points toward the reticle (pitch + yaw) and the body
	# banks into a horizontal turn (roll). Keeps easing to live aim even mid-evade.
	var n := _normalized_aim()
	var lean_target := Vector3(
		n.y * deg_to_rad(ship_pitch_max_deg),    # pitch: aim up -> nose up
		-n.x * deg_to_rad(ship_yaw_max_deg),     # yaw: aim right -> nose right
		-n.x * deg_to_rad(ship_bank_max_deg)     # roll: bank into the turn
	)
	var vt := clampf(ship_visual_lerp * delta, 0.0, 1.0)
	_ship_lean = _ship_lean.lerp(lean_target, vt)

	# Base orientation: normally the live lean. During an evade the way OUT (p<=0.5)
	# preserves the lean captured at trigger time; the way BACK lerps to the
	# now-current live lean, so the ship ends correctly oriented with no snap. A
	# full spin about the ship's UP axis (a left/right "screw" pirouette, not a
	# screen-plane cartwheel) is composed on top.
	var base_lean := _ship_lean
	var spin := 0.0
	if is_evade:
		var back_blend := clampf((p - 0.5) / 0.5, 0.0, 1.0)
		base_lean = _evade_frozen_lean.lerp(_ship_lean, back_blend)
		spin = _evade_dir * TAU * evade_spins * p

	# Position the ship on its plane relative to the banked camera; the lean (and
	# any evade spin) is a local rotation composed onto the camera basis.
	var cam_xform := _camera.global_transform
	var lean := Basis.from_euler(base_lean)
	if is_evade:
		lean = lean * Basis(Vector3.UP, spin)
	var offset := Vector3(final_cursor.x, final_cursor.y, -player_plane_distance)
	_body.global_transform = Transform3D(cam_xform.basis * lean, cam_xform * offset)


## Normalized aim cursor, each component in -1..1 (cursor / frustum extent).
func _normalized_aim() -> Vector2:
	var ext := _frustum_extents(aim_plane_distance, aim_bounds_scale)
	return Vector2(
		clampf(_aim_cursor.x / maxf(ext.x, 0.001), -1.0, 1.0),
		clampf(_aim_cursor.y / maxf(ext.y, 0.001), -1.0, 1.0)
	)


## Frustum half-size (width, height) at a plane distance, scaled. Godot's
## Camera3D defaults to KEEP_HEIGHT, so fov is the vertical angle.
func _frustum_extents(distance: float, bounds_scale: float) -> Vector2:
	var fov_rad := deg_to_rad(_camera.fov)
	var half_h := tan(fov_rad * 0.5) * distance
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := 1.0 if viewport_size.y == 0.0 else viewport_size.x / viewport_size.y
	var half_w := half_h * aspect
	return Vector2(half_w, half_h) * bounds_scale

#endregion
