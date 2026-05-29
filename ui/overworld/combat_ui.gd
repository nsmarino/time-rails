extends CanvasLayer

@onready var crosshair: Control = $Crosshair

var _player: Node = null


func _ready() -> void:
	crosshair.visible = false
	_player = get_tree().get_first_node_in_group("player")


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		crosshair.visible = false
		return

	if not _player.has_method("is_ads_active"):
		crosshair.visible = false
		return

	crosshair.visible = bool(_player.call("is_ads_active"))
