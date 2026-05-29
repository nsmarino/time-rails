extends CharacterBody3D
class_name FseEnemy

signal died

@export var enemy_data: FseEnemyData

@onready var state_machine: Node = $StateMachine
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var attack_area: Area3D = $AttackArea
@onready var damage_sfx: AudioStreamPlayer3D = get_node_or_null("SFX/Damage") as AudioStreamPlayer3D
@onready var death_sfx: AudioStreamPlayer3D = get_node_or_null("SFX/Death") as AudioStreamPlayer3D

var spawn_point: Vector3
var character_instance: Node3D
var animator: AnimationPlayer

var hp: int = 0
var max_hp: int = 0


func _ready() -> void:
	add_to_group("enemy")
	spawn_point = global_position

	if enemy_data:
		max_hp = enemy_data.max_hp
		hp = max_hp

	if nav_agent:
		nav_agent.velocity_computed.connect(_on_velocity_computed)
		nav_agent.use_3d_avoidance = false
		nav_agent.keep_y_velocity = false

	if enemy_data and enemy_data.character_scene:
		_spawn_character_mesh()
	else:
		push_warning("[FseEnemy:%s] No character_scene in enemy_data" % name)

	var player_body: CharacterBody3D = _resolve_player()
	_setup_state_machine(player_body)

	if OS.is_debug_build():
		await get_tree().process_frame
		_debug_navigation_once()


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	safe_velocity.y = 0.0
	velocity = safe_velocity
	move_and_slide()


func _debug_navigation_once() -> void:
	if not nav_agent:
		return
	var nav_map: RID = nav_agent.get_navigation_map()
	if not nav_map.is_valid():
		push_warning("[FseEnemy:%s] Navigation map invalid" % name)
		return
	if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		push_warning("[FseEnemy:%s] Navigation map not synced yet" % name)


func _spawn_character_mesh() -> void:
	character_instance = enemy_data.character_scene.instantiate()
	add_child(character_instance)
	animator = _find_animation_player(character_instance)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found:
			return found
	return null


func _resolve_player() -> CharacterBody3D:
	var node: Node = get_tree().get_first_node_in_group("player")
	if node is CharacterBody3D:
		return node as CharacterBody3D
	push_warning("[FseEnemy:%s] No CharacterBody3D in global group \"player\"" % name)
	return null


func _setup_state_machine(player_body: CharacterBody3D) -> void:
	if not state_machine:
		return
	for child in state_machine.get_children():
		if child is FseAIState:
			var st: FseAIState = child as FseAIState
			st.character = self
			st.player = player_body
			st.spawn_point = spawn_point
			st.animator = animator
			st.nav_agent = nav_agent
			st.attack_area = attack_area
			st.enemy_data = enemy_data


func command_state(state_name: String) -> void:
	if state_machine and state_machine.has_method("switch_to"):
		state_machine.switch_to(state_name)


func get_current_state_name() -> String:
	if state_machine and state_machine.has_method("get_current_state_name"):
		return state_machine.get_current_state_name()
	return ""


func take_damage(amount: int) -> void:
	if hp <= 0:
		print("[FseEnemy:%s] Ignored %d damage because enemy is already defeated." % [name, amount])
		return
	var previous_hp: int = hp
	hp = maxi(0, hp - amount)
	print("[FseEnemy:%s] Took %d damage. HP: %d/%d -> %d/%d" % [name, amount, previous_hp, max_hp, hp, max_hp])
	_play_sfx(damage_sfx)
	Events.enemy_damaged.emit(amount)
	Events.enemy_hp_changed.emit(hp, max_hp)
	if hp <= 0 and state_machine and state_machine.has_method("switch_to"):
		if not state_machine.is_in_state("death"):
			print("[FseEnemy:%s] HP depleted; switching to death state." % name)
			_play_sfx(death_sfx)
			state_machine.switch_to("death")


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)
	Events.enemy_hp_changed.emit(hp, max_hp)


func reset_hp() -> void:
	if enemy_data:
		max_hp = enemy_data.max_hp
	hp = max_hp
	Events.enemy_hp_changed.emit(hp, max_hp)


func is_defeated() -> bool:
	return hp <= 0


func notify_died() -> void:
	died.emit()


func _play_sfx(player: AudioStreamPlayer3D) -> void:
	if not player:
		return

	player.stop()
	player.play()


## Instantiate up to [param count] enemies at shuffled [Marker3D] children under [param markers_root].
static func spawn_from_markers(
	parent: Node,
	markers_root: Node,
	enemy_scene: PackedScene,
	data: FseEnemyData,
	count: int
) -> Array[FseEnemy]:
	var result: Array[FseEnemy] = []
	if not markers_root or not enemy_scene or not parent:
		return result

	var markers: Array[Marker3D] = []
	for child in markers_root.get_children():
		if child is Marker3D:
			markers.append(child as Marker3D)

	markers.shuffle()
	var spawn_count: int = mini(count, markers.size())

	for i in spawn_count:
		var inst: Node = enemy_scene.instantiate()
		if not inst is FseEnemy:
			push_error("[FseEnemy] enemy_scene root must be FseEnemy")
			continue
		var enemy: FseEnemy = inst as FseEnemy
		if data:
			enemy.enemy_data = data
		parent.add_child(enemy)
		var m: Marker3D = markers[i]
		enemy.global_position = m.global_position
		enemy.spawn_point = enemy.global_position
		enemy._sync_state_spawn_points()
		enemy.velocity = Vector3.ZERO
		if enemy.nav_agent:
			enemy.nav_agent.set_velocity_forced(Vector3.ZERO)
		result.append(enemy)

	return result


func _sync_state_spawn_points() -> void:
	if not state_machine:
		return
	for child in state_machine.get_children():
		if child is FseAIState:
			(child as FseAIState).spawn_point = spawn_point


static func get_closest_to(position: Vector3, tree: SceneTree) -> FseEnemy:
	var closest: FseEnemy = null
	var best: float = INF
	for node in tree.get_nodes_in_group("enemy"):
		if not node is FseEnemy:
			continue
		var e: FseEnemy = node as FseEnemy
		var d: float = e.global_position.distance_squared_to(position)
		if d < best:
			best = d
			closest = e
	return closest


static func command_all(state_name: String, tree: SceneTree) -> void:
	for node in tree.get_nodes_in_group("enemy"):
		if node is FseEnemy:
			(node as FseEnemy).command_state(state_name)
