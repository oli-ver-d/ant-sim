class_name CarrySpoilBehaviour
extends Behaviour
## Carry a spoil pellet from the digging face up through the nearest nest
## entrance and drop it on that entrance's spoil heap
## (NestType.spoil_position_for(), within `spoil_spread`, chosen once on the
## surface so the heap grows as a mound), then -> `on_done`. Heavier pellets
## slow the ant like any load.
##
## params: on_done ("dig"), spoil_spread (world units, 22)
## scratch_f0: 1 once a drop point is chosen (in target)

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_f0[i] = 0.0

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var nest := colony.nest
	var item := sim.item_of(i)
	if item == null:
		return p.get("on_done", "dig")
	var move_speed := sim.speed[i] / (1.0 + item.mass * colony.carry_mass_slowdown)
	if sim.layer[i] != 0:
		var exit := Travel.best_portal(sim, i, 0, Vector2.ZERO, 0.0)
		if exit != null:
			Travel.to_portal(sim, i, exit, move_speed, dt)
		return ""
	# Came up through sim.transit_portal[i]: its heap.
	if sim.scratch_f0[i] == 0.0:
		var spread: float = p.get("spoil_spread", 22.0)
		sim.target[i] = nest.spoil_position_for(sim.transit_portal[i]) + Vector2.from_angle(sim.rng.randf() * TAU) * spread * sqrt(sim.rng.randf())
		sim.scratch_f0[i] = 1.0
	if Travel.go(sim, i, 0, sim.target[i], -1, move_speed, dt, 4.0):
		var dropped := sim.drop_item(i)
		nest.receive_spoil(sim, dropped, sim.transit_portal[i])
		sim.destroy_item(dropped.id)
		return p.get("on_done", "dig")
	return ""
