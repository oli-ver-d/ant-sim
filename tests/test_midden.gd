extends TestCase
## M15f: the refuse system: middens sited away from trails, food and
## entrances; loads kept as deposits that rot into a stain with mass
## conserved; a fixed "dump"; ring middens at the cleared disc's edge; and
## opt-in corpses (worker_lifespan, brood_corpses) carried to a midden.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _run_seconds(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

## A surface colony with a basic nest at (540, 1000); `params` are colony
## params, `nest` merged over the nest params.
func _basic(params: Dictionary = {}, nest: Dictionary = {}, food: Array = [], population: int = 30) -> Simulation:
	var data := {"seed": 7, "food": food, "colonies": [{"species": "leafcutter", "nest_type": "basic_nest",
			"nest": [540, 1000], "population": {"media": population}, "params": params, "nest_params": nest}]}
	return ScenarioLoader.build(data, _registry, _config)

func _conservation_error(m: Midden, time: float) -> float:
	return absf(m.received - m.deposit_mass(time, _registry) - m.stain_mass - m.decayed_mass(time, _registry))

func test_deposits_rot_into_the_stain_and_mass_is_conserved() -> void:
	var m := Midden.new(Vector2(600, 1000), Vector2(500, 1000), "pile", 30.0)
	for k in 40:
		m.add("remnant" if k % 2 == 0 else "soil_clump", m.drop_point(fmod(k * 0.37, 1.0), fmod(k * 0.61, 1.0)), 0.25, k * 10.0, _registry)
	check_eq(m.count(), 40, "every load is a deposit")
	check_eq(m.kinds.size(), 2, "two kinds")
	check(_conservation_error(m, 400.0) < 1e-4, "conserved while fresh")
	# Remnants (half-life 900 s) mostly rot away within a few thousand
	# seconds; soil never does.
	for t in range(400, 6000, 5):
		m.update(float(t), _registry)
	check(m.count() < 40 and m.count() >= 20, "rotted remnants merged, soil kept (%d left)" % m.count())
	check(m.stain_mass > 0.0 and m.decayed > 0.0, "merged into the stain, the rest rotted")
	check(_conservation_error(m, 6000.0) < 1e-4, "carried out = deposits + stain + rotted")
	var ids := Array(m.dep_id)
	var sorted := ids.duplicate()
	sorted.sort()
	check(ids == sorted, "still in drop order")

func test_deposit_count_is_capped() -> void:
	var m := Midden.new(Vector2(600, 1000), Vector2(500, 1000), "pile", 1e9)
	var n := Midden.MAX_DEPOSITS + 300
	for k in n:
		m.add("soil_clump", m.drop_point(fmod(k * 0.37, 1.0), fmod(k * 0.61, 1.0)), 0.1, float(k), _registry)
	check_eq(m.count(), Midden.MAX_DEPOSITS, "capped")
	check_eq(m.dep_id[0], 300, "the oldest went first")
	check(absf(m.stain_mass - 30.0) < 1e-3, "into the stain")
	check(_conservation_error(m, float(n)) < 1e-3, "conserved")

func test_piles_grow_away_from_the_nest() -> void:
	var m := Midden.new(Vector2(640, 1000), Vector2(500, 1000), "pile", 1e9)
	var near := 0.0
	for k in 400:
		var at := m.drop_point(fmod(k * 0.37, 1.0), fmod(k * 0.61, 1.0))
		near = maxf(near, 640.0 - at.x)
		m.add("soil_clump", at, 0.25, 0.0, _registry)
	check(m.centre().x > 650.0, "the middle moved outward (%.0f)" % m.centre().x)
	check(near < m.radius(), "the side facing the nest stays about where it was")

