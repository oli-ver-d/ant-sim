class_name SeekRideBehaviour
extends Behaviour
## A hitchhiker minim has found the leaf (its id is in scratch_i): hang around
## the cutting edge and climb onto a fragment that a carrier is just taking
## home (in real colonies these minims guard carriers from parasitic flies).
##
## Every few ticks it looks for a carried leaf fragment of its own colony,
## with room for a rider, whose carrier is within `seek_ride_reach`.
##
## params: on_ride ("hitchhike"), timeout (s, 40), on_timeout ("follow_trail"),
##         on_lost ("explore")
## tunables: seek_ride_reach, max_riders, ride_item_type

const SCAN_INTERVAL := 3
## Stay about this far from the leaf edge while waiting.
const HOVER_DISTANCE := 10.0

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_f1[i] = 0.0

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colony_of(i)
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var src := sim.food_by_id(sim.scratch_i[i])
	if src == null or src.is_depleted():
		return p.get("on_lost", "explore")
	if sim.timer[i] > float(p.get("timeout", 40.0)):
		return p.get("on_timeout", "follow_trail")

	var at := sim.pos[i]
	if (sim.tick_count + i) % SCAN_INTERVAL == 0:
		var item := _find_ride(sim, i, colony)
		if item != null:
			# Sit somewhere on the fragment (item frame: x along the carrier's heading).
			var offset := Vector2(sim.rng.randf_range(-1.5, 1.5), sim.rng.randf_range(-1.5, 1.5))
			sim.mount(i, item, offset)
			return p.get("on_ride", "hitchhike")

	# Hover near the leaf edge: head for it, slow down and mill about when close.
	sim.scratch_f1[i] -= dt
	if sim.scratch_f1[i] <= 0.0:
		sim.target[i] = src.nearest_access_point(at)
		sim.scratch_f1[i] = 0.5
	var goal := sim.target[i]
	var near := at.distance_to(goal) < HOVER_DISTANCE
	var turn := 0.0 if near else Steering.turn_toward(at, sim.heading[i], goal)
	Steering.move(sim, i, turn, sim.speed[i] * (0.3 if near else 1.0), dt)
	return ""

func _find_ride(sim: Simulation, i: int, colony: Colony) -> Item:
	var params := colony.params
	var reach: float = params.get(&"seek_ride_reach", 8.0)
	var max_riders: int = int(params.get(&"max_riders", 1))
	var ride_type: String = params.get(&"ride_item_type", "")
	var at := sim.pos[i]
	var best: Item = null
	var best_d := reach * reach
	for id: int in sim.items:
		var item: Item = sim.items[id]
		var c := item.carrier
		if c < 0 or item.riders.size() >= max_riders or sim.colony_id[c] != colony.id:
			continue
		if ride_type != "" and item.type_id != ride_type:
			continue
		var d := sim.pos[c].distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = item
	return best
