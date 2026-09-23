class_name GoToFoodBehaviour
extends Behaviour
## A food source was sensed (its id is in scratch_i): head straight for its
## nearest access point. On arrival either hand over to `on_arrive` (e.g. a
## species-specific cutting state) or, if none is set, take an item directly
## and switch to `on_pickup`.
##
## params: lay_channel, on_arrive (""), on_pickup ("carry_home"),
##         on_lost ("explore"), timeout (s)

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.state_params_by_index[sim.state[i]]
	var src := sim.food_by_id(sim.scratch_i[i])
	if src == null or src.is_depleted() or sim.timer[i] > float(p.get("timeout", 20.0)):
		return p.get("on_lost", "explore")

	var at := sim.pos[i]
	var goal := src.nearest_access_point(at)
	if at.distance_to(goal) <= colony.arrive_distance:
		var arrive: String = p.get("on_arrive", "")
		if arrive != "":
			return arrive
		var item := src.take(sim, i)
		if item == null:
			return p.get("on_lost", "explore")
		sim.pick_up(i, item)
		# Touching the food resets deposit decay, then turn back the way we came.
		sim.source_age[i] = 0.0
		sim.heading[i] = wrapf(sim.heading[i] + PI, -PI, PI)
		return p.get("on_pickup", "carry_home")

	Steering.move(sim, i, Steering.turn_toward(at, sim.heading[i], goal), sim.speed[i], dt)
	var lay: int = p.get("lay_channel", -1)
	if lay >= 0:
		sim.lay(i, lay)
	return ""
