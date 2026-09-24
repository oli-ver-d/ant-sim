class_name GardenBehaviour
extends Behaviour
## A gardener (a minim) in a nest that digs its own underground. In order:
##   - cut leaf fragments lying by the gardens into pulp (a bite at a time,
##     so the fragment shrinks) and plant each bite on the garden
##     (FungusNest.plant_point / plant_pulp): the leaf processing line;
##   - weed out spent material and mould (FungusNest.weed_point / weed_at),
##     then -> `on_waste` to carry the load out;
##   - otherwise tend the garden: walk over it and groom the fungus.
## After `stint` seconds, between jobs -> `on_done`.
##
## params: cut_time (s, 1.6), plant_time (s, 1.0), weed_time (s, 1.8),
##         pulp_mass (0.5, times the caste's carry_capacity), stint (s, 100),
##         on_done ("nest_role"),
##         on_waste ("carry_spent")
## scratch_f1: step (see Step); scratch_i: the fragment's item id;
## scratch_f0: seconds into the current bit of work; target: where to go

enum Step { CHOOSE, TO_LEAF, CUT, TO_PLANT, PLANT, TO_WEED, WEED, TEND }

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_f1[i] = Step.CHOOSE
	sim.scratch_f0[i] = 0.0
	sim.scratch_i[i] = -1

func exit(sim: Simulation, i: int) -> void:
	var nest := sim.colonies[sim.colony_id[i]].nest as FungusNest
	_release(sim, i)
	# Pulp in the jaws gets planted where the gardener stands.
	var item := sim.item_of(i)
	if item != null and item.type_id == "pulp" and nest.garden != null:
		sim.carried[i] = -1
		item.carrier = -1
		nest.plant_pulp(sim, sim.pos[i], item)
		sim.destroy_item(item.id)

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var nest := colony.nest as FungusNest
	if nest.garden == null:
		return p.get("on_done", "nest_role")
	var speed := sim.speed[i]
	if sim.layer[i] != nest.underground_layer:
		_walk(sim, i, nest, nest.garden_spot(), speed, dt, 4.0)
		return ""
	var step := int(sim.scratch_f1[i])
	match step:
		Step.CHOOSE:
			var carried := sim.item_of(i)
			# Between jobs: after the stint, or when the brood needs nurses,
			# take a new role (pulp in the jaws gets planted first).
			if carried == null and (sim.timer[i] > float(p.get("stint", 100.0))
					or nest.role_need.get("nurse", 0) > nest.role_count.get("nurse", 0)):
				return p.get("on_done", "nest_role")
			if carried != null and carried.type_id == "pulp":
				sim.target[i] = nest.plant_point(sim, nest.leaf_chamber())
				_to(sim, i, Step.TO_PLANT)
				return ""
			var frag := nest.claim_fragment(sim, i, sim.pos[i])
			if frag != null:
				sim.scratch_i[i] = frag.id
				sim.target[i] = frag.position
				_to(sim, i, Step.TO_LEAF)
				return ""
			var weed := nest.weed_point(sim)
			if weed != Vector2.INF:
				sim.target[i] = weed
				_to(sim, i, Step.TO_WEED)
				return ""
			# Nothing to do here: done after the stint, or at once if the
			# colony is short of hands elsewhere.
			if sim.timer[i] > float(p.get("stint", 100.0)) or nest.short_elsewhere("garden"):
				return p.get("on_done", "nest_role")
			sim.target[i] = nest.plant_point(sim, nest.leaf_chamber())
			_to(sim, i, Step.TEND)
			sim.scratch_f0[i] = -sim.rng.randf_range(2.0, 5.0)
		Step.TO_LEAF:
			var frag: Item = sim.items.get(sim.scratch_i[i])
			if frag == null or frag.carrier >= 0:
				_release(sim, i)
				_to(sim, i, Step.CHOOSE)
			elif _walk(sim, i, nest, frag.position, speed, dt, 3.5):
				_to(sim, i, Step.CUT)
		Step.CUT:
			var frag: Item = sim.items.get(sim.scratch_i[i])
			if frag == null:
				_to(sim, i, Step.CHOOSE)
				return ""
			if _work(sim, i, dt, frag.position) >= float(p.get("cut_time", 1.6)):
				var k := nest.chambers_layout.chamber_at(frag.position)
				# A bite as big as the gardener can carry (a media takes twice a minim's).
				var pulp := nest.cut_pulp(sim, frag, float(p.get("pulp_mass", 0.5)) * sim.caste_of(i).carry_capacity)
				_release(sim, i)
				sim.pick_up(i, pulp)
				sim.target[i] = nest.plant_point(sim, k if k >= 0 and nest.garden.has_chamber(k) else nest.leaf_chamber())
				_to(sim, i, Step.TO_PLANT)
		Step.TO_PLANT:
			if _walk(sim, i, nest, sim.target[i], speed, dt, 2.5):
				_to(sim, i, Step.PLANT)
		Step.PLANT:
			if _work(sim, i, dt, sim.target[i]) >= float(p.get("plant_time", 1.0)):
				var pulp := sim.item_of(i)
				if pulp != null:
					sim.carried[i] = -1
					pulp.carrier = -1
					nest.plant_pulp(sim, sim.target[i], pulp)
					sim.destroy_item(pulp.id)
				_to(sim, i, Step.CHOOSE)
		Step.TO_WEED:
			if _walk(sim, i, nest, sim.target[i], speed, dt, 2.5):
				_to(sim, i, Step.WEED)
		Step.WEED:
			if _work(sim, i, dt, sim.target[i]) >= float(p.get("weed_time", 1.8)):
				var load := nest.weed_at(sim, sim.target[i])
				if load != null:
					sim.pick_up(i, load)
					return p.get("on_waste", "carry_spent")
				_to(sim, i, Step.CHOOSE)
		Step.TEND:
			if sim.scratch_f0[i] < 0.0:
				# Walking over the garden.
				if _walk(sim, i, nest, sim.target[i], speed * 0.5, dt, 2.0):
					sim.scratch_f0[i] = 0.0
			elif _work(sim, i, dt, sim.target[i] + Vector2(3, 0)) >= 2.5:
				_to(sim, i, Step.CHOOSE)
	return ""

func _to(sim: Simulation, i: int, step: int) -> void:
	sim.scratch_f1[i] = step
	sim.scratch_f0[i] = 0.0

func _release(sim: Simulation, i: int) -> void:
	var frag: Item = sim.items.get(sim.scratch_i[i]) if sim.scratch_i[i] >= 0 else null
	if frag != null and frag.reserved_by == i:
		frag.reserved_by = -1
	sim.scratch_i[i] = -1

func _walk(sim: Simulation, i: int, nest: FungusNest, goal: Vector2, move_speed: float, dt: float, reach: float) -> bool:
	return Travel.go(sim, i, nest.underground_layer, goal, nest.field_toward(goal), move_speed, dt, reach,
			nest.direct_range(goal) * 0.9)

## A tick of work on something at `at`; returns seconds worked so far.
func _work(sim: Simulation, i: int, dt: float, at: Vector2) -> float:
	sim.scratch_f0[i] += dt
	var aim := (at - sim.pos[i]).angle() + sin(sim.scratch_f0[i] * 11.0) * 0.25
	sim.heading[i] = lerp_angle(sim.heading[i], aim, minf(1.0, dt * 8.0))
	sim.anim_phase[i] += dt * 1.2
	return sim.scratch_f0[i]
