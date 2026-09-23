class_name NestType
extends RefCounted
## Base interface for a colony's home. One instance per colony, created from
## the Registry by the species' nest_type id. Rendering is hooked up by
## registering a renderer under "nest:<type_id>" (which may include a cutaway view).
##
## Nests without a fixed entrance (e.g. a moving bivouac) return
## has_entrance() == false and can move `position` in update(); nests that are
## built at runtime can start without an entrance and gain one later.

var type_id: String = ""
## Owning colony, as an index into sim.colonies (not a reference, to avoid a
## Colony <-> NestType reference cycle that would leak).
var colony_id: int = -1
var position: Vector2 = Vector2.ZERO
## Distance from the entrance at which an ant counts as "at the nest".
var radius: float = 12.0
## Distance from which returning ants see the entrance and head straight for it.
var sense_radius: float = 60.0

func setup(_sim: Simulation, owner_colony: Colony, params: Dictionary) -> void:
	colony_id = owner_colony.id
	position = owner_colony.nest_position
	radius = params.get("radius", radius)
	sense_radius = params.get("sense_radius", sense_radius)

func has_entrance() -> bool:
	return true

func entrance_position() -> Vector2:
	return position

func is_at_nest(pos: Vector2) -> bool:
	return has_entrance() and pos.distance_squared_to(entrance_position()) <= radius * radius

## Takes ownership of a delivered item. The Simulation destroys the item afterwards.
func receive_item(_sim: Simulation, _item: Item) -> void:
	pass

## Growth and internal processes; called once per tick.
func update(_sim: Simulation, _dt: float) -> void:
	pass

## Spawns `count` ants at the entrance, choosing castes by spawn_ratio.
func spawn_ants(sim: Simulation, count: int) -> void:
	for n in count:
		var caste := pick_caste(sim)
		var heading := sim.rng.randf_range(-PI, PI)
		sim.spawn_ant(sim.colonies[colony_id], caste, entrance_position(), heading)

## Weighted random caste index by CasteDef.spawn_ratio.
func pick_caste(sim: Simulation) -> int:
	var castes := sim.colonies[colony_id].species.castes
	var total := 0.0
	for c in castes:
		total += c.spawn_ratio
	var r := sim.rng.randf() * total
	for i in castes.size():
		r -= castes[i].spawn_ratio
		if r <= 0.0:
			return i
	return castes.size() - 1
