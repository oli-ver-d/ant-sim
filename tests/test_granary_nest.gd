extends TestCase
## Harvester nests that dig their own granaries (GranaryNest on the core's
## ColonyNest): the founding queen's cache, seeds carried down and stored in
## the granaries, the colony eating them, chaff carried out to the midden.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

## A harvester colony with a granary nest. `nest` is merged over the
## nest_params, `population` per caste; seed piles near the nest when `food`.
func _sim(population: Dictionary, nest: Dictionary = {}, food: bool = false, seed_value: int = 3) -> Simulation:
	var params := {"initial_seeds": 20, "brood_reserve": 1, "ant_cost": 0.5, "underground": {"size": [800, 800]},
			"brood": {"lay_interval": 1000, "egg": 20, "larva": 30, "pupa": 20, "callow": 4}}
	params.merge(nest, true)
	var data := {"seed": seed_value, "colonies": [{"species": "harvester", "nest_type": "granary_nest", "nest": [540, 1000],
			"population": population, "nest_params": params}]}
	if food:
		data["food"] = [{"type": "seed_pile", "pos": [540, 860], "radius": 26, "count": 150, "seed": 4},
				{"type": "seed_pile", "pos": [660, 1050], "radius": 22, "count": 100, "seed": 5}]
	return ScenarioLoader.build(data, _registry, _config)

func _nest(sim: Simulation) -> GranaryNest:
	return sim.colonies[0].nest as GranaryNest

