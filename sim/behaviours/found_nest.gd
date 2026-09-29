class_name FoundNestBehaviour
extends Behaviour
## A founding queen's arrival from her nuptial flight: flying in, shedding
## her wings, walking the site, digging down and going underground (all in
## ColonyNest.founding, see Founding), then "queen".

func tick(sim: Simulation, i: int, dt: float) -> String:
	var nest := sim.colonies[sim.colony_id[i]].nest as ColonyNest
	if nest == null or nest.founding == null:
		return "queen"
	return nest.founding.tick_queen(sim, nest, i, dt)
