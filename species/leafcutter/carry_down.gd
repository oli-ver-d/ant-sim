class_name CarryDownBehaviour
extends Behaviour
## A leaf carrier home at a nest that digs its own underground: instead of
## handing the fragment over at the entrance, it carries it down to the
## gardens and drops it at a garden's edge (FungusNest.leaf_drop_point) for
## the gardeners to cut up, then -> `next`. Hitchhikers get off at the
## entrance.
##
## params: next ("go_up")
## scratch_f0: 1 once a drop point is chosen (in target)

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_f0[i] = 0.0

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var nest := colony.nest as FungusNest
	var item := sim.item_of(i)
	if item == null or nest.garden == null:
		return p.get("next", "go_up")
	if sim.scratch_f0[i] == 0.0:
		sim.target[i] = nest.leaf_drop_point(sim)
		sim.scratch_f0[i] = 1.0
	var goal := sim.target[i]
	var move_speed := sim.speed[i] / (1.0 + item.mass * colony.carry_mass_slowdown)
	if Travel.go(sim, i, nest.underground_layer, goal, nest.field_toward(goal), move_speed, dt, 3.0,
			nest.direct_range(goal) * 0.9):
		var dropped := sim.drop_item(i)
		nest.leaf_arrived(sim, dropped)
		sim.source_age[i] = 0.0
		return p.get("next", "go_up")
	return ""
