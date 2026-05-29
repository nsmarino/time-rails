extends FseAIState

@export var idle_seconds_before_wander: float = 2.0

var _idle_timer: float = 0.0


func on_enter() -> void:
	super.on_enter()
	_idle_timer = 0.0
	if animator and enemy_data:
		animator.play(enemy_data.anim_idle)


func update(_delta: float) -> void:
	stop_with_avoidance()
	_idle_timer += _delta


func check_transition(_delta: float) -> Array:
	if not player:
		return [false, ""]

	#var pursue_range: float = enemy_data.pursue_range if enemy_data else 15.0
	#if get_distance_to_player() <= pursue_range:
		#return [true, "pursue"]
#
	#if idle_seconds_before_wander > 0.0 and _idle_timer >= idle_seconds_before_wander:
		#return [true, "wander"]

	return [false, ""]
