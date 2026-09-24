class_name Steering
extends RefCounted
## Reusable steering helpers. Behaviours decide *where* they'd like to turn
## (a value in [-1, 1], as a fraction of the caste's max turn rate) and then
## call move() to apply wander, obstacle avoidance and the actual step.
##
## Angle convention: y points down, so a positive turn is clockwise on screen
## ("right" from the ant's point of view).
##
## These run for every ant every tick, so they are written for GDScript speed:
## few function calls, grid lookups inlined, packed arrays read via locals
## (reading a local copy of a packed array is free; only writes would copy).
## With the native ant kernel (see NativeAnts) move, move_to, sense_turn and
## sense_away hand over to its versions, which give exactly the same results;
## a change here must be made in native/src/ant_kernel.cpp too.

## Angle of the side probes used for obstacle avoidance.
const AVOID_PROBE_ANGLE := 0.7
## Wider probes used to pick a side when something is dead ahead.
const AVOID_WIDE_ANGLE := 1.4

## Classic three-sensor pheromone model. Samples channel c at the left, centre
## and right sensors (sensor_distance ahead, +-sensor_angle) and returns:
##    0  if the centre is strongest (keep going) or nothing is sensed,
##   -1  to turn left, +1 to turn right, toward the stronger side.
## Raw values are compared, since scaling a whole channel doesn't change the order.
static func sense_turn(sim: Simulation, c: int, at: Vector2, heading_rad: float, colony: Colony, on_layer: int = 0) -> float:
	if sim.native_bound:
		return sim.kernel.sense_turn(c, at, heading_rad, colony.id, on_layer)
	var field := sim.pheromones if on_layer == 0 else sim.layers[on_layer].pheromones
	var values := field.values
	var off := c * field.cell_count
	var inv := field.inv_cell
	var w := field.width
	var h := field.height
	# Forward sensor offset, then rotate it by -angle (left) and +angle (right).
	var fx := cos(heading_rad) * colony.sensor_distance
	var fy := sin(heading_rad) * colony.sensor_distance
	var ca := colony.sensor_cos
	var sa := colony.sensor_sin

	var centre := 0.0
	var x := at.x + fx
	var y := at.y + fy
	if x >= 0.0 and y >= 0.0 and int(x * inv) < w and int(y * inv) < h:
		centre = values[off + int(y * inv) * w + int(x * inv)]
	var left := 0.0
	x = at.x + fx * ca + fy * sa
	y = at.y - fx * sa + fy * ca
	if x >= 0.0 and y >= 0.0 and int(x * inv) < w and int(y * inv) < h:
		left = values[off + int(y * inv) * w + int(x * inv)]
	var right := 0.0
	x = at.x + fx * ca - fy * sa
	y = at.y + fx * sa + fy * ca
	if x >= 0.0 and y >= 0.0 and int(x * inv) < w and int(y * inv) < h:
		right = values[off + int(y * inv) * w + int(x * inv)]

	if centre >= left and centre >= right:
		return 0.0
	# Too faint to follow: ignore (compare in real units).
	if maxf(left, right) * field.scale[c] < colony.sense_threshold:
		return 0.0
	return -1.0 if left > right else 1.0

## The opposite of sense_turn(): turns toward the *weaker* side sensor of
## channel c (0 if the centre is weakest or nothing is sensed). Explorers use
## it on their own home trail to push into ground nobody has walked yet.
static func sense_away(sim: Simulation, c: int, at: Vector2, heading_rad: float, colony: Colony, on_layer: int = 0) -> float:
	if sim.native_bound:
		return sim.kernel.sense_away(c, at, heading_rad, colony.id, on_layer)
	var field := sim.pheromones if on_layer == 0 else sim.layers[on_layer].pheromones
	var fwd := Vector2(cos(heading_rad), sin(heading_rad)) * colony.sensor_distance
	var centre := _sample_open(sim, c, at + fwd, on_layer)
	var left := _sample_open(sim, c, at + fwd.rotated(-colony.sensor_angle), on_layer)
	var right := _sample_open(sim, c, at + fwd.rotated(colony.sensor_angle), on_layer)
	if centre <= left and centre <= right:
		return 0.0
	# Too faint everywhere walkable: no preference.
	var strongest := 0.0
	for v: float in [centre, left, right]:
		if v < INF:
			strongest = maxf(strongest, v)
	if strongest * field.scale[c] < colony.sense_threshold:
		return 0.0
	return -1.0 if left < right else 1.0

