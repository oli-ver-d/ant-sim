class_name ExploreBehaviour
extends Behaviour
## Wander, following `follow_channel` when sensed and laying `lay_channel`.
## Switches to `on_food` when a food source is sensed, or `on_give_up` after
## roughly `give_up_after` seconds without finding any.
##
## With `avoid_channel` (usually the colony's own home trail), when there is
## nothing to follow the ant steers toward the least-walked side instead, so
## the colony's search keeps pushing into new ground (e.g. unexplored
## corridors of a maze).
##
## params: follow_channel, lay_channel, on_food ("go_to_food"),
##         give_up_after (s, 0 = never), on_give_up, avoid_channel
## scratch_f0: this ant's give-up time (jittered so ants don't all give up at once)

## Give-up time varies per ant by this fraction either way.
const GIVE_UP_JITTER := 0.35

func enter(sim: Simulation, i: int) -> void:
	var give_up: float = sim.state_params(i).get("give_up_after", 0.0)
	sim.scratch_f0[i] = give_up * sim.rng.randf_range(1.0 - GIVE_UP_JITTER, 1.0 + GIVE_UP_JITTER)

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var at := sim.pos[i]

	# Checking for food and the nest every tick is wasteful; stagger these
	# checks across ants so each ant does them every food_check_interval ticks.
	if (sim.tick_count + i) % colony.food_check_interval == 0:
		var src := sim.find_sensed_food(at, colony)
		if src != null:
			sim.scratch_i[i] = src.id
			return p.get("on_food", "go_to_food")
		# Passing the nest counts as touching the home trail's source.
		if colony.nest.is_at_nest(at):
			sim.source_age[i] = 0.0

	var give_up := sim.scratch_f0[i]
	if give_up > 0.0 and sim.timer[i] > give_up:
		return p.get("on_give_up", "")

	var turn := 0.0
	var follow: int = p.get("follow_channel", -1)
	if follow >= 0:
		turn = Steering.sense_turn(sim, follow, at, sim.heading[i], colony)
	var avoid: int = p.get("avoid_channel", -1)
	if turn == 0.0 and avoid >= 0:
		turn = Steering.sense_away(sim, avoid, at, sim.heading[i], colony)
	Steering.move(sim, i, turn, sim.speed[i], dt)

	var lay: int = p.get("lay_channel", -1)
	if lay >= 0:
		sim.lay(i, lay)
	return ""
