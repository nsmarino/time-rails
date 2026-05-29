extends Resource

enum SpellType { EARTH, FIRE, WATER, AIR }

@export var name: String
@export var animation: String = "Spell"
@export var spell_type: SpellType = SpellType.EARTH
@export var mp_cost: int = 5
@export var fallback_duration: float = 1.2
@export var attack_power: int = 35
@export var stagger_power: int = 25
@export var start_particle_fx: String
@export var contact_particle_fx: String
