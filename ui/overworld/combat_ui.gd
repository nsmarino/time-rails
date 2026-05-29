extends CanvasLayer

@onready var crosshair: Control = $Crosshair

var _player: Node = null

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")


func _process(_delta: float) -> void:
	pass
