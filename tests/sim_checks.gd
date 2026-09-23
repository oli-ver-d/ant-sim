class_name SimChecks
extends RefCounted
## Invariant checks shared by simulation tests.

## Number of live ants standing on a blocked cell (should always be 0).
static func ants_in_obstacles(sim: Simulation) -> int:
	var bad := 0
	for i in sim.high_water:
		if sim.alive[i] != 0 and sim.world.is_blocked(sim.pos[i]):
			bad += 1
	return bad

## Food taken from sources minus (items in existence + delivered). Should be 0.
static func mass_error(sim: Simulation) -> float:
	var taken := 0.0
	for src in sim.food_sources:
		taken += src.taken_mass
	var accounted := 0.0
	for id: int in sim.items:
		if sim.items[id].source_id < 0:
			continue  # debris etc.: not food
		accounted += sim.items[id].mass
	for colony in sim.colonies:
		accounted += colony.delivered_mass
	return taken - accounted
