class_name Travel
extends RefCounted
## Getting around a layered world: to a point on any layer, through portals
## when the point is on another layer, following navigation fields
## underground (NavGrid) where pheromone trails would be unreliable.
##
## On open ground (no nav field given) ants steer straight at the goal with
## the usual wander and obstacle avoidance (Steering.move); with a nav field
## they follow it downhill with Steering.move_to, which is made for tunnels.
##
## A nest may have several entrances (portals between the same layers): an
## ant takes the one that makes its way shortest (best_portal()).
##
## Lanes: on a layer with SimLayer.lanes > 0, an ant following a nav field
## keeps to the right-hand side of its way where the tunnel is wide enough
## (lane_aim()), so ants going out and ants coming back pass in two streams.
## The native kernel does the same (nav_aim), with the same results.

## Lane keeping: how far to each side a tunnel's width is probed, the width
## below which there are no lanes, and where the lane is (from the middle
## toward the right, as a share of the width).
const LANE_PROBE := 36.0
const LANE_MIN_WIDTH := 14.0
const LANE_OFFSET := 0.3
## Most an aim is moved sideways.
const LANE_MAX_SHIFT := 12.0

## The first portal linking layer `from` directly to layer `to`, or null.
static func portal_between(sim: Simulation, from: int, to: int) -> Portal:
	for p in sim.portals:
		if p.connects(from) and p.other_layer(from) == to:
			return p
	return null

## The portal ant i should take to get to `goal` on layer `to`: among the
## open ones linking its layer to `to`, the one with the shortest way (on
## its layer: along the portal's nav field underground, straight on the
## surface; plus `goal_weight` times the straight distance from the far end
## to the goal). With none open, the first linking portal (to wait at).
static func best_portal(sim: Simulation, i: int, to: int, goal: Vector2, goal_weight: float = 1.0) -> Portal:
	var li := sim.layer[i]
	var at := sim.pos[i]
	var best: Portal = null
	var best_cost := INF
	var first: Portal = null
	var nav := sim.layers[li].nav_grid
	for p in sim.portals:
		if not p.connects(li) or p.other_layer(li) != to:
			continue
		if first == null:
			first = p
		if not p.open:
			continue
		var cost := at.distance_to(p.end_on(li))
		if li == p.layer_b and p.nav_field >= 0 and nav != null:
			cost = nav.distance(p.nav_field, at)
		cost += goal_weight * p.end_on(to).distance_to(goal)
		if best == null or cost < best_cost:
			best = p
			best_cost = cost
	return best if best != null else first

## One tick of travel for ant i toward `goal` on layer `goal_layer`. On
## another layer it first makes for the portal leading there (best_portal).
## On the goal's layer it follows nav field `field` (an id on that layer, -1
## = none) until the field says it is within `direct_within` world units of
## the field's target and nothing blocks the straight line, then heads
## straight for `goal`. Returns true once within `reach` of the goal (it
## doesn't move on that tick).
static func go(sim: Simulation, i: int, goal_layer: int, goal: Vector2, field: int, move_speed: float,
		dt: float, reach: float = 3.0, direct_within: float = 0.0) -> bool:
	var li := sim.layer[i]
	if li != goal_layer:
		var p := best_portal(sim, i, goal_layer, goal)
		if p != null:
			to_portal(sim, i, p, move_speed, dt)
		return false
	var at := sim.pos[i]
	if at.distance_squared_to(goal) <= reach * reach:
		return true
	if field < 0:
		Steering.move(sim, i, Steering.turn_toward(at, sim.heading[i], goal), move_speed, dt)
		return false
	var aim := goal
	var l := sim.layers[li]
	var nav := l.nav_grid
	if nav != null and sim.native_bound:
		var f: NavGrid.Field = nav.fields.get(field)
		if f != null:
			aim = sim.kernel.nav_aim(f.dist, li, at, goal, direct_within, l.lanes)
	elif nav != null and (nav.distance(field, at) > direct_within or not l.world.line_clear(at, goal)):
		aim = nav.downhill(field, at)
		if aim == at:
			aim = goal
		elif l.lanes > 0.0:
			aim = lane_aim(l.world, at, aim, l.lanes)
	Steering.move_to(sim, i, aim, move_speed, dt)
	return false

## One tick toward portal p's end on the ant's layer; enters it on arrival.
## Waits by the end while the portal is closed. Returns true if the ant
## started going through.
static func to_portal(sim: Simulation, i: int, p: Portal, move_speed: float, dt: float) -> bool:
	var li := sim.layer[i]
	var at := sim.pos[i]
	var end := p.end_on(li)
	if at.distance_squared_to(end) <= p.radius * p.radius:
		if p.open:
			return sim.enter_portal(i, p)
		# Sealed: potter about by the plug.
		Steering.move_to(sim, i, end + Vector2.from_angle(sim.heading[i] + 1.0) * p.radius, move_speed * 0.3, dt)
		return false
	if li == p.layer_b and p.nav_field >= 0:
		var l := sim.layers[li]
		var nav := l.nav_grid
		if sim.native_bound:
			Steering.move_to(sim, i, sim.kernel.nav_aim(nav.fields[p.nav_field].dist, li, at, end, -INF, l.lanes), move_speed, dt)
			return false
		var aim := nav.downhill(p.nav_field, at)
		if aim == at:
			aim = end
		elif l.lanes > 0.0:
			aim = lane_aim(l.world, at, aim, l.lanes)
		Steering.move_to(sim, i, aim, move_speed, dt)
	else:
		Steering.move(sim, i, Steering.turn_toward(at, sim.heading[i], end), move_speed, dt)
	return false

## Lane keeping: `aim` (the next point down a nav field from `at`) moved
## toward a lane right of the tunnel's middle, LANE_OFFSET of its width over,
## by `lane` (0-1) of the way, and fully only where the tunnel is at least
## twice LANE_MIN_WIDTH wide (probed square to the way, to LANE_PROBE on each
## side). Narrow tunnels and open chambers (no wall within the probe) have
## no lanes.
static func lane_aim(world: World, at: Vector2, aim: Vector2, lane: float) -> Vector2:
	var dir := aim - at
	var dist := dir.length()
	if dist < 0.001:
		return aim
	var fwd := dir / dist
	var right := Vector2(-fwd.y, fwd.x)
	var step := world.cell_size * 0.5
	var r_free := 0.0
	while r_free < LANE_PROBE and not world.is_blocked(at + right * (r_free + step)):
		r_free += step
	var l_free := 0.0
	while l_free < LANE_PROBE and not world.is_blocked(at - right * (l_free + step)):
		l_free += step
	var width := r_free + l_free
	# Too narrow for two streams, or not a tunnel at all (a chamber).
	if width < LANE_MIN_WIDTH or r_free >= LANE_PROBE or l_free >= LANE_PROBE:
		return aim
	var k := minf(1.0, (width - LANE_MIN_WIDTH) / LANE_MIN_WIDTH)
	var shift := clampf((r_free - l_free) * 0.5 + width * LANE_OFFSET, -LANE_MAX_SHIFT, LANE_MAX_SHIFT)
	# The aim's own sideways offset (the field's path) is replaced by the lane's.
	var lat := dir.dot(right)
	return aim + right * ((shift - lat) * lane * k)
