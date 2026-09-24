class_name PatrolTrailBehaviour
extends Behaviour
## Majors' trunk-trail maintenance patrol: walk slowly along `follow_channel`
## (the foraging trail) and look for debris lying on cells where that trail is
## strong (high traffic). Found -> `on_debris` with the item id in scratch_i.
##
## params: follow_channel, speed_factor (0.7), give_up_after (s), on_give_up,
##         on_debris ("clear_debris")
## tunables: debris_sense_radius, debris_trail_threshold (real pheromone units),
##           debris_scan_interval (ticks)

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colony_of(i)
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var at := sim.pos[i]
	var follow: int = p.get("follow_channel", -1)

	var give_up: float = p.get("give_up_after", 0.0)
	if give_up > 0.0 and sim.timer[i] > give_up:
		return p.get("on_give_up", "follow_trail")

	var interval := int(colony.params.get(&"debris_scan_interval", 6))
	if follow >= 0 and (sim.tick_count + i) % interval == 0:
		var debris := _find_debris_on_trail(sim, at, follow, colony)
		if debris != null:
			sim.scratch_i[i] = debris.id
			return p.get("on_debris", "clear_debris")

	var turn := 0.0
	if follow >= 0:
		turn = Steering.sense_turn(sim, follow, at, sim.heading[i], colony, sim.layer[i])
	Steering.move(sim, i, turn, sim.speed[i] * float(p.get("speed_factor", 0.7)), dt)
	return ""

## Nearest unclaimed ground debris within sensing range that sits on strong trail.
static func _find_debris_on_trail(sim: Simulation, at: Vector2, channel: int, colony: Colony) -> Item:
	var radius: float = colony.params.get(&"debris_sense_radius", 45.0)
	var threshold: float = colony.params.get(&"debris_trail_threshold", 0.35)
	var best: Item = null
	var best_d := radius * radius
	for id in sim.ground_clutter():
		var item: Item = sim.items[id]
		if item.reserved_by >= 0:
			continue
		var d := item.position.distance_squared_to(at)
		if d < best_d and sim.pheromones.sample(channel, item.position) >= threshold:
			best_d = d
			best = item
	return best
