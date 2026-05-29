extends Node

enum Phase {
	START,
	PLAY,
	END,
}

# Game signals
signal helicopter_destroyed(loc: Vector3)
signal player_killed
signal phase_changed(phase: Phase)

# Open-field enemy / hit feedback (FSE)
signal enemy_hp_changed(current: int, max_val: int)
signal enemy_damaged(amount: int)
signal attack_hit(attacker: Node, target: Node, damage: int)
signal enemy_state_changed(enemy: Node, new_state: String)

# Overworld dialogue
signal dialogue_prompt_requested(content: String)
signal dialogue_prompt_cleared
signal dialogue_started(dialogue_config: DialogueConfig)
signal dialogue_trigger_fired(trigger_id: String)
signal dialogue_ended

var active_dialogue_trigger: Node = null
var is_dialogue_active: bool = false


func _ready() -> void:
	print("Init autoload events")


func request_dialogue_prompt(trigger: Node, content: String) -> void:
	if is_dialogue_active:
		return
	active_dialogue_trigger = trigger
	dialogue_prompt_requested.emit(content)


func clear_dialogue_prompt(trigger: Node) -> void:
	if active_dialogue_trigger != trigger:
		return
	active_dialogue_trigger = null
	dialogue_prompt_cleared.emit()


func can_start_dialogue(trigger: Node) -> bool:
	return not is_dialogue_active and active_dialogue_trigger == trigger


func begin_dialogue(trigger: Node, dialogue_config: DialogueConfig) -> bool:
	if not can_start_dialogue(trigger):
		return false
	if not dialogue_config:
		return false

	is_dialogue_active = true
	active_dialogue_trigger = trigger
	dialogue_prompt_cleared.emit()
	dialogue_started.emit(dialogue_config)
	return true


func emit_dialogue_trigger(trigger_id: String) -> void:
	if trigger_id.is_empty():
		return
	dialogue_trigger_fired.emit(trigger_id)


func end_dialogue(trigger: Node = null) -> void:
	if trigger and active_dialogue_trigger != trigger:
		return

	is_dialogue_active = false
	active_dialogue_trigger = null
	dialogue_ended.emit()
