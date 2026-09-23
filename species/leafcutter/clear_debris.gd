class_name ClearDebrisBehaviour
extends Behaviour
## A major removes a piece of debris (id in scratch_i) from the trail:
##   phase 0: walk to it and pick it up;
##   phase 1: carry it off the trail - toward whichever of 8 directions has the
##            weakest `trail_channel` - for `debris_carry_distance`, then drop it.
## The item is reserved while this major deals with it.
##
## scratch_f0: phase; target[i]: where to drop it.
## params: trail_channel, next ("patrol_trail"), timeout (s, 30)
## tunables: debris_carry_distance

const DIRECTIONS := 8
## How far out the 8 candidate directions are probed.
const PROBE_DISTANCE := 40.0

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_f0[i] = 0.0
	var item: Item = sim.items.get(sim.scratch_i[i])
	if item != null:
		item.reserved_by = i

func exit(sim: Simulation, i: int) -> void:
	var item: Item = sim.items.get(sim.scratch_i[i])
	if item != null and item.reserved_by == i:
		item.reserved_by = -1
	# Never leave carrying debris (e.g. on timeout): put it down here.
	if sim.carried[i] >= 0 and sim.item_of(i).obstructs:
		sim.drop_item(i)

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colony_of(i)
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var next: String = p.get("next", "patrol_trail")
	if sim.timer[i] > float(p.get("timeout", 30.0)):
		return next
	var at := sim.pos[i]
	var caste := sim.caste_of(i)

	if sim.scratch_f0[i] == 0.0:
		var item: Item = sim.items.get(sim.scratch_i[i])
		if item == null or item.carrier >= 0 or item.reserved_by != i:
			return next
		if at.distance_to(item.position) <= caste.size * 0.6 + 2.0:
			sim.pick_up(i, item)
			sim.target[i] = item.position + _off_trail_direction(sim, item.position, int(p.get("trail_channel", -1))) \
					* float(colony.params.get(&"debris_carry_distance", 55.0))
			sim.scratch_f0[i] = 1.0
			return ""
		Steering.move(sim, i, Steering.turn_toward(at, sim.heading[i], item.position), sim.speed[i], dt)
		return ""

	# Phase 1: carrying it away.
	var goal := sim.target[i]
	if at.distance_to(goal) <= 4.0:
		sim.drop_item(i)
		sim.heading[i] = wrapf(sim.heading[i] + PI, -PI, PI)
		return next
	var mass := sim.item_of(i).mass if sim.carried[i] >= 0 else 0.0
	Steering.move(sim, i, Steering.turn_toward(at, sim.heading[i], goal),
			sim.speed[i] / (1.0 + mass * colony.carry_mass_slowdown), dt)
	return ""

## Unit direction (one of 8) along which the trail is weakest, probing
## PROBE_DISTANCE out from `from`. Ties keep the first direction found.
static func _off_trail_direction(sim: Simulation, from: Vector2, channel: int) -> Vector2:
	var best := Vector2.RIGHT
	var best_v := INF
	for k in DIRECTIONS:
		var dir := Vector2.from_angle(TAU * k / DIRECTIONS)
		var probe := from + dir * PROBE_DISTANCE
		if sim.world.is_blocked(probe):
			continue
		var v := sim.pheromones.sample(channel, probe) if channel >= 0 else 0.0
		if v < best_v:
			best_v = v
			best = dir
	return best