func _run_seconds(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

## Seed mass stored = the cache + seeds brought in - eaten - fed to larvae.
func _store_balance_error(nest: GranaryNest, cache: float) -> float:
	var sum := 0.0
	for m in nest.seed_mass:
		sum += m
	var expected := cache + nest.received_mass - nest.eaten_mass - nest.fed_mass
	return maxf(absf(nest.stored - expected), absf(sum - expected))

func test_a_scenario_colony_can_use_another_nest_type() -> void:
	var sim := _sim({"queen": 1, "minor": 2})
	var nest := _nest(sim)
	check(nest != null, "the colony has a GranaryNest")
	check_eq(nest.type_id, "granary_nest", "type id")
	check(nest.underground_layer > 0, "it has an underground")
	# The species' own nest is unchanged for other colonies.
	var plain := ScenarioLoader.build({"seed": 1, "colonies": [{"species": "harvester", "nest": [540, 1000],
			"population": {"minor": 3}}]}, _registry, _config)
	check(plain.colonies[0].nest is SeedNest, "harvesters still use the seed nest by default")

func test_founding_cache_lies_in_the_royal_chamber() -> void:
	var sim := _sim({"queen": 1})
	var nest := _nest(sim)
	sim.step()
	check_eq(nest.seed_mass.size(), 20, "20 seeds in the cache")
	var inside := 0
	for s in nest.seed_pos.size():
		if nest.chambers_layout.chamber_at(nest.seed_pos[s]) == 0 and nest.seed_chamber[s] == 0:
			inside += 1
	check_eq(inside, 20, "all in the royal chamber")
	check(nest.queen_ant >= 0 and sim.layer[nest.queen_ant] == nest.underground_layer, "the queen is underground")
	check(nest.stats_lines(sim)[2].contains("20 seeds"), "the readout counts stored seeds")

func test_founding_queen_feeds_her_first_brood_from_the_cache() -> void:
	var sim := _sim({"queen": 1}, {"open_entrance_at": 99, "underground": {"size": [800, 800], "open": false},
			"brood": {"lay_interval": 1000, "egg": 20, "larva": 30, "pupa": 20, "callow": 4, "initial": {"larva": 3}}})
	var nest := _nest(sim)
	var cache := nest.stored
	_run_seconds(sim, 90.0)
	check(nest.fed_mass > 0.3, "the queen fed larvae (%.2f)" % nest.fed_mass)
	check_eq(nest.brood.deaths, 0, "no larva starved")
	check(nest.stored < cache, "the cache shrinks")
	check(_store_balance_error(nest, cache) < 1e-3, "seed mass balances (%.5f)" % _store_balance_error(nest, cache))

func test_seeds_are_carried_down_into_granaries() -> void:
	var sim := _sim({"queen": 1, "minor": 12}, {"open_entrance_at": 4,
			"brood": {"lay_interval": 2, "egg": 20, "larva": 30, "pupa": 20, "callow": 4}}, true)
	var nest := _nest(sim)
	var cache := nest.stored
	_run_seconds(sim, 400.0)
	check(nest.has_entrance(), "dug out to the surface")
	check(nest.seeds_received >= 10, "seeds brought home (%d)" % nest.seeds_received)
	check_eq(sim.colonies[0].delivered_items, nest.seeds_received, "each stored seed counts as a delivery")
	var misplaced := 0
	for s in nest.seed_pos.size():
		var k := nest.seed_chamber[s]
		if nest.chambers_layout.chamber_at(nest.seed_pos[s]) != k or not nest.is_granary(k):
			misplaced += 1
	check_eq(misplaced, 0, "every stored seed lies inside a granary")
	check(_store_balance_error(nest, cache) < 1e-2, "seed mass balances (%.5f)" % _store_balance_error(nest, cache))
	check(sim.colonies[0].population > 13, "the colony grew (%d)" % sim.colonies[0].population)

func test_eating_leaves_chaff_that_is_carried_to_the_midden() -> void:
	var sim := _sim({"queen": 1, "minor": 30}, {"initial_seeds": 150, "upkeep_per_ant": 0.004,
			"underground": {"size": [800, 800], "open": true}})
	var nest := _nest(sim)
	_run_seconds(sim, 240.0)
	check(nest.eaten_mass > 1.0, "the colony ate (%.2f)" % nest.eaten_mass)
	check(nest.chaff_made > 0.3, "husks left as chaff (%.2f)" % nest.chaff_made)
	check(nest.dumped_items > 0, "chaff carried out to the midden (%d loads)" % nest.dumped_items)
	check(absf(nest.chaff_made - nest.chaff_taken - Array(nest.chaff).reduce(func(a: float, b: float) -> float: return a + b, 0.0)) < 1e-6,
			"chaff is conserved")

func test_full_granaries_call_for_new_chambers() -> void:
	var sim := _sim({"queen": 1, "minor": 30}, {"initial_seeds": 200, "granary_capacity": 30,
			"underground": {"size": [900, 900], "open": true}})
	var nest := _nest(sim)
	_run_seconds(sim, 5.0)
	var dug_before := sim.layers[nest.underground_layer].world.dug_cells
	check(nest.space_pressure() > 1.0, "the royal cache overfills it (%.2f)" % nest.space_pressure())
	_run_seconds(sim, 300.0)
	check(nest.chambers_layout.count() > 1, "chambers planned (%d)" % nest.chambers_layout.count())
	var dug := sim.layers[nest.underground_layer].world.dug_cells - dug_before
	check(dug > 150, "and digging toward them (%d cells)" % dug)

func test_granary_runs_are_deterministic() -> void:
	var a := _sim({"queen": 1, "minor": 10}, {}, true, 9)
	var b := _sim({"queen": 1, "minor": 10}, {}, true, 9)
	_run_seconds(a, 120.0)
	_run_seconds(b, 120.0)
	check_eq(a.state_hash(), b.state_hash(), "same seed, same hash")

## The whole harvester_founding run (about 6,600 simulated seconds, ~20
## minutes): tools/test.sh --long test_harvester_founding_grows.
func test_harvester_founding_grows() -> void:
	if not OS.get_cmdline_user_args().has("--long"):
		print("    (long: pass --long to run)")
		return
	var sim := ScenarioLoader.load_simulation("harvester_founding", _registry, _config)
	var colony := sim.colonies[0]
	var nest := colony.nest as GranaryNest
	for t in 6500 * _config.tick_rate:
		sim.step()
	check(colony.total_population() >= 2500, "grew to thousands (%d)" % colony.total_population())
	check(nest.chambers_layout.dug_count() >= 15, "chambers dug (%d)" % nest.chambers_layout.dug_count())
	check(nest.entrances().size() >= 3, "more entrances (%d)" % nest.entrances().size())
	check(nest.dumped_items > 100, "a midden of husks (%d loads)" % nest.dumped_items)
