class_name RefuseKind
extends RefCounted
## A kind of refuse a midden holds (Midden deposits): how fast it rots and
## how big a deposit of it is. Registered by id (Registry.
## register_refuse_kind), with the item types that become it when dropped on
## a midden; drawn by the renderer registered as "refuse:<id>".

var id: String = ""
## Seconds for a deposit to lose half its mass (0 = never rots, e.g. soil).
var half_life: float = 0.0
## Radius of a deposit of mass m: size * sqrt(m), in world units.
var size: float = 4.0

func _init(kind_id: String = "", kind_half_life: float = 0.0, kind_size: float = 4.0) -> void:
	id = kind_id
	half_life = kind_half_life
	size = kind_size

## Share of a deposit's mass left after `age` seconds.
func left_after(age: float) -> float:
	if half_life <= 0.0:
		return 1.0
	return pow(0.5, maxf(age, 0.0) / half_life)

func radius_of(mass: float) -> float:
	return size * sqrt(maxf(mass, 0.0))
