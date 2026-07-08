extends FseObstacle
class_name DoorObstacle

## A blast door that blocks the rail and kills the player on contact (100 dmg by
## default via the inherited ContactDamage) UNLESS it has been opened.
##
## It opens when its "keyBlast" enemies — assigned per-instance in the Inspector —
## have been destroyed. The intended level pattern: place a DoorObstacle at an
## interval along the rail with a cluster of KeyBlasts before it; the player must
## shoot the keys to open the door, or slam into it and die.
##
## The door is INDESTRUCTIBLE (is_destructible = false, set in the scene) — you
## cannot shoot the door itself open; only destroying its keys works. On open the
## two panels slide apart and the ContactDamage is switched off so the player
## passes through unharmed.

## The keyBlast enemies whose destruction opens this door. Drag the instances in
## from the scene tree. The door listens to each one's `died` signal.
@export var key_blasts: Array[Node] = []
## How many of the assigned keyBlasts must be destroyed before the door opens.
## If this is 0, OR no keyBlasts are assigned, the door instead AUTO-OPENS when
## the player comes within auto_open_distance — handy for tutorial stages and
## cinematic doors that should just open as you approach.
@export var keys_required: int = 0
## Auto-opening doors (see keys_required) trigger when the player is within this
## many world units.
@export var auto_open_distance: float = 20.0
## Seconds the open (panel-slide) animation takes.
@export var open_duration: float = 0.8
## World units each panel slides outward (to its own side) when opening.
@export var panel_slide_distance: float = 3.0

@onready var _left_panel: Node3D = get_node_or_null("LeftPanel")
@onready var _right_panel: Node3D = get_node_or_null("RightPanel")
@onready var _contact: Node = get_node_or_null("ContactDamage")

var _keys_destroyed: int = 0
var _opened: bool = false


func _ready() -> void:
	super._ready()
	if _auto_opens():
		print("[Door:%s] Armed — auto-opens within %.0fu." % [name, auto_open_distance])
		return
	for key in key_blasts:
		if key and key.has_signal("died"):
			key.died.connect(_on_key_destroyed)
	print("[Door:%s] Armed — opens after %d keys destroyed." % [name, keys_required])


## True when the door ignores keys and opens on player proximity instead — no
## keys required (keys_required <= 0) or none assigned.
func _auto_opens() -> bool:
	return keys_required <= 0 or key_blasts.is_empty()


## Auto-opening doors watch for the player getting close (key-gated doors don't
## need this — they open off the keys' `died` signals).
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _opened or state != State.ACTIVE or not _auto_opens():
		return
	if _player and global_position.distance_to(_player.global_position) <= auto_open_distance:
		_open()


func _on_key_destroyed() -> void:
	_keys_destroyed += 1
	if not _opened and _keys_destroyed >= keys_required:
		_open()


## Slide the panels apart and disable contact damage so the player can pass.
func _open() -> void:
	if _opened:
		return
	_opened = true
	print("[Door:%s] Opening." % name)

	# Switch off the damage/collision area — the player now passes through freely.
	if _contact and _contact.has_method("set_active"):
		_contact.set_active(false)

	var tween := create_tween().set_parallel(true)
	if _left_panel:
		tween.tween_property(_left_panel, "position:x",
			_left_panel.position.x - panel_slide_distance, open_duration)
	if _right_panel:
		tween.tween_property(_right_panel, "position:x",
			_right_panel.position.x + panel_slide_distance, open_duration)
