class_name NestRoleBehaviour
extends Behaviour
## Picks a worker's next job in a nest with an underground by what the
## colony needs most (ColonyNest.pick_role: nurses for the brood, a retinue
## for the queen, diggers for planned tunnels and chambers), or sends it up
## to the surface to forage or do outside work when nothing inside is short
## of hands. Decided on the first tick.

func tick(sim: Simulation, i: int, _dt: float) -> String:
	var nest := sim.colonies[sim.colony_id[i]].nest as ColonyNest
	if nest.chambers_layout == null:
		return "go_up"
	return nest.pick_role(sim, sim.caste_id[i])
