extends TestCase
## M10: the leafcutter brood model (queen, eggs, larvae, pupae, callows).

const Stage := LeafcutterBrood.Stage

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

## A leafcutter colony with brood on; `brood` is merged over quick defaults.
func _sim(brood: Dictionary = {}, nest: Dictionary = {}, population: int = 0) -> Simulation:
	var b := {"lay_interval": 1000, "egg": 2, "larva": 3, "pupa": 2, "callow": 1}
	b.merge(brood, true)
	var params := {"initial_fungus": 400, "brood": b}
	params.merge(nest, true)
	var sim := Simulation.new(_config, _registry, 1)
	var colony := sim.add_colony("leafcutter", Vector2(540, 1200), params)
	for n in population:
		sim.spawn_ant(colony, 1, Vector2(100, 100), 0.0)
	return sim

func _nest(sim: Simulation) -> FungusNest:
	return sim.colonies[0].nest as FungusNest

func _run_seconds(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

func _feed(sim: Simulation, mass: float) -> void:
	var item := sim.create_item("leaf_fragment", mass)
	_nest(sim).receive_item(sim, item)
	sim.destroy_item(item.id)

func test_initial_brood_present_at_setup() -> void:
	var sim := _sim({"initial": {"egg": 3, "larva": 4, "pupa": 2}})
	var brood := _nest(sim).brood
	check(brood != null, "brood model on")
	if brood == null:
		return
	check_eq(brood.count_stage(Stage.EGG), 3, "eggs")
	check_eq(brood.count_stage(Stage.LARVA), 4, "larvae")
	check_eq(brood.count_stage(Stage.PUPA), 2, "pupae")
	check_eq(brood.eggs_laid, 0, "initial brood is not logged as laid")
	check_eq(sim.colonies[0].population, 0, "no ants yet")

func test_brood_off_by_default() -> void:
	var sim := Simulation.new(_config, _registry, 1)
	sim.add_colony("leafcutter", Vector2(540, 1200))
	check(_nest(sim).brood == null, "no brood without nest_params.brood")

## One egg goes egg -> larva -> pupa -> callow -> ant; the colony only
## counts it at emergence.
func test_egg_develops_into_an_ant() -> void:
	var sim := _sim({"initial": {"egg": 1}})
	var nest := _nest(sim)
	var brood := nest.brood
	var seen: PackedInt32Array = []
	var pop_changes_before_emergence := 0
	for t in 12 * _config.tick_rate:
		var was := brood.count()
		sim.step()
		if brood.count() > 0:
			var s := brood.stage[0]
			if seen.is_empty() or seen[seen.size() - 1] != s:
				seen.append(s)
			if sim.colonies[0].population != 0:
				pop_changes_before_emergence += 1
		elif was > 0:
			check_eq(sim.colonies[0].population, 1, "the ant joined at emergence")
			var ant := brood.emerge_ants[0]
			check(sim.pos[ant].distance_to(nest.entrance_position()) < 5.0, "it came out at the entrance (one tick of walking)")
	check_eq(seen, PackedInt32Array([Stage.EGG, Stage.LARVA, Stage.PUPA, Stage.CALLOW]), "stages in order")
	check_eq(pop_changes_before_emergence, 0, "population unchanged while it was brood")
	check_eq(brood.count(), 0, "emerged")
	check_eq(brood.emerged, 1, "emergence logged")
	check_eq(nest.ants_raised, 1, "ants_raised")
	check_eq(sim.colonies[0].population, 1, "population")
	var ant := brood.emerge_ants[0]
	check(sim.alive[ant] != 0, "the logged ant is alive")
	check(brood.emerge_tick(0) > 0 and brood.emerge_tick(0) <= sim.tick_count, "emergence tick logged")

func test_larvae_eat_ant_cost() -> void:
	var sim := _sim({"initial": {"larva": 1}})
	var nest := _nest(sim)
	nest.brood.age[0] = 0.0
	nest.brood.growth[0] = 0.0
	var before := nest.fungus
	_run_seconds(sim, 3.0)
	check_eq(nest.brood.stage[0], Stage.PUPA, "fed larva pupated")
	check(absf(before - nest.fungus - nest.ant_cost) < 0.05, "ate ant_cost (%.3f)" % (before - nest.fungus))

func test_queen_lays_at_intervals() -> void:
	var sim := _sim({"lay_interval": 2, "egg": 1000}, {"brood_rate": 1.0})
	var brood := _nest(sim).brood
	_run_seconds(sim, 10.5)
	check_eq(brood.eggs_laid, 5, "one egg every lay_interval")
	check_eq(brood.count_stage(Stage.EGG), 5, "eggs in the nest")
	check_eq(brood.lay_tick(1) - brood.lay_tick(0), 2 * _config.tick_rate, "lay ticks logged")
	check_eq(brood.lay_ids[4], brood.id[4], "lay events name the egg")

func test_starved_garden_stops_laying_and_growth() -> void:
	var sim := _sim({"lay_interval": 1, "larva": 20, "initial": {"larva": 2}}, {"brood_rate": 1.0})
	var nest := _nest(sim)
	var brood := nest.brood
	nest.fungus = nest.brood_reserve
	var laid := brood.eggs_laid
	var growth := brood.growth.duplicate()
	_run_seconds(sim, 5.0)
	check(brood.starving, "starving")
	check_eq(brood.eggs_laid, laid, "no laying at the reserve")
	check_eq(brood.growth, growth, "larvae stop growing")
	check_eq(brood.count_stage(Stage.LARVA), 2, "no larva died")
	# Leaf again: the garden recovers and brood resumes.
	_feed(sim, 300.0)
	_run_seconds(sim, 10.0)
	check(not brood.starving, "fed again")
	check(brood.eggs_laid > laid, "laying resumed (%d)" % brood.eggs_laid)
	check(brood.growth[0] > growth[0], "larvae grow again")

func test_brood_respects_caps() -> void:
	# Plenty of fungus and fast laying: brood is limited by max_brood, then
	# population + brood by max_population.
	var sim := _sim({"lay_interval": 0.1, "egg": 3, "larva": 3, "pupa": 3, "callow": 1, "max_brood": 12,
			"initial": {"egg": 4, "larva": 4, "pupa": 4}},
			{"brood_rate": 1.0, "initial_fungus": 2000, "max_population": 30}, 10)
	var brood := _nest(sim).brood
	var worst_total := 0
	var worst_brood := 0
	for t in 60 * _config.tick_rate:
		sim.step()
		worst_total = maxi(worst_total, sim.colonies[0].population + brood.count())
		worst_brood = maxi(worst_brood, brood.count())
	check(worst_brood <= 12, "brood <= max_brood (%d)" % worst_brood)
	check_eq(worst_brood, 12, "brood reached max_brood")
	check(worst_total <= 30, "population + brood <= max_population (%d)" % worst_total)
	check_eq(sim.colonies[0].population + brood.count(), 30, "filled up to max_population")

func test_brood_is_deterministic() -> void:
	var data := {
		"seed": 3,
		"colonies": [{"species": "leafcutter", "nest": [540, 1200], "population": {"media": 20, "minim": 5},
			"nest_params": {"brood": {"lay_interval": 1, "egg": 3, "larva": 4, "pupa": 3, "callow": 1,
				"initial": {"egg": 3, "larva": 3, "pupa": 3}}}}],
		"food": [{"type": "leaf", "pos": [540, 1000], "length": 200, "width": 100, "seed": 2}],
	}
	var a := ScenarioLoader.build(data, _registry, _config)
	var b := ScenarioLoader.build(data, _registry, _config)
	for t in 300:
		a.step()
		b.step()
	check(_nest(a).brood.emerged > 0, "some ants emerged")
	check_eq(a.state_hash(), b.state_hash(), "same seed, same state with brood")
	_nest(b).brood.age[0] += 0.01
	check(a.state_hash() != b.state_hash(), "brood state is part of the hash")

## fungus_farm has no brood: same state and hash as before M10.
func test_fungus_farm_unchanged_without_brood() -> void:
	var sim := ScenarioLoader.load_simulation("fungus_farm", _registry, _config)
	for t in 900:
		sim.step()
	var nest := _nest(sim)
	check(nest.brood == null, "fungus_farm has no brood")
	check_eq(sim.colonies[0].population, 156, "population")
	check_eq(nest.ants_raised, 6, "ants raised")
	# Recorded before the brood model was added (M9, 900 ticks).
	check_eq(sim.state_hash(), "ae3a9d3680930dc15b0659e7052ae9ae5bdad84e1da6b9efbf306df0847cfa57", "state hash")
