extends CharacterBody3D

## Mecha player HUB. Owns the scheme-independent identity of the player —
## HP/damage/death, the weapon mount and firing loop, homing acquisition, the
## rail-coupled bob, and mouse-capture policy — and delegates "how does the
## ship move & where does it aim" to a swappable CONTROL SCHEME child (e.g.
## AimLedScheme). The hub ticks the scheme each physics frame (schemes don't
## self-process — their internal update order is load-bearing) and consumes
## only its ports:
##   update(delta), set_active(bool),
##   get_aim_world_point() -> Vector3        (weapon convergence point)
##   get_reticle_screen_position() -> Vector2 (HUD crosshair + homing anchor)
##   is_evading() -> bool                     (fire gate)
##   is_aiming() -> bool
## Swapping schemes (e.g. for a ship-led Star Fox SNES model) touches only the
## scheme child — weapons, homing, HUD, and damage flow stay identical.
##
## Movement/aim/camera/evade tuning lives on the scheme node's Inspector, not
## here. The scheme is referenced duck-typed (Node + .call()) to dodge the
## class_name-registration lag noted in CLAUDE.md.
##
## Input map: gamepad and keyboard/trackpad share one action set —
##   - Gamepad: left stick L/R flicks the evade; aim is the right stick.
##   - Keyboard/trackpad: aim is mouse/trackpad motion (captured; Escape toggles),
##     J/L flick the evade, Space fires, K toggles the brake.

@export_category("Combat")
## Weapon instantiated and mounted to the WeaponSocket on ready.
@export var default_weapon_scene: PackedScene
## Player hit points.
@export var max_hp: int = 100
## Lock-on radius around the reticle, as a fraction of screen height. A target
## must project within this many pixels of the crosshair to be homing-eligible;
## if nothing is inside it, shots fly straight (no distant lock). Small = tight,
## crosshair-accurate homing.
@export var homing_screen_radius: float = 0.12
## Max world distance a target can be to be eligible for homing lock-on.
@export var homing_max_range: float = 120.0

@export_category("Bob")
## The ship mesh gently floats up/down at all times — a subtle sway in flight
## that deepens into the idle hover while braked. Set move_bob_amplitude to 0
## to restore the old braked-only bob.
## Vertical amplitude (world units) while flying — subtler than the braked hover.
@export var move_bob_amplitude: float = 0.05
## Bob oscillation speed while flying (radians/sec).
@export var move_bob_speed: float = 2.5
## Vertical amplitude (world units) while braked (rail stopped).
@export var brake_bob_amplitude: float = 0.15
## Bob oscillation speed while braked (radians/sec).
@export var brake_bob_speed: float = 2.5
## How fast the bob crossfades between the moving and braked settings.
@export var brake_bob_ease: float = 3.0

@export_category("Input")
## Capture the mouse on ready; Escape toggles release. Capture policy is a hub
## concern — any scheme may read the mouse while captured.
@export var capture_mouse_on_ready: bool = true

@export_category("References")
## Active camera for the rig. Falls back to the viewport's current camera when
## left empty. Resolved here and injected into the scheme.
@export var camera_path: NodePath
## World-space aim target node used by the aim-led scheme (parenting it to the
## camera works best). One is created under the camera automatically if this is
## left empty. Injected into the scheme; ship-led schemes ignore it.
@export var aim_target_path: NodePath
## PathFollow3D running rail_follower.gd, read for its `braked` flag (drives the
## idle bob). Empty = the nearest PathFollow3D ancestor.
@export var rail_follower_path: NodePath

@onready var weapon_socket: Node3D = $WeaponSocket

var hp: int = 0

var _camera: Camera3D = null
var _aim_target: Node3D = null
var _equipped_weapon: Node3D = null
# The currently locked homing target (null = none). Read by CombatUI to place
# the lock-on indicator.
var _homing_target: Node3D = null

# The active control scheme child. Duck-typed (Node + .call()) so this script
# doesn't depend on the scheme's class_name being registered.
var _scheme: Node = null

# Hit-react (flash + shake) is delegated to a HitReactComponent child; the player
# feeds its brake bob in through that component's extra_offset. Duck-typed (Node)
# so this script doesn't depend on the component's class_name being registered.
var _hit_react: Node = null