func test_site_avoids_trails_food_and_entrances() -> void:
	var food := [{"type": "food_pile", "pos": [540, 700], "radius": 20, "amount": 200}]
	var sim := _basic({}, {}, food)
	var nest := sim.colonies[0].nest
	var from := nest.entrance_position()
	# A strong trail out to the right.
	var c: int = sim.colonies[0].channels.values()[0]
	for x in range(0, 260, 4):
		for dy in range(-12, 13, 4):
			sim.pheromones.deposit(c, from + Vector2(x, dy), 50.0)
	var at := nest.site_midden(sim)
	check(at != Vector2.INF, "a site was found")
	var dir := (at - from).normalized()
	check(dir.dot(Vector2.UP) < 0.2, "not toward the food (%s)" % dir)
	check(dir.dot(Vector2.RIGHT) < 0.5, "not along the trail (%s)" % dir)
	var d := at.distance_to(from)
	check(d >= nest.midden_distance.x - 1e-3 and d <= nest.midden_distance.y + 1e-3, "within the distance range (%.0f)" % d)
	for s in nest.entrance_sites():
		check(at.distance_to(s.position) >= s.reach(nest.entrance_style) + 20.0, "clear of the entrance")
	# Without food, the trail alone keeps it off to the side.
	var sim2 := _basic()
	var nest2 := sim2.colonies[0].nest
	for x in range(0, 260, 4):
		for dy in range(-12, 13, 4):
			sim2.pheromones.deposit(c, from + Vector2(x, dy), 50.0)
	var at2 := nest2.site_midden(sim2)
	check(absf(at2.y - from.y) > 50.0 or at2.x < from.x - 50.0, "well off the trail (%s)" % (at2 - from))

func test_site_avoids_props_and_walls() -> void:
	var sim := _basic()
	var nest := sim.colonies[0].nest
	var first := nest.site_midden(sim)
	sim.scenery.add({"type": "rock", "center": [first.x, first.y], "radius": 30})
	var second := nest.site_midden(sim)
	check(second != first, "moved off the rock")
	check(not sim.world.prop_near(second, 12.0) and not sim.world.is_blocked(second), "on clear ground")

func test_fungus_farm_waste_goes_to_a_sited_midden() -> void:
	var a := ScenarioLoader.load_simulation("fungus_farm", _registry, _config)
	var b := ScenarioLoader.load_simulation("fungus_farm", _registry, _config)
	for t in 900:
		a.step()
		b.step()
	var nest := a.colonies[0].nest
	check(nest.middens.size() >= 1, "a midden was sited")
	check(nest.dumped_items > 0, "loads carried out (%d)" % nest.dumped_items)
	var loads := 0
	var received := 0.0
	for m in nest.middens:
		loads += m.loads
		received += m.received
		check(_conservation_error(m, a.time()) < 1e-4, "midden %d conserves mass" % m.index)
		for d in m.count():
			check(m.dep_pos[d].distance_to(m.centre()) <= m.radius() * 1.5 + 1.0, "deposit on the midden")
		check_eq(m.kinds[0], "spent_substrate", "leafcutter waste is spent substrate")
	check_eq(loads, nest.dumped_items, "every load is on a midden")
	check(absf(received - nest.dumped_mass) < 1e-4, "and all its mass")
	var nb := b.colonies[0].nest
	check_eq(nb.middens[0].position, nest.middens[0].position, "same site in the same run")
	check_eq(nb.middens[0].dep_pos, nest.middens[0].dep_pos, "same deposits")
	check_eq(b.state_hash(), a.state_hash(), "deterministic")

func test_a_full_midden_gets_a_neighbour() -> void:
	var sim := _basic({}, {"midden": {"capacity": 1.0, "sites": 2}})
	var nest := sim.colonies[0].nest
	var first := nest.midden_for(sim)
	for k in 5:
		nest.drop_refuse(sim, sim.create_item("crumb", 0.25), first.drop_point(0.5, 0.5))
	check(first.is_full(), "full")
	var second := nest.midden_for(sim)
	check(second != first and nest.middens.size() == 2, "a second midden")
	check(second.position.distance_to(first.position) >= first.radius() * 2.0 + 10.0, "clear of the first")
	check(second.position.distance_to(first.position) < 200.0, "but near it")
	for k in 5:
		nest.drop_refuse(sim, sim.create_item("crumb", 0.25), second.drop_point(0.5, 0.5))
	check(nest.midden_for(sim) == second, "no more than `sites`: the last keeps filling")

