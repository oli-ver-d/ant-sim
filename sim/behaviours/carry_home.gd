class_name CarryHomeBehaviour
extends Behaviour
## Carry an item home: follow `follow_channel` (the home trail), lay
## `lay_channel` (the food trail), and move slower the heavier the item.
## Near the nest the entrance is seen directly; at the nest -> `on_arrive`.
##
## home_bias / home_cone_deg: path integration, see Steering.home_turn().
##
## params: follow_channel, lay_channel, on_arrive ("deliver"), home_bias (0),
##         home_cone_deg (0 = off)

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
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
			turn = Steering.sense_turn(sim, follow, at, sim.heading[i], colony, sim.layer[i])
		# Path integration: ants know roughly where home is (see Steering.home_turn).
		# Right after steering around an obstacle they trust the trail instead,
		# which may lead around it (SimConfig.obstacle_memory).
		if nest.has_entrance() and sim.since_obstacle[i] >= colony.obstacle_memory:
			turn = Steering.home_turn(at, sim.heading[i], nest.entrance_position(), turn,
					p.get("home_bias", 0.0), deg_to_rad(p.get("home_cone_deg", 0.0)))

	var item := sim.item_of(i)
	var mass := item.mass if item != null else 0.0
	Steering.move(sim, i, turn, sim.speed[i] / (1.0 + mass * colony.carry_mass_slowdown), dt)

	var lay: int = p.get("lay_channel", -1)
	if lay >= 0:
		sim.lay(i, lay)
	return ""
