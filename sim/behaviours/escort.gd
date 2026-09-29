class_name EscortBehaviour
extends Behaviour
## A worker milling round the alates gathered on the mound for a nuptial
## flight, until the last has flown; then its caste's first state (see
## Alates).

func tick(sim: Simulation, i: int, dt: float) -> String:
	var nest := sim.colonies[sim.colony_id[i]].nest as ColonyNest
	if nest == null or nest.alates == null:
		return sim.caste_of(i).initial_state
	return nest.alates.tick_escort(sim, nest, i, dt)
