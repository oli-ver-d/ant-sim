class_name LingerBehaviour
extends Behaviour
## Stay near the nest: wander slowly within `radius` of the entrance, turning
## back toward it when outside. Used for nest guards / idle workers. After
## `duration` seconds (0 = forever) -> `next`.
##
## params: radius (world units, default 80), speed_factor (default 0.5),
##         duration (s, 0 = forever), next ("explore")

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var duration: float = p.get("duration", 0.0)
	if duration > 0.0 and sim.timer[i] > duration:
		return p.get("next", "explore")

	var at := sim.pos[i]
	var turn := 0.0
	var nest := colony.nest
	if nest.has_entrance():
		var home := nest.entrance_position()
		var r: float = p.get("radius", 80.0)
		var d2 := at.distance_squared_to(home)
		if d2 > r * r:
			turn = Steering.turn_toward(at, sim.heading[i], home)
		if nest.is_at_nest(at):
			sim.source_age[i] = 0.0
	Steering.move(sim, i, turn, sim.speed[i] * float(p.get("speed_factor", 0.5)), dt)
	return ""
