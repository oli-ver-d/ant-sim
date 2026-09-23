class_name FollowTrailBehaviour
extends Behaviour
## Follow `follow_channel` toward a goal, optionally laying `lay_channel`.
## Currently the only goal is "nest": within the nest's sense radius the ant
## heads straight for the entrance, and on arrival switches to `on_arrive`.
##
## params: follow_channel, lay_channel, goal ("nest"), on_arrive ("explore")

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.state_params_by_index[sim.state[i]]
	var at := sim.pos[i]
	var nest := colony.nest

	if nest.is_at_nest(at):
		sim.source_age[i] = 0.0
		return p.get("on_arrive", "explore")

	var turn := 0.0
	if nest.has_entrance() and at.distance_squared_to(nest.entrance_position()) < nest.sense_radius * nest.sense_radius:
		turn = Steering.turn_toward(at, sim.heading[i], nest.entrance_position())
	else:
		var follow: int = p.get("follow_channel", -1)
		if follow >= 0:
			turn = Steering.sense_turn(sim, follow, at, sim.heading[i], colony)
	Steering.move(sim, i, turn, sim.speed[i], dt)

	var lay: int = p.get("lay_channel", -1)
	if lay >= 0:
		sim.lay(i, lay)
	return ""
