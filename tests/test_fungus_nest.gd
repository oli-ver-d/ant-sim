extends TestCase
## M8: the leafcutter fungus nest (garden, colony growth, chambers), the
## generic waste mechanism (carry_waste + NestType waste API) and the
## cutaway panel lookup.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _sim(population: int = 0) -> Simulation:
	var sim := Simulation.new(_config, _registry, 1)
	var colony := sim.add_colony("leafcutter", Vector2(540, 1200))
	for n in population:
		sim.spawn_ant(colony, 1, Vector2(100, 100), 0.0)
	return sim

func _run_seconds(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

func _feed(sim: Simulation, mass: float) -> void:
	var item := sim.create_item("leaf_fragment", mass)
	sim.colonies[0].nest.receive_item(sim, item)
	sim.destroy_item(item.id)

## Leaf delivered = substrate left + fungus grown + waste (inside, carried, dumped).
func _mass_balance_error(sim: Simulation) -> float:
	var nest := sim.colonies[0].nest as FungusNest
	var carried_waste := 0.0
	for id: int in sim.items:
		if sim.items[id].type_id == "waste":
			carried_waste += sim.items[id].mass
	var digested := nest.leaf_received - nest.substrate
	return digested - (nest.fungus_grown + nest.waste + carried_waste + nest.dumped_mass)

func test_leafcutters_use_the_fungus_nest() -> void:
	var sim := _sim()
	check(sim.colonies[0].nest is FungusNest, "leafcutter nest type")

func test_fed_garden_grows_and_raises_brood() -> void:
	var sim := _sim(100)
	var nest := sim.colonies[0].nest as FungusNest
	var fungus0 := nest.fungus
	_feed(sim, 200.0)
	_run_seconds(sim, 60.0)
	check(nest.fungus_grown > 0.0, "garden digested leaf")
	check(nest.substrate < 200.0, "substrate used up over time")
	check(nest.ants_raised > 0, "brood raised (%d)" % nest.ants_raised)
	check_eq(sim.colonies[0].population, 100 + nest.ants_raised, "new ants joined the colony")
	check(nest.fungus + nest.ants_raised * nest.ant_cost > fungus0, "garden grew overall")
	check(absf(_mass_balance_error(sim)) < 0.01, "leaf mass accounted for")

func test_starved_garden_shrinks_and_stops_brood() -> void:
	var sim := _sim(150)
	var nest := sim.colonies[0].nest as FungusNest
	_run_seconds(sim, 120.0)
	var raised := nest.ants_raised
	check(nest.fungus < nest.brood_reserve + nest.ant_cost, "no leaf: garden shrinks to the reserve (%.1f)" % nest.fungus)
	_run_seconds(sim, 60.0)
	check_eq(nest.ants_raised, raised, "no brood without surplus fungus")

func test_chambers_are_dug_as_the_garden_grows() -> void:
	var sim := _sim()
	var nest := sim.colonies[0].nest as FungusNest
	check_eq(nest.chambers, 1, "starts with one chamber")
	nest.fungus = nest.chamber_capacity * 2.5
	nest.update(sim, sim.dt)
	check_eq(nest.chambers, 3, "chambers for the garden")
	nest.fungus = nest.chamber_capacity * 100.0
	nest.update(sim, sim.dt)
	check_eq(nest.chambers, nest.max_chambers, "capped")

func test_waste_is_carried_to_the_dump() -> void:
	var sim := _sim()
	var nest := sim.colonies[0].nest as FungusNest
	nest.waste = nest.waste_load * 3.0
	var ant := sim.spawn_ant(sim.colonies[0], 0, nest.entrance_position(), 0.0)
	sim.change_state(ant, "carry_waste")
	_run_seconds(sim, 1.0)
	check(sim.carried[ant] >= 0, "picked up a load at the entrance")
	check_eq(sim.item_of(ant).type_id, "waste", "a waste item")
	_run_seconds(sim, 20.0)
	check(nest.dumped_items >= 1, "dumped (%d loads)" % nest.dumped_items)
	var waste_items := 0
	for id: int in sim.items:
		if sim.items[id].type_id == "waste":
			waste_items += 1
	check(waste_items <= 1, "dumped loads are absorbed into the pile")

func test_nests_without_waste_send_workers_back() -> void:
	var sim := _sim()
	var ant := sim.spawn_ant(sim.colonies[0], 0, sim.colonies[0].nest.entrance_position(), 0.0)
	sim.change_state(ant, "carry_waste")
	_run_seconds(sim, 0.5)
	check_eq(sim.state_id(ant), "linger", "nothing to carry -> on_none")

func test_cutaway_only_for_nests_that_have_one() -> void:
	var sim := Simulation.new(_config, _registry, 1)
	sim.add_colony("leafcutter", Vector2(300, 1200))
	sim.add_colony("harvester", Vector2(800, 1200))
	var panel := CutawayPanel.create(sim, _registry, 0, Rect2(0, 0, 400, 300))
	check(panel != null, "fungus nest has a cutaway view")
	if panel != null:
		panel.free()
	check(CutawayPanel.create(sim, _registry, 1, Rect2(0, 0, 400, 300)) == null, "seed nest has none")

## fungus_farm: leaf feeds the garden, the colony grows, waste piles up.
func test_fungus_farm_colony_grows() -> void:
	var sim := ScenarioLoader.load_simulation("fungus_farm", _registry, _config)
	var colony := sim.colonies[0]
	var nest := colony.nest as FungusNest
	_run_seconds(sim, 300.0)
	check(colony.population >= 250, "colony grew from 150 to %d" % colony.population)
	check(nest.chambers >= 2, "chambers dug (%d)" % nest.chambers)
	check(nest.dumped_items >= 100, "waste dumped (%d loads)" % nest.dumped_items)
	check(absf(_mass_balance_error(sim)) < 0.01, "leaf mass accounted for")
	check(absf(SimChecks.mass_error(sim)) < 0.001, "food mass conserved")
