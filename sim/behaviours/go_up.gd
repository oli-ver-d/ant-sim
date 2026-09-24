class_name GoUpBehaviour
extends Behaviour
## Walk up from the nest's underground to the surface through its entrance
## (the nest's portal), then -> `next` (e.g. foraging). Tells the nest when
## the ant comes out (NestType.ant_surfaced), so views can point out new
## workers. Already on the surface -> `next` at once.
##
## params: next ("explore")

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	if sim.layer[i] == 0:
		colony.nest.ant_surfaced(sim, i)
		return p.get("next", "explore")
	var nest := colony.nest
	if nest.portal == null:
		return p.get("next", "explore")
	Travel.to_portal(sim, i, nest.portal, sim.speed[i], dt)
	return ""