func test_explicit_dump_is_one_fixed_site() -> void:
	var sim := _basic({}, {"dump": [90, -30], "midden": {"capacity": 0.5}})
	var nest := sim.colonies[0].nest
	var m := nest.midden_for(sim)
	check_eq(m.position, nest.position + Vector2(90, -30), "at the dump")
	for k in 4:
		nest.drop_refuse(sim, sim.create_item("crumb", 0.25), m.drop_point(0.3, 0.7))
	check(nest.midden_for(sim) == m and nest.middens.size() == 1, "never another site")

func test_granary_chaff_goes_to_a_ring_at_the_disc_edge() -> void:
	var data := {"seed": 3, "colonies": [{"species": "harvester", "nest_type": "granary_nest", "nest": [540, 1000],
			"population": {"queen": 1, "minor": 10}, "nest_params": {"underground": {"size": [800, 800]}}}]}
	var sim := ScenarioLoader.build(data, _registry, _config)
	var nest := sim.colonies[0].nest
	check_eq(nest.midden_style, "ring", "harvesters keep a ring")
	var m := nest.midden_for(sim)
	check(absf(m.position.distance_to(nest.entrance_position()) - (nest.clear_radius + 6.0)) < 1e-3, "at the disc's edge")
	for k in 20:
		var at := m.drop_point(fmod(k * 0.37, 1.0), fmod(k * 0.61, 1.0))
		check(absf(at.distance_to(nest.entrance_position()) - m.ring_radius) < 12.0, "on the band")
	check_eq(_registry.refuse_kind_for("chaff"), "husk", "chaff is husks")

func test_corpses_are_off_by_default() -> void:
	var sim := _basic()
	var colony := sim.colonies[0]
	check(not colony.nest.corpses_on, "off")
	var s: int = sim.behaviour_index["carry_corpse"]
	for c in colony.species.castes.size():
		check(not colony.allows(c, s), "carry_corpse not allowed")

func test_old_workers_die_and_are_carried_to_a_midden() -> void:
	var sim := _basic({"worker_lifespan": 40.0}, {}, [], 40)
	var nest := sim.colonies[0].nest
	check(nest.corpses_on, "on")
	_run_seconds(sim, 45.0)
	check(nest.worker_deaths > 0, "some died (%d)" % nest.worker_deaths)
	_run_seconds(sim, 60.0)
	check_eq(nest.worker_deaths, 40, "all of them in the end")
	check(sim.colonies[0].population == 0, "none left")
	# Nobody left to carry the last ones: run a second colony with a longer
	# lifespan so some carry the others.
	var sim2 := _basic({"worker_lifespan": 200.0}, {}, [], 60)
	var nest2 := sim2.colonies[0].nest
	_run_seconds(sim2, 240.0)
	check(nest2.worker_deaths > 0, "died (%d)" % nest2.worker_deaths)
	check(nest2.corpses_taken > 0, "taken (%d)" % nest2.corpses_taken)
	var on_midden := 0
	for m in nest2.middens:
		var k := m.kinds.find("corpse")
		for d in m.count():
			on_midden += 1 if m.dep_kind[d] == k else 0
	check(on_midden > 0, "corpses on a midden (%d)" % on_midden)

func test_brood_corpses_are_carried_up_to_a_midden() -> void:
	var data := {"seed": 3, "colonies": [{"species": "harvester", "nest_type": "granary_nest", "nest": [540, 1000],
			"population": {"queen": 1, "minor": 20}, "params": {"brood_corpses": true},
			"nest_params": {"initial_seeds": 60, "underground": {"size": [800, 800]}}}]}
	var sim := ScenarioLoader.build(data, _registry, _config)
	var nest := sim.colonies[0].nest as ColonyNest
	_run_seconds(sim, 5.0)
	var at := nest.chambers_layout.list[0].centre
	var item := nest.leave_corpse(sim, "brood_corpse", 0.04, at, nest.underground_layer)
	check(item is Corpse and item.layer == nest.underground_layer, "a brood corpse in the nest")
	for t in 240 * _config.tick_rate:
		sim.step()
		if not sim.items.has(item.id):
			break
	check(not sim.items.has(item.id), "carried out and dropped")
	var found := false
	for m in nest.middens:
		found = found or m.kinds.has("brood_corpse")
	check(found, "on a midden")