# The mecha mesh, hidden on death so only the death burst remains on screen.
var _mecha_frame: Node3D = null
# True once the player has died — halts per-frame processing (scheme/combat/bob)
# so the wreck stops steering and firing.
var _dead: bool = false

# Idle-bob state. _bob_blend crossfades 0 (moving settings) -> 1 (braked
# settings) as the rail brakes/resumes; _bob_phase is the running sine phase.
# _rail_follower is read for its `braked` flag.
var _rail_follower: Node = null
var _bob_phase: float = 0.0
var _bob_blend: float = 0.0


func _ready() -> void:
	hp = max_hp
	_resolve_camera()
	_resolve_aim_target()
	_equip_default_weapon()
	_hit_react = get_node_or_null("HitReactComponent")
	_mecha_frame = get_node_or_null("mecha-frame")
	_resolve_rail_follower()
	_resolve_scheme()
	if capture_mouse_on_ready:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	# Once dead the wreck stops steering, aiming, firing, and bobbing.
	if _dead:
		return
	if _scheme:
		_scheme.call("update", delta)
	_process_combat()
	_update_bob(delta)


#region Combat

func _process_combat() -> void:
	if not _equipped_weapon:
		return

	# Refresh the homing lock every frame so non-locked shots fly straight. Aim
	# and lock-on keep updating during an evade — only firing is gated below.
	_homing_target = _acquire_homing_target()
	if "homing_target" in _equipped_weapon:
		_equipped_weapon.homing_target = _homing_target

	# No shooting while evading.
	if is_evading():
		return

	var pressed := Input.is_action_pressed("CombatAttack")
	var just := Input.is_action_just_pressed("CombatAttack")
	var wants_fire := pressed
	if _equipped_weapon.has_method("should_fire_for_input"):
		wants_fire = bool(_equipped_weapon.call("should_fire_for_input", pressed, just))

	if wants_fire:
		_equipped_weapon.try_fire(_get_aim_direction())


## Pick the homing-eligible target whose screen position is nearest the reticle,
## within a tight screen-space radius and within range. Returns null when nothing
## qualifies — shots then fly straight, so there's no distant snap lock-on.
##
## Iterates the "destructible" group (enemies, shootable obstacles, turret-bolts)
## and honors each target's homing_eligible flag, so props opt out cleanly.
func _acquire_homing_target() -> Node3D:
	if not _camera or not _scheme:
		return null

	var reticle_screen: Vector2 = get_reticle_screen_position()
	var cam_origin: Vector3 = _camera.global_position
	var radius_px: float = homing_screen_radius * get_viewport().get_visible_rect().size.y

	var best: Node3D = null
	var best_screen_dist: float = radius_px  # only targets inside the radius qualify

	for node in get_tree().get_nodes_in_group("destructible"):
		var target := node as Node3D
		if not target:
			continue
		if "homing_eligible" in target and not target.homing_eligible:
			continue
		if target.has_method("is_defeated") and target.is_defeated():
			continue

		var dist: float = cam_origin.distance_to(target.global_position)
		if dist > homing_max_range or dist < 0.01:
			continue
		if _camera.is_position_behind(target.global_position):
			continue

		# Nearest to the crosshair on screen, and must be inside the lock radius.
		var screen_dist: float = reticle_screen.distance_to(_camera.unproject_position(target.global_position))
		if screen_dist < best_screen_dist:
			best_screen_dist = screen_dist
			best = target

	return best


## Fire direction: from the muzzle toward the scheme's aim world point, so shots
## converge on the reticle / nose point regardless of the muzzle offset.
func _get_aim_direction() -> Vector3:
	if not _scheme:
		return -global_transform.basis.z

	var muzzle := _get_muzzle_position()
	var aim_point: Vector3 = _scheme.call("get_aim_world_point")
	var dir := aim_point - muzzle
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


## Damage entry point used by enemy projectiles (body group "player") and contact.
func receive_attack(amount: int) -> void:
	take_damage(amount)


func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	var prev: int = hp
	hp = maxi(0, hp - amount)
	print("[Player] Took %d damage. HP: %d -> %d / %d" % [amount, prev, hp, max_hp])
	if _hit_react:
		_hit_react.call("trigger")
	if hp <= 0:
		_die()


