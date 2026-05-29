extends Resource
class_name DialogueConfig

## Configuration resource for dialogue encounters
## Defines the visual appearance and dialogue content

@export_category("Dialogue Content")
@export_file("*.json") var dialogue_json_path: String
@export var prompt_content: String = "Press [A] to talk"

@export_category("Overworld")
@export var overworld_mesh: Mesh


func load_dialogue_nodes() -> Array[Dictionary]:
	if dialogue_json_path.is_empty():
		push_warning("[DialogueConfig] dialogue_json_path is empty.")
		return []
	
	if not FileAccess.file_exists(dialogue_json_path):
		push_error("[DialogueConfig] JSON file not found: %s" % dialogue_json_path)
		return []
	
	var file := FileAccess.open(dialogue_json_path, FileAccess.READ)
	if not file:
		push_error("[DialogueConfig] Unable to open JSON file: %s" % dialogue_json_path)
		return []
	
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		push_error("[DialogueConfig] Expected an array of dialogue nodes in: %s" % dialogue_json_path)
		return []
	
	var nodes: Array[Dictionary] = []
	var parsed_nodes: Array = parsed
	for raw_node: Variant in parsed_nodes:
		if typeof(raw_node) != TYPE_DICTIONARY:
			continue
		
		var normalized_node: Dictionary = {
			"speaker": str(raw_node.get("speaker", "")),
			"portrait": str(raw_node.get("portrait", "")),
			"text_content": str(raw_node.get("text_content", "")),
			"trigger_id": str(raw_node.get("trigger_id", "")),
		}
		nodes.append(normalized_node)
	
	return nodes
