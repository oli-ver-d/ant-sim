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
## More states this caste may use when its colony's nest has an underground
## (NestType.underground_layer >= 0), e.g. digging and nest work.
@export var underground_states: PackedStringArray = []
## Per-state param overrides for this caste, merged over SpeciesDef.state_params
## (e.g. {"follow_trail": {"on_arrive": "patrol_trail"}}).
@export var state_params: Dictionary = {}
## Max mass this caste can take from a food source in one go (used by food sources).
@export var carry_capacity: float = 1.0
## A winged reproductive (gyne or male): raised only by a nest's alates
## (ColonyNest nest_params "alates", see Alates), never by spawn_ratio (keep
## it 0), and never part of the abstract population. Alate castes come after
## all the others, so adding them to a species leaves its runs' hashes as
## they were.
@export var alate: bool = false
## Winged castes' look (render only): fore wing length in body lengths, and
## the membrane's tint (alpha 0: the body colour, lightened).
@export var wing_length: float = 1.15
@export var wing_tint: Color = Color(0, 0, 0, 0)

## The wings' membrane colour (see wing_tint).
func wing_color() -> Color:
	return wing_tint if wing_tint.a > 0.0 else color.lightened(0.55)
