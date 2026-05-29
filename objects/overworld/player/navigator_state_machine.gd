extends BaseStateMachine

## State machine for overworld Navigator character
## Manages Idle / Locomotion animation states based on movement

const DEBUG_NAVIGATOR_STATES := true


func _init() -> void:
	default_state = "idle"


func _collect_states() -> void:
	super._collect_states()
	var animator_node: AnimationPlayer = _get_animator()
	if DEBUG_NAVIGATOR_STATES:
		print("[NavigatorStateMachine] Collected %d states: %s" % [states.size(), states.keys()])
		print("[NavigatorStateMachine] owner_node=%s, animator=%s" % [owner_node, animator_node != null])
	for state: BaseAIState in states.values():
		if "animator" in state:
			state.animator = animator_node
			if DEBUG_NAVIGATOR_STATES:
				print("[NavigatorStateMachine] Set animator for state '%s'" % state.state_name)


func _get_animator() -> AnimationPlayer:
	if not owner_node:
		if DEBUG_NAVIGATOR_STATES:
			print("[NavigatorStateMachine] _get_animator: owner_node is null")
		return null
	var elena: Node = owner_node.get_node_or_null("elena")
	if not elena:
		if DEBUG_NAVIGATOR_STATES:
			print("[NavigatorStateMachine] _get_animator: elena node not found under owner")
		return null
	var ap: AnimationPlayer = elena.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if DEBUG_NAVIGATOR_STATES and ap:
		print("[NavigatorStateMachine] _get_animator: found AnimationPlayer with %d animations: %s" % [ap.get_animation_list().size(), ap.get_animation_list()])
	return ap


func switch_to(next_state_name: String) -> void:
	if DEBUG_NAVIGATOR_STATES and not Engine.is_editor_hint():
		print("[NavigatorStateMachine] switch_to: %s -> %s" % [get_current_state_name(), next_state_name])
	super.switch_to(next_state_name)
