class_name CarryWasteBehaviour
extends Behaviour
## Midden work: fetch a load of waste from the nest entrance and carry it to
## the nest's dump (NestType.dump_position()), then -> `on_done`. If the nest
## has no waste when the ant gets to the entrance -> `on_none`.
##
## Loads are dropped within `dump_spread` of the dump position (chosen per
## trip), so the pile grows as a mound rather than a single point.
##
## params: on_done ("linger"), on_none ("linger"), dump_spread (world units, 18)
## target: where this ant will drop its load

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var nest := colony.nest
	var at := sim.pos[i]

	if sim.carried[i] < 0:
		# Fetch: go to the entrance and take a load.
		if not nest.has_entrance():
			return p.get("on_none", "linger")
		if nest.is_at_nest(at):
			var waste := nest.take_waste(sim)
			if waste == null:
				return p.get("on_none", "linger")
			sim.pick_up(i, waste)
			var spread: float = p.get("dump_spread", 18.0)
			sim.target[i] = nest.dump_position() + Vector2.from_angle(sim.rng.randf() * TAU) * spread * sqrt(sim.rng.randf())
			return ""
		Steering.move(sim, i, Steering.turn_toward(at, sim.heading[i], nest.entrance_position()), sim.speed[i], dt)
		return ""

	# Carry the load to the dump and drop it there.
	var goal := sim.target[i]
	if at.distance_squared_to(goal) <= colony.arrive_distance * colony.arrive_distance * 4.0:
		var item := sim.drop_item(i)
		nest.receive_waste(sim, item)
		sim.destroy_item(item.id)
		return p.get("on_done", "linger")
	var item_mass := sim.item_of(i).mass
	Steering.move(sim, i, Steering.turn_toward(at, sim.heading[i], goal), sim.speed[i] / (1.0 + item_mass * colony.carry_mass_slowdown), dt)
	return ""
