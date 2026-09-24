class_name Travel
extends RefCounted
## Getting around a layered world: to a point on any layer, through portals
## when the point is on another layer, following navigation fields
## underground (NavGrid) where pheromone trails would be unreliable.
##
## On open ground (no nav field given) ants steer straight at the goal with
## the usual wander and obstacle avoidance (Steering.move); with a nav field
## they follow it downhill with Steering.move_to, which is made for tunnels.

## The first portal linking layer `from` directly to layer `to`, or null.
static func portal_between(sim: Simulation, from: int, to: int) -> Portal:
	for p in sim.portals:
		if p.connects(from) and p.other_layer(from) == to:
			return p
	return null

## One tick of travel for ant i toward `goal` on layer `goal_layer`. On
## another layer it first makes for the portal leading there. On the goal's
## layer it follows nav field `field` (an id on that layer, -1 = none) until
## the field says it is within `direct_within` world units of the field's
## target, then heads straight for `goal`. Returns true once within `reach`
## of the goal (it doesn't move on that tick).
static func go(sim: Simulation, i: int, goal_layer: int, goal: Vector2, field: int, move_speed: float,
		dt: float, reach: float = 3.0, direct_within: float = 0.0) -> bool:
	var li := sim.layer[i]
	if li != goal_layer:
		var p := portal_between(sim, li, goal_layer)
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
	var nav := sim.layers[li].nav_grid
	if nav != null and nav.distance(field, at) > direct_within:
		aim = nav.downhill(field, at)
		if aim == at:
			aim = goal
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
		var aim := sim.layers[li].nav_grid.downhill(p.nav_field, at)
		Steering.move_to(sim, i, end if aim == at else aim, move_speed, dt)
	else:
		Steering.move(sim, i, Steering.turn_toward(at, sim.heading[i], end), move_speed, dt)
	return false
