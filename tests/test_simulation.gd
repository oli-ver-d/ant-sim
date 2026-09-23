extends TestCase
## Whole-simulation tests on a small, fast fixture scenario.

const SCENARIO := "res://tests/fixtures/scenarios/forage_small.json"

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _sim(seed_value: int = -1) -> Simulation:
	return ScenarioLoader.load_simulation(SCENARIO, _registry, _config, seed_value)

func test_species_def_loads() -> void:
	var def := _registry.species.get("leafcutter") as SpeciesDef
	check(def != null, "leafcutter registered")
	if def == null:
		return
	check_eq(def.castes.size(), 3, "caste count")
	check_eq(def.channels.size(), 2, "channel count")

func test_determinism() -> void:
	var a := _sim(7)
	var b := _sim(7)
	var c := _sim(8)
	for t in 300:
		a.step()
		b.step()
		c.step()
	check_eq(a.state_hash(), b.state_hash(), "same seed, same state")
	check(a.state_hash() != c.state_hash(), "different seed, different state")

## One long run covering foraging, obstacles and mass conservation.
func test_forage_obstacles_and_mass() -> void:
	var sim := _sim()
	var bad_positions := 0
	var worst_mass_error := 0.0
	for t in 3600:  # 60 simulated seconds
		sim.step()
		if t % 10 == 0:
			bad_positions += _ants_in_obstacles(sim)
			worst_mass_error = maxf(worst_mass_error, absf(_mass_error(sim)))
	var colony := sim.colonies[0]
	check(colony.delivered_items >= 15, "delivered %d items in 60 s, expected >= 15" % colony.delivered_items)
	check_eq(bad_positions, 0, "ants inside obstacle cells")
	check(worst_mass_error < 0.001, "food taken = carried + delivered (worst error %f)" % worst_mass_error)

func test_free_list_reuses_slots() -> void:
	var sim := _sim()
	var colony := sim.colonies[0]
	var before := sim.high_water
	var count := sim.ant_count
	sim.remove_ant(5)
	check_eq(sim.ant_count, count - 1, "ant removed")
	var idx := sim.spawn_ant(colony, 0, colony.nest_position, 0.0)
	check_eq(idx, 5, "freed slot reused")
	check_eq(sim.high_water, before, "no new slot used")

func test_removing_carrier_drops_item() -> void:
	var sim := _sim()
	var item := sim.food_sources[0].take(sim, 0)
	sim.pick_up(0, item)
	sim.remove_ant(0)
	check_eq(item.carrier, -1, "item dropped")
	check(sim.items.has(item.id), "item still exists on the ground")

func _ants_in_obstacles(sim: Simulation) -> int:
	var bad := 0
	for i in sim.high_water:
		if sim.alive[i] != 0 and sim.world.is_blocked(sim.pos[i]):
			bad += 1
	return bad

## taken - (carried + delivered + on the ground); should be 0.
func _mass_error(sim: Simulation) -> float:
	var taken := 0.0
	for src in sim.food_sources:
		taken += src.taken_mass
	var accounted := 0.0
	for id: int in sim.items:
		accounted += sim.items[id].mass
	for colony in sim.colonies:
		accounted += colony.delivered_mass
	return taken - accounted
