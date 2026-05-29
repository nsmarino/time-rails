extends Resource
class_name FseEnemyData

@export var display_name: StringName
@export var character_scene: PackedScene

@export var max_hp: int = 100
@export var speed: float = 3.0
@export var attack_power: int = 10
@export var attack_range: float = 2.0
@export var pursue_range: float = 15.0
## Max distance from spawn point the enemy will chase before returning to wander/idle.
@export var leash_radius: float = 40.0

@export var anim_idle: String = "Idle"
@export var anim_locomotion: String = "RUN"
@export var anim_attack: String = "Combo1"
@export var anim_receive_hit: String = "HitReact"
