class_name TendGranaryBehaviour
extends Behaviour
## A worker keeping the granaries of a harvester nest (GranaryNest). In
## order:
##   - gather a load of chaff (husks of eaten seeds) by the heap where most
##     has piled up (GranaryNest.chaff_point / take_chaff), then -> `on_waste`
##     to carry it out to the midden;
##   - otherwise sort the seeds: walk to a heap and turn seeds over a while.
## After `stint` seconds, between jobs -> `on_done` (at once, when nothing
## needs doing and another role is short of hands).
##
## params: gather_time (s, 1.8), sort_time (s, 3), stint (s, 90),
##         on_done ("nest_role"), on_waste ("carry_spent")
## scratch_f1: step (see Step); scratch_f0: seconds into the current bit of
## work (negative while walking to sort); target: where to go

enum Step { CHOOSE, TO_CHAFF, GATHER, SORT }

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_f1[i] = Step.CHOOSE
	sim.scratch_f0[i] = 0.0

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var nest := colony.nest as GranaryNest
	if nest.chambers_layout == null:
		return p.get("on_done", "nest_role")
	var speed := sim.speed[i]
	if sim.layer[i] != nest.underground_layer:
		_walk(sim, i, nest, nest.heap_centre(0), speed, dt, 4.0)
		return ""
	match int(sim.scratch_f1[i]):
		Step.CHOOSE:
			var stint := float(p.get("stint", 90.0))
			if sim.timer[i] > stint or nest.role_need.get("nurse", 0) > nest.role_count.get("nurse", 0):
				return p.get("on_done", "nest_role")
			var at := nest.chaff_point(sim)
			if at != Vector2.INF:
				sim.target[i] = at
				_to(sim, i, Step.TO_CHAFF)
				return ""
			if nest.short_elsewhere("tend_granary"):
				return p.get("on_done", "nest_role")
			sim.target[i] = nest.tend_point(sim)
			_to(sim, i, Step.SORT)
			sim.scratch_f0[i] = -1.0
		Step.TO_CHAFF:
			if _walk(sim, i, nest, sim.target[i], speed, dt, 2.5):
				_to(sim, i, Step.GATHER)
		Step.GATHER:
			if _work(sim, i, dt, sim.target[i]) >= float(p.get("gather_time", 1.8)):
				var load := nest.take_chaff(sim, sim.pos[i])
				if load != null:
					sim.pick_up(i, load)
					return p.get("on_waste", "carry_spent")
				_to(sim, i, Step.CHOOSE)
		Step.SORT:
			if sim.scratch_f0[i] < 0.0:
				if _walk(sim, i, nest, sim.target[i], speed * 0.6, dt, 2.0):
					sim.scratch_f0[i] = 0.0
			elif _work(sim, i, dt, sim.target[i] + Vector2(2, 0)) >= float(p.get("sort_time", 3.0)):
				_to(sim, i, Step.CHOOSE)
	return ""

func _to(sim: Simulation, i: int, step: int) -> void:
	sim.scratch_f1[i] = step
	sim.scratch_f0[i] = 0.0

func _walk(sim: Simulation, i: int, nest: GranaryNest, goal: Vector2, move_speed: float, dt: float, reach: float) -> bool:
	return Travel.go(sim, i, nest.underground_layer, goal, nest.field_toward(goal), move_speed, dt, reach,
			nest.direct_range(goal) * 0.9)

## A tick of work on something at `at`; returns seconds worked so far.
func _work(sim: Simulation, i: int, dt: float, at: Vector2) -> float:
	sim.scratch_f0[i] += dt
	var aim := (at - sim.pos[i]).angle() + sin(sim.scratch_f0[i] * 11.0) * 0.25
	sim.heading[i] = lerp_angle(sim.heading[i], aim, minf(1.0, dt * 8.0))
	sim.anim_phase[i] += dt * 1.2
	return sim.scratch_f0[i]