## Raw pheromone at a point, or +INF on obstacles (so walls never look like
## "unexplored ground").
static func _sample_open(sim: Simulation, c: int, p: Vector2, on_layer: int = 0) -> float:
	var l := sim.layers[on_layer]
	return INF if l.world.is_blocked(p) else l.pheromones.sample_raw(c, p)

## Turn input in [-1, 1] that steers heading toward `goal`. Proportional near
## the goal direction so ants don't oscillate around it.
static func turn_toward(at: Vector2, heading_rad: float, goal: Vector2) -> float:
	var diff := angle_difference(heading_rad, (goal - at).angle())
	return clampf(diff * 2.0, -1.0, 1.0)

## Obstacle avoidance. Probes ahead and to both sides at `lookahead` distance.
## Returns 0 when the way is clear, otherwise a turn in [-1, 1] away from the
## blocked side. In a narrow passage (both sides blocked, ahead clear) keeps
## going. When blocked dead ahead with both near sides open, the wider
## probes decide; ties turn right so the choice stays deterministic.
static func avoid_turn(world: World, at: Vector2, heading_rad: float, lookahead: float) -> float:
	var ahead := world.is_blocked(at + Vector2.from_angle(heading_rad) * lookahead)
	var left := world.is_blocked(at + Vector2.from_angle(heading_rad - AVOID_PROBE_ANGLE) * lookahead)
	var right := world.is_blocked(at + Vector2.from_angle(heading_rad + AVOID_PROBE_ANGLE) * lookahead)
	if not ahead and not left and not right:
		return 0.0
	# A narrow passage (e.g. a bridge): walls on both sides but clear ahead.
	if not ahead and left and right:
		return 0.0
	if left and not right:
		return 1.0
	if right and not left:
		return -1.0
	var wide_left := world.is_blocked(at + Vector2.from_angle(heading_rad - AVOID_WIDE_ANGLE) * lookahead)
	var wide_right := world.is_blocked(at + Vector2.from_angle(heading_rad + AVOID_WIDE_ANGLE) * lookahead)
	if wide_right and not wide_left:
		return -1.0
	return 1.0

## Applies one tick of movement to ant i:
##   1. turn = desired turn + random wander, overridden by obstacle avoidance
##      (only probed when the ant is near an obstacle or edge), clamped to
##      the caste's turn rate;
##   2. step forward at move_speed unless the next position is blocked, in
##      which case the ant stays put and keeps turning (never enters a blocked cell);
##   3. advance the walk-cycle phase by distance travelled.
static func move(sim: Simulation, i: int, desired_turn: float, move_speed: float, dt: float) -> void:
	if sim.native_bound:
		sim.kernel.move(i, desired_turn, move_speed, dt)
		return
	var colony := sim.colonies[sim.colony_id[i]]
	var c := sim.caste_id[i]
	var world := sim.layers[sim.layer[i]].world if sim.multi_layer else sim.world
	var at := sim.pos[i]
	var h := sim.heading[i]
	var max_turn := colony.caste_turn_rate[c]

	var turn := desired_turn * max_turn + sim.rng.randf_range(-1.0, 1.0) * colony.wander_strength
	var avoid := 0.0
	var cell := int(at.y * world.inv_cell) * world.width + int(at.x * world.inv_cell)
	var near := world.near_blocked[cell] != 0
	if near:
		avoid = avoid_turn(world, at, h, colony.avoid_lookahead)
		if avoid != 0.0:
			turn = avoid * max_turn
	turn = clampf(turn, -max_turn, max_turn)
	h = wrapf(h + turn * dt, -PI, PI)

	var step_len := move_speed * dt
	# Ground clutter (debris) slows ants down.
	if world.clutter[cell] != 0:
		step_len *= colony.clutter_slowdown
	var next := Vector2(at.x + cos(h) * step_len, at.y + sin(h) * step_len)
	# Away from obstacles (not near_blocked) a single step can't reach a blocked cell.
	var blocked := false
	if near:
		var next_cell := world.cell_at(next)
		blocked = next_cell < 0 or world.obstacles[next_cell] != World.Cell.FREE
	if avoid != 0.0 or blocked:
		sim.since_obstacle[i] = 0.0
	if blocked:
		# Can't step: stay here and rotate away so we don't grind into the wall.
		h = wrapf(h + (avoid if avoid != 0.0 else 1.0) * max_turn * dt, -PI, PI)
		step_len = 0.0
	else:
		sim.pos[i] = next
	sim.heading[i] = h
	sim.anim_phase[i] += step_len * colony.caste_phase_per_unit[c]

