extends TestCase
## M11b: the queen, positioned brood that needs care, nurses and other nest
## roles, the founding sequence and emergence in a leafcutter nest that digs
## its own underground.

const Stage := LeafcutterBrood.Stage
const Pile := LeafcutterBrood.Pile

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

## A leafcutter colony with an underground. `nest` is merged over the
## nest_params (with "brood" merged over quick stage times), `population`
## per caste.
func _sim(population: Dictionary = {}, nest: Dictionary = {}, brood: Dictionary = {}, seed_value: int = 3) -> Simulation:
	var b := {"lay_interval": 1000, "egg": 20, "larva": 30, "pupa": 20, "callow": 4}
	b.merge(brood, true)
	var params := {"initial_fungus": 200, "brood_reserve": 5, "underground": {"size": [800, 800]}, "brood": b}
	params.merge(nest, true)
	var data := {"seed": seed_value, "colonies": [{"species": "leafcutter", "nest": [540, 1000],
			"population": population, "nest_params": params}]}
	return ScenarioLoader.build(data, _registry, _config)

func _nest(sim: Simulation) -> FungusNest:
	return sim.colonies[0].nest as FungusNest

func _run_seconds(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

func _count_state(sim: Simulation, state_id: String) -> int:
	var n := 0
	for i in sim.high_water:
		if sim.alive[i] != 0 and sim.state_id(i) == state_id:
			n += 1
	return n

func test_queen_is_a_real_ant_in_the_royal_chamber() -> void:
	var sim := _sim({"queen": 1})
	var nest := _nest(sim)
	var q := nest.queen_ant
	check(q >= 0 and sim.alive[q] != 0, "queen spawned")
	check_eq(sim.caste_of(q).id, &"queen", "queen caste")
	check_eq(sim.layer[q], nest.underground_layer, "underground")
	check_eq(sim.state_id(q), "queen", "queen state")
	check(sim.caste_of(q).size > 2.0 * sim.colonies[0].species.castes[2].size * 0.7, "much bigger than a worker")
	_run_seconds(sim, 30.0)
	check(sim.pos[q].distance_to(nest.queen_spot()) < 8.0, "stays at her spot (%s)" % sim.pos[q])
	check_eq(sim.colonies[0].population, 1, "the queen counts in the population")
	# Without "queen" in the population she is placed anyway.
	var auto := _sim({"minim": 2})
	auto.step()
	check(_nest(auto).queen_ant >= 0, "queen placed on the first tick")

## Brood only develops when cared for: with nobody to look after them eggs
## and pupae stall and larvae starve; with nurses they develop.
func test_care_is_required() -> void:
	var initial := {"initial": {"egg": 4, "larva": 4, "pupa": 3}}
	var sim := _sim({"queen": 1}, {}, initial.merged({"starve_time": 40, "egg": 200, "larva": 200, "pupa": 200}))
	var nest := _nest(sim)
	sim.remove_ant(nest.queen_ant)  # no queen, no workers: nobody cares
	var brood := nest.brood
	# Clean at first, they develop a little; once dirty (90 s) nothing moves.
	_run_seconds(sim, 100.0)
	var stages := brood.stage.duplicate()
	var ages := {}
	for k in brood.count():
		ages[brood.id[k]] = brood.age[k]
	var larvae := brood.count_stage(Stage.LARVA)
	var deaths := brood.deaths
	_run_seconds(sim, 90.0)
	check(brood.count_stage(Stage.EGG) + brood.count_stage(Stage.PUPA) + brood.count_stage(Stage.CALLOW) >= 6, "eggs and pupae still there")
	check_eq(brood.count_stage(Stage.LARVA), 0, "larvae starved")
	check_eq(brood.deaths, deaths + larvae, "every hungry larva died")
	check(brood.deaths >= 3, "starvation (%d)" % brood.deaths)
	check_eq(nest.ants_raised, 0, "nothing raised")
	for k in brood.count():
		check(brood.dirt[k] >= 1.0, "brood %d neglected" % k)
		var was := stages.find(brood.stage[k])
		check(was >= 0, "no stage changes once neglected")
	var grown := 0.0
	for k in brood.count():
		grown += absf(brood.age[k] - float(ages[brood.id[k]]))
	check(grown < 0.001, "development stopped (%.3f)" % grown)
	# The same brood with nurses develops.
	var cared := _sim({"queen": 1, "minim": 6}, {}, initial)
	_run_seconds(cared, 150.0)
	var b2 := _nest(cared).brood
	check(_nest(cared).ants_raised >= 4, "cared-for brood raised workers (%d)" % _nest(cared).ants_raised)
	check_eq(b2.deaths, 0, "no larva starved")
	check(_nest(cared).fed_mass > 0.0, "nurses fed larvae from the garden")

## The queen's eggs appear at her abdomen and nurses carry them to the egg pile.
func test_queen_egg_flow() -> void:
	var sim := _sim({"queen": 1, "minim": 5}, {"brood_rate": 1.0}, {"lay_interval": 2, "egg": 200})
	var nest := _nest(sim)
	var brood := nest.brood
	var q := nest.queen_ant
	var at_queen := 0
	var laid_near := true
	for t in 20 * _config.tick_rate:
		var before := brood.eggs_laid
		sim.step()
		if brood.eggs_laid > before:
			var k := brood.index_of(brood.lay_ids[(brood.eggs_laid - 1) % LeafcutterBrood.EVENT_LOG])
			laid_near = laid_near and brood.pos[k].distance_to(sim.pos[q]) < sim.caste_of(q).size
			at_queen += 1
	check(brood.eggs_laid >= 8, "the queen laid (%d)" % brood.eggs_laid)
	check(laid_near, "each egg appeared at the queen")
	brood.max_brood = brood.count()  # stop laying
	_run_seconds(sim, 30.0)
	var in_pile := 0
	for k in brood.count():
		if brood.stage[k] == Stage.EGG and brood.pile[k] == Pile.EGGS:
			in_pile += 1
	check(in_pile >= brood.count_stage(Stage.EGG) - 2, "nurses carried the eggs to the pile (%d of %d)" % [in_pile, brood.count_stage(Stage.EGG)])
	for k in brood.count():
		if brood.pile[k] == Pile.EGGS:
			check(brood.pos[k].distance_to(nest.pile_centre(Pile.EGGS)) < 15.0, "egg %d in the pile" % k)

## More brood, more nurses.
func test_nurse_assignment_scales_with_brood() -> void:
	var few := _sim({"queen": 1, "minim": 40}, {}, {"initial": {"egg": 2, "pupa": 2}})
	var many := _sim({"queen": 1, "minim": 40}, {}, {"initial": {"egg": 20, "larva": 20, "pupa": 20}, "max_brood": 200})
	_run_seconds(few, 10.0)
	_run_seconds(many, 10.0)
	var n_few := _count_state(few, "nurse")
	var n_many := _count_state(many, "nurse")
	check(n_few >= 1 and n_few <= 3, "a little brood, a nurse or two (%d)" % n_few)
	check(n_many >= 8, "lots of brood, many nurses (%d)" % n_many)
	check(_count_state(many, "tend_queen") >= 1, "a retinue for the queen")

## A sealed founding nest: the queen raises the first workers alone, they
## dig the entrance open, and foraging can begin.
func test_founding_sequence_opens_the_entrance() -> void:
	var sim := _sim({"queen": 1}, {"initial_fungus": 40, "open_entrance_at": 3,
			"underground": {"size": [800, 800], "open": false}},
			{"lay_interval": 12, "initial": {"egg": 2, "larva": 3}})
	var nest := _nest(sim)
	check(not nest.has_entrance(), "sealed")
	var first_worker := -1.0
	var opened := -1.0
	var queen_fed := false
	for t in 420 * _config.tick_rate:
		sim.step()
		if first_worker < 0.0 and nest.ants_raised > 0:
			first_worker = sim.time()
			queen_fed = nest.fed_mass > 0.0
		if nest.has_entrance():
			opened = sim.time()
			break
	check(first_worker > 0.0, "the queen raised a first worker (at %.0f s)" % first_worker)
	check(queen_fed, "fed the first larvae herself")
	check(opened > first_worker, "then the workers dug the entrance open (at %.0f s)" % opened)
	check(nest.packed_spoil > 0.0, "soil went into the walls while sealed")
	check(nest.workers_alive(sim) >= 3, "open_entrance_at workers")
	# Once open, workers come up and go out.
	_run_seconds(sim, 60.0)
	var surface := 0
	for i in sim.high_water:
		if sim.alive[i] != 0 and sim.layer[i] == 0:
			surface += 1
	check(surface > 0, "workers out on the surface (%d)" % surface)
	check(nest.spoil_items > 0 or nest.packed_spoil > 0.0, "spoil accounted for")

## Every callow becomes exactly one ant; population counts every agent.
func test_emergence_and_population_accounting() -> void:
	var sim := _sim({"queen": 1, "minim": 8}, {}, {"initial": {"pupa": 6}, "first_caste": 1, "first_workers": 100})
	var nest := _nest(sim)
	var brood := nest.brood
	_run_seconds(sim, 60.0)
	check_eq(brood.emerged, nest.ants_raised, "each emergence raised one ant")
	check(nest.ants_raised >= 6, "all six pupae came out (%d)" % nest.ants_raised)
	var alive := 0
	for i in sim.high_water:
		if sim.alive[i] != 0:
			alive += 1
	check_eq(sim.colonies[0].population, alive, "population = agents alive")
	check_eq(alive, 1 + 8 + nest.ants_raised, "queen + starting workers + raised")
	var ant := brood.emerge_ants[0]
	check(ant >= 0 and sim.alive[ant] != 0, "the logged ant exists")
	check_eq(sim.caste_of(ant).id, &"media", "first_caste sets the first workers' caste")
	# New workers who come up are pointed out on the surface.
	var highlighted := false
	for t in 120 * _config.tick_rate:
		sim.step()
		if nest.highlight_ant >= 0 and sim.layer[nest.highlight_ant] == 0:
			highlighted = true
			break
	check(highlighted, "a new worker came up and was highlighted")

func test_brood_care_is_deterministic() -> void:
	var a := _sim({"queen": 1, "minim": 10}, {"brood_rate": 1.0}, {"lay_interval": 3, "initial": {"egg": 3, "larva": 3, "pupa": 3}})
	var b := _sim({"queen": 1, "minim": 10}, {"brood_rate": 1.0}, {"lay_interval": 3, "initial": {"egg": 3, "larva": 3, "pupa": 3}})
	_run_seconds(a, 40.0)
	_run_seconds(b, 40.0)
	check_eq(a.state_hash(), b.state_hash(), "same run, same hash")
