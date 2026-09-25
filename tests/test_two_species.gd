extends TestCase
## Harvester ants (added purely as a species module) and the two_species scenario.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func test_harvester_module_registered() -> void:
	check(_registry.loaded_modules.has("harvester"), "harvester module discovered")
	var def := _registry.species.get("harvester") as SpeciesDef
	check(def != null and def.castes.size() == 3, "harvester species with 3 castes (minor, major, queen)")
	check(def.castes[2].spawn_ratio == 0.0, "the queen is never spawned as a worker")
	check(_registry.food_source_types.has("seed_pile"), "seed_pile registered")
	check(_registry.nest_types.has("seed_nest"), "seed_nest registered")

func test_seed_pile_gives_seeds_one_by_one() -> void:
	var sim := Simulation.new(_config, _registry, 1)
	var colony := sim.add_colony("harvester", Vector2(540, 1500))
	var ant := sim.spawn_ant(colony, 0, Vector2(540, 1500), 0.0)
	var pile := sim.add_food_source("seed_pile", {"pos": [540, 500], "count": 10, "seed": 1}) as SeedPile
	var total := pile.remaining_mass()
	var taken := 0.0
	sim.pos[ant] = Vector2(540, 1000)
	check(pile.take(sim, ant) == null, "no seed out of reach")
	for n in 10:
		sim.pos[ant] = pile.nearest_access_point(sim.pos[ant])
		var item := pile.take(sim, ant)
		check(item != null, "seed %d taken" % n)
		if item == null:
			return
		taken += item.mass
	check(pile.is_depleted(), "pile empty after 10 seeds")
	check(absf(taken - total) < 1e-5, "seed masses add up")

func test_two_species_both_forage() -> void:
	var sim := ScenarioLoader.load_simulation("two_species", _registry, _config)
	check_eq(sim.pheromones.channel_count(), 4, "each colony has its own two channels")
	var worst_mass_error := 0.0
	for t in 120 * _config.tick_rate:
		sim.step()
		if t % 30 == 0:
			worst_mass_error = maxf(worst_mass_error, absf(SimChecks.mass_error(sim)))
	var leaf := sim.colonies[0].delivered_items
	var seeds := sim.colonies[1].delivered_items
	check(leaf >= 60, "leafcutters delivered %d fragments, expected >= 60" % leaf)
	check(seeds >= 100, "harvesters delivered %d seeds, expected >= 100" % seeds)
	check(worst_mass_error < 0.001, "mass conserved across both colonies (worst %f)" % worst_mass_error)
