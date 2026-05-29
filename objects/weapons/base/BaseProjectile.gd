extends Node3D
class_name FseBaseProjectile

@export var speed: float = 60.0
@export var damage: float = 10.0
@export var life_time: float = 2.0
@export var group_to_damage: StringName = &"enemy"

@onready var collider: Area3D = $Area3D

var _direction: Vector3 = Vector3.FORWARD
var _shooter: Node = null


func _ready() -> void:
	get_tree().create_timer(life_time).timeout.connect(queue_free)
	collider.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta


func launch(from: Transform3D, initial_direction: Vector3, shooter: Node = null) -> void:
	global_transform = from
	_direction = initial_direction.normalized()
	_shooter = shooter


func _on_body_entered(body: Node) -> void:
	if body == _shooter:
		return

	if body.is_in_group(group_to_damage):
		var damage_amount: int = roundi(damage)
		if body.has_method("take_damage"):
			body.call("take_damage", damage_amount)
			if Events:
				Events.attack_hit.emit(_shooter, body, damage_amount)
		elif body.has_method("on_damage"):
			body.call("on_damage", damage_amount)
			if Events:
				Events.attack_hit.emit(_shooter, body, damage_amount)

	queue_free()
