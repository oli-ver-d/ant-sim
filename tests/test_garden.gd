extends TestCase
## M11c: the fungus gardens cell by cell (GardenGrid), the leaf processing
## line (carried down, cut into pulp, planted), weeding, and gardens growth
## planning new chambers.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _sim(population: Dictionary = {}, nest: Dictionary = {}, food: Array = [], seed_value: int = 4) -> Simulation:
	var params := {"initial_fungus": 40, "brood_reserve": 5, "underground": {"size": [900, 900]},
			"brood": {"lay_interval": 1000}}
	params.merge(nest, true)
	var data := {"seed": seed_value, "colonies": [{"species": "leafcutter", "nest": [540, 1000],
			"population": population, "nest_params": params}], "food": food}
	return ScenarioLoader.build(data, _registry, _config)

func _nest(sim: Simulation) -> FungusNest:
	return sim.colonies[0].nest as FungusNest

func _run_seconds(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

## Everything that went into the gardens is still there or accounted for.
func _garden_balance_error(nest: FungusNest, initial: float) -> float:
	var g := nest.garden
	return initial + nest.planted_mass - (g.total_fungus() + g.total_substrate() + g.total_spent()
			+ nest.fungus_eaten + nest.fed_mass + nest.weeded_mass)

func test_garden_grid_is_the_nest_totals() -> void:
	var sim := _sim({"queen": 1, "minim": 6}, {"initial_fungus": 12})
	var nest := _nest(sim)
	var g := nest.garden
	check(g != null, "a garden grid")
	check(g.cells.size() > 50, "founding garden cells (%d)" % g.cells.size())
	check(absf(g.total_fungus() - 12.0) < 1e-3, "starting fungus seeded into the grid (%.3f)" % g.total_fungus())
	check(GardenGrid.CELL < sim.layers[nest.underground_layer].world.cell_size, "finer than the nav grid")
	for n in 20:
		g.plant(nest.garden_spot() + Vector2(n % 5, n / 5) * 3.0, 0.5)
	nest.planted_mass += 10.0
	_run_seconds(sim, 60.0)
	check(absf(nest.fungus - g.total_fungus()) < 1e-5, "nest fungus = grid fungus")
	check(absf(nest.substrate - g.total_substrate()) < 1e-5, "nest substrate = grid substrate")
	var f := g.total_fungus()
	g.recount()
	check(absf(g.total_fungus() - f) < 1e-3, "running totals match a recount")
	check(nest.garden.grown > 0.0, "the pulp grew fungus")
	check(absf(_garden_balance_error(nest, 12.0)) < 1e-3, "garden mass balance (error %.5f)" % _garden_balance_error(nest, 12.0))

func test_unfed_garden_shrinks() -> void:
	var sim := _sim({"queen": 1, "minim": 30}, {"upkeep_per_ant": 0.002})
	var nest := _nest(sim)
	var f0 := nest.fungus
	_run_seconds(sim, 120.0)
	check(nest.fungus < f0 * 0.9, "no leaf: the garden shrank (%.1f -> %.1f)" % [f0, nest.fungus])
	check(nest.fungus_eaten > 0.0, "eaten by the colony")
	check(absf(_garden_balance_error(nest, f0)) < 1e-3, "mass balance")

## Old garden turns to spent material, and gardeners weed it out and carry
## it to the dump.
func test_spent_material_is_removed_as_waste() -> void:
	var sim := _sim({"queen": 1, "minim": 16}, {"underground": {"size": [900, 900], "garden_life": 15}})
	var nest := _nest(sim)
	_run_seconds(sim, 150.0)
	check(nest.weeded_mass > 0.0, "spent material weeded out (%.2f)" % nest.weeded_mass)
	check(nest.dumped_items > 0, "loads carried out to the dump (%d)" % nest.dumped_items)
	var carried := 0.0
	for id: int in sim.items:
		if sim.items[id].type_id == "waste":
			carried += sim.items[id].mass
	check(absf(nest.weeded_mass - nest.dumped_mass - carried) < 1e-4, "weeded = dumped + in transit")
	check(absf(_garden_balance_error(nest, 40.0)) < 1e-3, "mass balance")

## A full garden plans a new chamber (a tunnel and the chamber) to dig.
func test_new_chamber_planned_when_nearly_full() -> void:
	var sim := _sim({"queen": 1, "minim": 10}, {"initial_fungus": 6})
	var nest := _nest(sim)
	_run_seconds(sim, 2.0)
	check_eq(nest.chambers_layout.count(), 1, "just the royal chamber while there is room")
	# Fill the garden up and put pulp on it.
	var g := nest.garden
	for c in g.cells:
		g.add_fungus(c, maxf(0.0, g.cap * 0.95 - g.fungus_at(c)))
		g.substrate[c] += g.cap
	g.recount()
	_run_seconds(sim, 2.0)
	check(nest.garden_pressure() > 0.8, "gardens nearly full (%.2f)" % nest.garden_pressure())
	check(nest.chambers_layout.count() >= 2, "a new chamber planned")
	var names: PackedStringArray = []
	for job in nest.plan.jobs:
		names.append(job.name)
	check(names.has("tunnel1") and names.has("chamber1"), "dug as a tunnel and a chamber (%s)" % names)
	var ch := nest.chambers_layout.list[1]
	check(ch.centre.distance_to(nest.chambers_layout.royal().centre) > ch.radius + nest.chambers_layout.royal().radius,
			"clear of the royal chamber")
	check(nest.role_need.get("dig", 0) >= 2, "diggers wanted (%d)" % nest.role_need.get("dig", 0))

## Leaf carriers bring fragments down; gardeners cut them into pulp and
## plant it; leaf mass is accounted for all the way.
func test_leaf_processing_line() -> void:
	var sim := _sim({"queen": 1, "minim": 20, "media": 30}, {},
			[{"type": "leaf", "pos": [540, 820], "length": 200, "width": 100, "seed": 2}])
	var nest := _nest(sim)
	var saw_pulp := false
	var saw_down := false
	var worst_mass := 0.0
	for t in 180 * _config.tick_rate:
		sim.step()
		if t % 15 == 0:
			for i in sim.high_water:
				if sim.alive[i] == 0:
					continue
				var s := sim.state_id(i)
				if s == "carry_down" and sim.layer[i] == nest.underground_layer and sim.carried[i] >= 0:
					saw_down = true
				if sim.carried[i] >= 0 and sim.item_of(i).type_id == "pulp":
					saw_pulp = true
			worst_mass = maxf(worst_mass, absf(SimChecks.mass_error(sim)))
	check(saw_down, "fragments carried down into the nest")
	check(nest.leaf_items > 0, "fragments arrived at the gardens (%d)" % nest.leaf_items)
	check(saw_pulp, "gardeners carried pulp")
	check(nest.planted_mass > 1.0, "pulp planted (%.2f)" % nest.planted_mass)
	check(worst_mass < 0.001, "leaf mass conserved (worst error %f)" % worst_mass)
	check_eq(sim.colonies[0].delivered_items, nest.leaf_items, "a delivery is a fragment arriving underground")
	check(absf(_garden_balance_error(nest, 40.0)) < 1e-3, "garden mass balance")

func test_founding_queen_feeds_her_garden() -> void:
	var sim := _sim({"queen": 1}, {"initial_fungus": 8, "underground": {"size": [900, 900], "open": false}})
	var nest := _nest(sim)
	check(nest.queen_reserve > 0.0, "a sealed nest's queen has reserves")
	_run_seconds(sim, 60.0)
	check(nest.planted_mass > 1.0, "she manured the garden (%.2f)" % nest.planted_mass)
	check(nest.garden.grown > 0.0, "and it grew")
	check(absf(_garden_balance_error(nest, 8.0)) < 1e-3, "mass balance")

func test_garden_is_deterministic() -> void:
	var a := _sim({"queen": 1, "minim": 10, "media": 10}, {}, [{"type": "leaf", "pos": [540, 820], "seed": 2}])
	var b := _sim({"queen": 1, "minim": 10, "media": 10}, {}, [{"type": "leaf", "pos": [540, 820], "seed": 2}])
	_run_seconds(a, 40.0)
	_run_seconds(b, 40.0)
	check_eq(a.state_hash(), b.state_hash(), "same run, same hash")

## An over-full seed (more fungus than the founding garden holds) is kept,
## not lost.
func test_seeding_keeps_all_the_fungus() -> void:
	var sim := _sim({"queen": 1}, {"initial_fungus": 300})
	check(absf(_nest(sim).garden.total_fungus() - 300.0) < 1e-2, "all 300 in the grid")
