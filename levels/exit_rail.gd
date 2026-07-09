@tool
class_name FseExitRail
extends "res://addons/nurbs_path/nurbs_path_3d.gd"

## An exit route off the main rail loop, owned by a DoorObstacle — assign this
## rail to the door's `exit_rail` in the Inspector (same pattern as its
## key_blasts). When the door opens it calls activate(); the rail then watches
## the player rig and, as the rig comes around and crosses this rail's start
## (control point 0), captures the rig's PathFollow3D onto itself. When the rig
## reaches the rail's end it announces completion on the Events bus
## (exit_rail_completed) — the level (main.gd) runs its victory sequence off
## that.
##
## Author the route with the standard NurbsPath3D control-point gizmo. Place
## control point 0 on (or very near) the main loop so the handoff is seamless;
## the residual snap is absorbed by the rig's PlayerRoot and eased out.
##
## Extends the NurbsPath3D script by path (not class_name) to dodge the global
## class-cache lag noted in CLAUDE.md.

## The rig has been captured onto this rail.
signal captured
## The rig reached the end of this rail.
signal completed

## Once active, the capture arms when the rig comes within this distance of the
## rail's start point. Keep it a touch larger than the gap between the loop's
## progress-0 point and this rail's control point 0 (~28u on the current rail).
@export var arm_radius: float = 35.0
## Seconds the rig's PlayerRoot eases back to center after the capture snap, so
## any residual misalignment between the rails reads as a small glide.
@export var capture_smooth_time: float = 0.4

var _active: bool = false
var _armed: bool = false
var _captured: bool = false
var _completed: bool = false
var _follower: PathFollow3D = null


func _ready() -> void:
	super._ready()
	# Idle until a door activates us (never in the editor).
	set_physics_process(false)


## Called by the owning DoorObstacle when it opens. From here on the rail
## watches for the rig to come around to its start.
func activate() -> void:
	if _active or Engine.is_editor_hint():
		return
	_active = true
	set_physics_process(true)
	print("[ExitRail:%s] Active — will capture the rig at the rail start." % name)


func _physics_process(_delta: float) -> void:
	if _completed:
		set_physics_process(false)
		return

	# After capture, only watch for the end of the rail.
	if _captured:
		if _follower and _follower.progress_ratio >= 1.0:
			_completed = true
			print("[ExitRail:%s] Rig reached the rail end." % name)
			completed.emit()
			if Events:
				Events.exit_rail_completed.emit(self)
		return

	if not _follower:
		_follower = _resolve_follower()
		if not _follower:
			return

	# Arm when the rig nears the rail's start point, then capture the moment it
	# actually crosses it (its closest-offset along the curve turns positive).
	# The arm gate matters because an exit route may overlap the loop further
	# along (this one shares the loop's opening straight) — without it, a door
	# opening mid-overlap would capture immediately instead of at the start.
	if curve.point_count == 0:
		return
	var start_point: Vector3 = to_global(curve.get_point_position(0))
	if not _armed:
		if _follower.global_position.distance_to(start_point) <= arm_radius:
			_armed = true
			print("[ExitRail:%s] Armed — rig approaching the rail start." % name)
		return

	var offset: float = curve.get_closest_offset(to_local(_follower.global_position))
	if offset > 0.5:
		_capture(offset)


## Reparent the rig's PathFollow3D onto this rail at the matching offset.
## PlayerRoot absorbs the residual position snap and eases back to center.
func _capture(offset: float) -> void:
	_captured = true
	var before: Vector3 = _follower.global_position
	_follower.reparent(self)
	_follower.loop = false  # this rail ends; progress_ratio must reach 1
	_follower.progress = offset

	var player_root: Node3D = _follower.get_node_or_null("PlayerRoot") as Node3D
	if player_root:
		player_root.position = _follower.to_local(before)
		var tween: Tween = create_tween()
		tween.tween_property(player_root, "position", Vector3.ZERO, capture_smooth_time)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	print("[ExitRail:%s] Captured the rig at offset %.1f." % [name, offset])
	captured.emit()
	if Events:
		Events.exit_rail_captured.emit(self)


## The rig's PathFollow3D: the nearest PathFollow3D ancestor of the player.
func _resolve_follower() -> PathFollow3D:
	var n: Node = get_tree().get_first_node_in_group("player")
	while n:
		if n is PathFollow3D:
			return n
		n = n.get_parent()
	return null
