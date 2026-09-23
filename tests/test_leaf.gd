extends TestCase
## Leafcutter leaves: generation, cutting, and the chaos_to_highway scenario.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _sim_with_leaf(params: Dictionary) -> Simulation:
	var sim := Simulation.new(_config, _registry, 1)
	var colony := sim.add_colony("leafcutter", Vector2(540, 1700))
	sim.spawn_ant(colony, 1, Vector2(540, 1700), 0.0)  # one media for cutting tests
	var p := {"pos": [540, 600], "length": 200, "width": 90, "seed": 3}
	p.merge(params, true)
	sim.add_food_source("leaf", p)
	return sim

func test_generation_is_seeded() -> void:
	var a := _sim_with_leaf({}).food_sources[0] as LeafSource
	var b := _sim_with_leaf({}).food_sources[0] as LeafSource
	var c := _sim_with_leaf({"seed": 4}).food_sources[0] as LeafSource
	check(a.tissue_left > 500, "leaf has tissue (%d cells)" % a.tissue_left)
	check_eq(a.mask, b.mask, "same seed, same leaf")
	check(a.mask != c.mask, "different seed, different leaf")

func test_bite_removes_cells_and_makes_matching_fragment() -> void:
	var sim := _sim_with_leaf({})
	var leaf := sim.food_sources[0] as LeafSource
	var before := leaf.tissue_left
	sim.pos[0] = leaf.nearest_access_point(Vector2(540, 1000))
	var item := leaf.take(sim, 0)
	check(item != null, "bite taken at the edge")
	if item == null:
		return
	var removed := before - leaf.tissue_left
	check(removed >= 3, "bite removed %d cells" % removed)
	check(absf(item.mass - removed * leaf.mass_per_cell) < 1e-5, "fragment mass matches removed cells")
	check(item.shape != null and item.shape.get_width() > 0, "fragment has a shape image")
	check(leaf.version > 0, "leaf version bumped for the renderer")

func test_no_bite_away_from_edge() -> void:
	var sim := _sim_with_leaf({})
	sim.pos[0] = Vector2(540, 1000)  # far from the leaf
	check(sim.food_sources[0].take(sim, 0) == null, "no bite from a distance")

func test_leaf_can_be_stripped_completely() -> void:
	var sim := _sim_with_leaf({"length": 90, "width": 40})
	var leaf := sim.food_sources[0] as LeafSource
	var total_mass := leaf.remaining_mass()
	var taken := 0.0
	var bites := 0
	while not leaf.is_depleted() and bites < 1000:
		sim.pos[0] = leaf.nearest_access_point(Vector2(540, 1000))
		var item := leaf.take(sim, 0)
		check(item != null, "every bite at the edge succeeds")
		if item == null:
			return
		taken += item.mass
		bites += 1
	check(leaf.is_depleted(), "leaf fully consumed after %d bites" % bites)
	check(absf(taken - total_mass) < 1e-4, "fragments add up to the whole leaf")

## Spec test: in chaos_to_highway the colony finds the leaf and brings it home.
func test_chaos_to_highway_forages() -> void:
	var sim := ScenarioLoader.load_simulation("chaos_to_highway", _registry, _config)
	var worst_mass_error := 0.0
	for t in 120 * _config.tick_rate:
		sim.step()
		if t % 30 == 0:
			worst_mass_error = maxf(worst_mass_error, absf(SimChecks.mass_error(sim)))
	var delivered := sim.colonies[0].delivered_items
	check(delivered >= 80, "delivered %d fragments in 120 s, expected >= 80" % delivered)
	check(worst_mass_error < 0.001, "leaf removed = carried + delivered (worst error %f)" % worst_mass_error)