## Death sequence: play the death burst, hide the mech so only the burst is left,
## deactivate the scheme, and halt the rail. The game-over reset itself is driven
## by main.gd off the player_killed signal (after its own delay), leaving room
## for a death screen.
func _die() -> void:
	if _dead:
		return
	_dead = true
	print("[Player] Destroyed!")
	if _hit_react:
		_hit_react.call("trigger_death")
	# Hide the mech so only the death burst remains on screen; the scheme hides
	# any visuals it owns via set_active(false).
	if _mecha_frame:
		_mecha_frame.visible = false
	if _scheme:
		_scheme.call("set_active", false)
	# Stop the rig advancing along the rail.
	if _rail_follower and "braked" in _rail_follower:
		_rail_follower.braked = true
	if Events:
		Events.player_killed.emit()


## Compute the idle bob (a constant vertical float — subtle in flight, deeper
## while braked) and feed it to the hit-react component as extra_offset — the
## component composes it with the shake into one mesh position write. Mesh-only,
## so the camera/reticle don't bob with it. Amplitude and speed crossfade
## between the move and brake settings via _bob_blend; the phase runs
## continuously so the transition never pops.
func _update_bob(delta: float) -> void:
	var brake_target := 1.0 if _is_braked() else 0.0
	_bob_blend = lerpf(_bob_blend, brake_target, clampf(brake_bob_ease * delta, 0.0, 1.0))
	_bob_phase += lerpf(move_bob_speed, brake_bob_speed, _bob_blend) * delta
	var bob_y := sin(_bob_phase) * lerpf(move_bob_amplitude, brake_bob_amplitude, _bob_blend)
	if _hit_react:
		_hit_react.set("extra_offset", Vector3(0.0, bob_y, 0.0))

#endregion


#region Scheme ports (read by CombatUI / weapons; delegate to the active scheme)

func is_aiming() -> bool:
	return _scheme != null and bool(_scheme.call("is_aiming"))


## True while an evade is running. CombatUI reads this only as a fire-gate
## (the reticle stays visible — aiming continues through the evade).
func is_evading() -> bool:
	return _scheme != null and bool(_scheme.call("is_evading"))


func get_reticle_screen_position() -> Vector2:
	if not _scheme:
		return Vector2.ZERO
	return _scheme.call("get_reticle_screen_position") as Vector2


## The currently locked homing target, or null. CombatUI reads this to show the
## lock-on indicator at the target's screen position.
func get_homing_target() -> Node3D:
	if _homing_target and is_instance_valid(_homing_target):
		return _homing_target
	return null


## Screen position + camera distance of the locked target, for the lock-on
## indicator. Returns {"pos": Vector2, "dist": float} or an empty dict when there
## is no lock / it's behind the camera.
func get_homing_target_screen_info() -> Dictionary:
	var t := get_homing_target()
	if not t or not _camera:
		return {}
	if _camera.is_position_behind(t.global_position):
		return {}
	return {
		"pos": _camera.unproject_position(t.global_position),
		"dist": _camera.global_position.distance_to(t.global_position),
	}

#endregion


#region Setup helpers

## Find the control scheme child (first child exposing the scheme ports) and
## inject the rig references into it.
func _resolve_scheme() -> void:
	for child in get_children():
		if child.has_method("update") and child.has_method("get_aim_world_point"):
			_scheme = child
			break
	if not _scheme:
		push_error("[MechaPlayer] No control scheme child found (e.g. AimLedScheme).")
		return
	if _scheme.has_method("setup"):
		_scheme.call("setup", self, _camera, _aim_target)


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


## Cache the rail follower (PathFollow3D running rail_follower.gd) whose `braked`
## flag drives the idle bob. Falls back to the nearest PathFollow3D ancestor.
func _resolve_rail_follower() -> void:
	if rail_follower_path != NodePath() and has_node(rail_follower_path):
		_rail_follower = get_node(rail_follower_path)
		return
	var n: Node = get_parent()
	while n:
		if n is PathFollow3D:
			_rail_follower = n
			return
		n = n.get_parent()


func _is_braked() -> bool:
	return _rail_follower != null and "braked" in _rail_follower and _rail_follower.braked


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
