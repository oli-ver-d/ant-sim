class_name CutLeafBehaviour
extends Behaviour
## At the leaf edge: stand and saw with the mandibles for a caste-dependent
## time (with a small jitter animation), then take a bite and carry it home.
##
## The leaf is in scratch_i (set by go_to_food). scratch_f0 holds this ant's
## cutting duration; scratch_f1 the heading it started cutting at.
##
## params: on_cut ("carry_home"), on_lost ("explore"), on_missed ("go_to_food")
## tunables: cut_time {caste id: seconds}, cut_jitter_angle (rad), cut_jitter_hz

const DEFAULT_CUT_TIME := 3.0

func enter(sim: Simulation, i: int) -> void:
	var colony := sim.colony_of(i)
	var times: Dictionary = colony.params.get(&"cut_time", {})
	var base: float = times.get(str(sim.caste_of(i).id), DEFAULT_CUT_TIME)
	sim.scratch_f0[i] = base * sim.rng.randf_range(0.8, 1.2)
	# Face the leaf: the ant arrived heading toward the edge point.
	sim.scratch_f1[i] = sim.heading[i]

func tick(sim: Simulation, i: int, dt: float) -> String:
	var p := sim.state_params(i)
	var src := sim.food_by_id(sim.scratch_i[i])
	if src == null or src.is_depleted():
		return p.get("on_lost", "explore")

	if sim.timer[i] < sim.scratch_f0[i]:
		# Sawing: rock the head side to side around the starting heading and
		# shuffle the legs a little; the ant doesn't move.
		var params := sim.colony_of(i).params
		var amp: float = params.get(&"cut_jitter_angle", 0.25)
		var hz: float = params.get(&"cut_jitter_hz", 3.0)
		sim.heading[i] = sim.scratch_f1[i] + amp * sin(sim.timer[i] * TAU * hz + i)
		sim.anim_phase[i] += dt * 2.0
		return ""

	var item := src.take(sim, i)
	if item == null:
		# The edge moved away (a neighbour cut it): find the new edge.
		return p.get("on_missed", "go_to_food")
	sim.pick_up(i, item)
	sim.source_age[i] = 0.0
	sim.heading[i] = wrapf(sim.scratch_f1[i] + PI, -PI, PI)
	return p.get("on_cut", "carry_home")
