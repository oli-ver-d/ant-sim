class_name AlateBehaviour
extends Behaviour
## A winged reproductive (gyne or male): waits in the nest, then on a nuptial
## flight walks up, gathers on the mound and takes off (all in
## ColonyNest.alates, see Alates).

func enter(sim: Simulation, i: int) -> void:
	var alates := _alates(sim, i)
	if alates != null:
		alates.join(sim, i)

func tick(sim: Simulation, i: int, dt: float) -> String:
	var nest := sim.colonies[sim.colony_id[i]].nest as ColonyNest
	if nest == null or nest.alates == null:
		return ""
	return nest.alates.tick_alate(sim, nest, i, dt)

func exit(sim: Simulation, i: int) -> void:
	var alates := _alates(sim, i)
	if alates != null:
		alates.leave(i)

static func _alates(sim: Simulation, i: int) -> Alates:
	var nest := sim.colonies[sim.colony_id[i]].nest as ColonyNest
	return nest.alates if nest != null else null
