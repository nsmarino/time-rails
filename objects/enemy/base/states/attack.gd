extends FseAIState

@export var hitbox_start: float = 0.2
@export var hitbox_end: float = 0.5
@export var fallback_duration: float = 0.8

var has_hit_player: bool = false
var animation_finished: bool = false
var attack_animation: StringName = &""


func on_enter() -> void:
	super.on_enter()
	has_hit_player = false
	animation_finished = false

	if animator and enemy_data:
		attack_animation = StringName(enemy_data.anim_attack)
		if not animator.animation_finished.is_connected(_on_animation_finished):
			animator.animation_finished.connect(_on_animation_finished)
		animator.play(String(attack_animation))
	elif animator:
		animation_finished = true

	if attack_area:
		attack_area.monitoring = true

	if player:
		var direction: Vector3 = (player.global_position - character.global_position).normalized()
		direction.y = 0
		if direction.length() > 0.1:
			character.rotation.y = atan2(direction.x, direction.z)


func on_exit() -> void:
	super.on_exit()
	if attack_area:
		attack_area.monitoring = false

	if animator and animator.animation_finished.is_connected(_on_animation_finished):
		animator.animation_finished.disconnect(_on_animation_finished)


func update(_delta: float) -> void:
	stop_with_avoidance()

	if duration_between(hitbox_start, hitbox_end) and not has_hit_player:
		_check_for_hits()


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == attack_animation:
		animation_finished = true


func _check_for_hits() -> void:
	if not attack_area:
		return

	var bodies: Array[Node3D] = attack_area.get_overlapping_bodies()

	for body in bodies:
		if body.is_in_group("player"):
			_on_hit_player(body)
			break


func _on_hit_player(target: Node) -> void:
	has_hit_player = true

	var damage: int = enemy_data.attack_power if enemy_data else 10
	Events.attack_hit.emit(character, target, damage)

	if target.has_method("receive_attack"):
		target.receive_attack(damage)


func check_transition(_delta: float) -> Array:
	if animation_finished:
		return [true, "pursue"]

	if fallback_duration > 0.0 and duration_longer_than(fallback_duration):
		return [true, "pursue"]

	return [false, ""]


func get_attack_duration() -> float:
	return fallback_duration
