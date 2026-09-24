class_name FollowTrailBehaviour
extends Behaviour
## Follow `follow_channel` toward a goal, optionally laying `lay_channel`.
## Currently the only goal is "nest": within the nest's sense radius the ant
## heads straight for the entrance, and on arrival switches to `on_arrive`.
##
## Sensors only look ahead, so an ant that decides to go back along a trail
## it just laid must first turn around (`turn_around`, default true).
## If the goal isn't reached within `timeout` seconds -> `on_timeout`.
##
## params: follow_channel, lay_channel, goal ("nest"), on_arrive ("explore"),
##         turn_around (true), timeout (s, default 60), on_timeout ("explore"),
##         home_bias, home_cone_deg (path integration, see Steering.home_turn())

func enter(sim: Simulation, i: int) -> void:
	if sim.state_params(i).get("turn_around", true):
		sim.heading[i] = wrapf(sim.heading[i] + PI, -PI, PI)

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var at := sim.pos[i]
	var nest := colony.nest

	if nest.is_at_nest(at):
		sim.source_age[i] = 0.0
		return p.get("on_arrive", "explore")
	if sim.timer[i] > float(p.get("timeout", 60.0)):
		return p.get("on_timeout", "explore")

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
	Steering.move(sim, i, turn, sim.speed[i], dt)

	var lay: int = p.get("lay_channel", -1)
	if lay >= 0:
		sim.lay(i, lay)
	return ""
