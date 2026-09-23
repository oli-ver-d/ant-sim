class_name CarryHomeBehaviour
extends Behaviour
## Carry an item home: follow `follow_channel` (the home trail), lay
## `lay_channel` (the food trail), and move slower the heavier the item.
## Near the nest the entrance is seen directly; at the nest -> `on_arrive`.
##
## params: follow_channel, lay_channel, on_arrive ("deliver")

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.state_params_by_index[sim.state[i]]
	var at := sim.pos[i]
	var nest := colony.nest

	if nest.is_at_nest(at):
		return p.get("on_arrive", "deliver")

	var turn := 0.0
	if nest.has_entrance() and at.distance_squared_to(nest.entrance_position()) < nest.sense_radius * nest.sense_radius:
		turn = Steering.turn_toward(at, sim.heading[i], nest.entrance_position())
	else:
		var follow: int = p.get("follow_channel", -1)
		if follow >= 0:
			turn = Steering.sense_turn(sim, follow, at, sim.heading[i], colony)

	var item := sim.item_of(i)
	var mass := item.mass if item != null else 0.0
	Steering.move(sim, i, turn, sim.speed[i] / (1.0 + mass * colony.carry_mass_slowdown), dt)

	var lay: int = p.get("lay_channel", -1)
	if lay >= 0:
		sim.lay(i, lay)
	return ""
