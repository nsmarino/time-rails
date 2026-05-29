extends Node

## Holds scene references for overworld systems (navigator, level roots).

var navigator: CharacterBody3D = null
var overworld_root: Node = null
var overworld_lighting: Node = null


func _ready() -> void:
	print("[GameManager] Initialized")


func register_navigator(nav: CharacterBody3D) -> void:
	navigator = nav
	print("[GameManager] Navigator registered: %s" % nav.name)


func register_overworld(overworld: Node) -> void:
	overworld_root = overworld
	print("[GameManager] Overworld registered: %s" % overworld.name)
