extends BaseStateMachine
class_name FseEnemyStateMachine

## State machine for FSE open-field enemies.

# Alias for backward compatibility - owner_node is the character
var character: CharacterBody3D:
	get:
		return owner_node as CharacterBody3D
	set(value):
		owner_node = value


## Override to collect FseAIState children specifically
func _collect_states() -> void:
	for child in get_children():
		if child is FseAIState:
			states[child.state_name] = child
			# Give state references
			child.state_machine = self
			child.owner_node = owner_node
