class_name StoreSeedBehaviour
extends Behaviour
## A forager home at a nest that digs its own underground: instead of
## handing the seed over at the entrance, it carries it down into a granary
## and puts it on the heap there (GranaryNest.store_point / store_seed),
## then -> `next`.
##
## params: next ("nest_role": take a job inside if one is short, else back
##         out to forage)
## scratch_f0: 1 once a drop point is chosen (in target)

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_f0[i] = 0.0

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var nest := colony.nest as GranaryNest
	var item := sim.item_of(i)
	if item == null or nest.chambers_layout == null:
		return p.get("next", "nest_role")
	if sim.scratch_f0[i] == 0.0:
		sim.target[i] = nest.store_point(sim)
		sim.scratch_f0[i] = 1.0
	var goal := sim.target[i]
	var move_speed := sim.speed[i] / (1.0 + item.mass * colony.carry_mass_slowdown)
	if Travel.go(sim, i, nest.underground_layer, goal, nest.field_toward(goal), move_speed, dt, 2.5,
			nest.direct_range(goal) * 0.9):
		var dropped := sim.drop_item(i)
		nest.store_seed(sim, dropped, goal)
		sim.destroy_item(dropped.id)
		sim.source_age[i] = 0.0
		return p.get("next", "nest_role")
	return ""