## Moves ant i one tick toward `goal` in tight spaces (tunnels, chambers):
## turns quickly toward it with only a little wander, slows while turning,
## and instead of probing for obstacles slides along a wall when the straight
## step is blocked. Never enters a blocked cell. Used with navigation fields
## (see Travel), which already route around walls.
static func move_to(sim: Simulation, i: int, goal: Vector2, move_speed: float, dt: float) -> void:
	if sim.native_bound:
		sim.kernel.move_to(i, goal, move_speed, dt)
		return
	var colony := sim.colonies[sim.colony_id[i]]
	var c := sim.caste_id[i]
	var world := sim.layers[sim.layer[i]].world
	var at := sim.pos[i]
	var to := goal - at
	var dist := to.length()
	var h := sim.heading[i]
	var max_turn := colony.caste_turn_rate[c] * 1.5
	var wander := sim.rng.randf_range(-1.0, 1.0) * colony.wander_strength * 0.25
	var step_len := 0.0
	if dist > 0.05:
		var diff := angle_difference(h, to.angle())
		h = wrapf(h + clampf(diff * 5.0 + wander, -max_turn, max_turn) * dt, -PI, PI)
		# Slow down while facing away from the goal, and don't overshoot it.
		var facing := cos(angle_difference(h, to.angle()))
		step_len = minf(move_speed * dt * clampf(0.25 + 0.75 * facing, 0.2, 1.0), dist)
	var fwd := Vector2(cos(h), sin(h))
	var next := at + fwd * step_len
	if step_len > 0.0 and world.is_blocked(next):
		# Slide: keep whichever axis of the step is free, else stay put.
		var slide_x := Vector2(next.x, at.y)
		var slide_y := Vector2(at.x, next.y)
		if absf(fwd.x) >= absf(fwd.y) and not world.is_blocked(slide_x):
			next = slide_x
		elif not world.is_blocked(slide_y):
			next = slide_y
		elif not world.is_blocked(slide_x):
			next = slide_x
		else:
			next = at
			sim.since_obstacle[i] = 0.0
		step_len = at.distance_to(next)
	sim.pos[i] = next
	sim.heading[i] = h
	sim.anim_phase[i] += step_len * colony.caste_phase_per_unit[c]

## Path integration for homeward ants. Combines a pheromone turn with the ant's
## sense of where `home` is:
##   - if the ant's heading is more than `cone` radians off the home direction,
##     the pheromone is ignored and it turns toward home (it won't follow a
##     trail leading away from home, and can't get trapped circling a local
##     peak in the field);
##   - otherwise `bias` (0-1) of a turn toward home is added to the pheromone turn.
static func home_turn(at: Vector2, heading_rad: float, home: Vector2, pheromone_turn: float,
		bias: float, cone: float) -> float:
	var toward := turn_toward(at, heading_rad, home)
	if cone > 0.0 and absf(angle_difference(heading_rad, (home - at).angle())) > cone:
		return toward
	return clampf(pheromone_turn + bias * toward, -1.0, 1.0)
