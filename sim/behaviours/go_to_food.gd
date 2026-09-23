class_name GoToFoodBehaviour
extends Behaviour
## A food source was sensed (its id is in scratch_i): head for its nearest
## access point. On arrival either hand over to `on_arrive` (e.g. a
## species-specific handling state) or, if none is set, take an item directly
## and switch to `on_pickup`.
##
## The access point is cached in target[i] and re-queried every
## `retarget_interval` seconds (scratch_f1 counts down), since finding the
## nearest point on a large source can be expensive and the point moves as the
## source is used up.
##
## params: lay_channel, on_arrive (""), on_pickup ("carry_home"),
##         on_lost ("explore"), timeout (s), retarget_interval (s, default 0.5)

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_f1[i] = 0.0

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.state_params_by_index[sim.state[i]]
	var src := sim.food_by_id(sim.scratch_i[i])
	if src == null or src.is_depleted() or sim.timer[i] > float(p.get("timeout", 20.0)):
		return p.get("on_lost", "explore")

	var at := sim.pos[i]
	sim.scratch_f1[i] -= dt
	if sim.scratch_f1[i] <= 0.0:
		sim.target[i] = src.nearest_access_point(at)
		sim.scratch_f1[i] = float(p.get("retarget_interval", 0.5))
	var goal := sim.target[i]

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
