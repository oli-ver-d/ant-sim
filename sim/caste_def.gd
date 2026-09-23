class_name CasteDef
extends Resource
## One caste of a species (e.g. a small worker or a large soldier): its body,
## movement and which behaviour states it uses.

@export var id: StringName = &""
## Body length in world units.
@export var size: float = 8.0
## Cruise speed in world units per second.
@export var speed: float = 40.0
## Maximum turn rate in radians per second.
@export var turn_rate: float = 5.0
@export var color: Color = Color(0.5, 0.25, 0.1)

@export_group("Body proportions")
@export var head_scale: float = 1.0
@export var thorax_scale: float = 1.0
@export var abdomen_scale: float = 1.0
@export var mandible_size: float = 0.3
@export var leg_length: float = 1.0

@export_group("Colony")
## Relative weight when the nest picks which caste to spawn.
@export var spawn_ratio: float = 1.0
## Behaviour state ids this caste may be in.
@export var states: PackedStringArray = []
@export var initial_state: String = "explore"
## Max mass this caste can take from a food source in one go (used by food sources).
@export var carry_capacity: float = 1.0
