class_name CarrySpentBehaviour
extends Behaviour
## Carry a load of refuse (spent material or husks a worker took inside) up
## out of the nest and drop it on the waste dump beside the entrance
## (NestType.dump_position(), within `dump_spread`), then -> `on_done`.
##
## params: on_done ("nest_role"), dump_spread (world units, 18)
## scratch_f0: 1 once a drop point is chosen (in target)

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_f0[i] = 0.0

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var nest := colony.nest
	var item := sim.item_of(i)
	if item == null:
		return p.get("on_done", "nest_role")
	var move_speed := sim.speed[i] / (1.0 + item.mass * colony.carry_mass_slowdown)
	if sim.layer[i] != 0:
		Travel.go(sim, i, 0, nest.dump_position(), -1, move_speed, dt)
		return ""
	if sim.scratch_f0[i] == 0.0:
		var spread: float = p.get("dump_spread", 18.0)
		sim.target[i] = nest.dump_position() + Vector2.from_angle(sim.rng.randf() * TAU) * spread * sqrt(sim.rng.randf())
		sim.scratch_f0[i] = 1.0
	if Travel.go(sim, i, 0, sim.target[i], -1, move_speed, dt, 4.0):
		var dropped := sim.drop_item(i)
		nest.receive_waste(sim, dropped)
		sim.destroy_item(dropped.id)
		return p.get("on_done", "nest_role")
	return ""
