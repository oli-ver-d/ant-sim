class_name NurseBehaviour
extends Behaviour
## A nurse in a nest with an underground: goes down if it isn't there, then
## cares for the brood (BroodCare: carry eggs from the queen, feed larvae
## with food from the stores, groom, move brood to its pile, free
## callows). Between tasks it waits by the brood. After `stint` seconds, once
## its task is done -> `on_done` (a new role).
##
## params: stint (s, 90), on_done ("nest_role")

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_f1[i] = 0.0
	sim.scratch_f0[i] = 0.0
	sim.scratch_i[i] = -1

func exit(sim: Simulation, i: int) -> void:
	BroodCare.abandon(sim, i, sim.colonies[sim.colony_id[i]].nest as ColonyNest)

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var nest := colony.nest as ColonyNest
	var speed := sim.speed[i]
	if sim.layer[i] != nest.underground_layer:
		var home := nest.pile_centre(Brood.Pile.LARVAE)
		Travel.go(sim, i, nest.underground_layer, home, nest.field_toward(home), speed, dt)
		return ""
	if BroodCare.tick(sim, i, dt, nest, speed):
		return ""
	if sim.timer[i] > float(p.get("stint", 90.0)) or (sim.timer[i] > 5.0 and nest.short_elsewhere("nurse")):
		return p.get("on_done", "nest_role")
	# Nothing to do: wait by the brood.
	var spot := nest.pile_centre(Brood.Pile.LARVAE) + Vector2.from_angle(i * 2.39996) * 12.0
	if sim.pos[i].distance_to(spot) > 4.0:
		Travel.go(sim, i, nest.underground_layer, spot, nest.field_toward(spot), speed * 0.5, dt, 3.0,
				nest.direct_range(spot) * 0.9)
	return ""
