extends TestCase
## M17e: alates and the nuptial flight (nest_params "alates", Alates): past a
## population the queen's brood includes gynes and males, which wait in the
## nest until a "nuptial_flight" event; then they walk up, gather on the
## mound with workers escorting them, take off one by one and leave the
## world. Off (no "alates"), nothing changes.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

## An established, open leafcutter nest with plenty of workers; `alates`
## params (null: none), extra starting castes and timed events.
func _nest_sim(alates: Variant, extra: Dictionary = {}, events: Array = [], seed_value: int = 5) -> Simulation:
	var population := {"queen": 1, "minim": 30, "media": 30, "major": 6}
	population.merge(extra, true)
	var params := {"initial_fungus": 600, "initial_chambers": 2, "max_chambers": 4,
		"underground": {"size": [1000, 1000], "royal_radius": 40},
		"brood": {"lay_interval": 2, "egg": 20, "larva": 30, "pupa": 20, "callow": 4,
			"initial": {"egg": 2, "larva": 2, "pupa": 2}}}
	if alates is Dictionary:
		params["alates"] = alates
	var data := {"seed": seed_value, "colonies": [{"species": "leafcutter", "nest": [540, 1000],
		"population": population, "nest_params": params}], "events": events,
		"food": [{"type": "leaf", "pos": [640, 800], "rotation": -25, "length": 250, "width": 120}]}
	return ScenarioLoader.build(data, _registry, _config)

func _nest(sim: Simulation) -> ColonyNest:
	return sim.colonies[0].nest as ColonyNest

func _count_state(sim: Simulation, s: String) -> int:
	var n := 0
	for i in sim.high_water:
		if sim.alive[i] != 0 and sim.state_id(i) == s:
			n += 1
	return n

func _step(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

func test_brood_raises_alates_past_the_population() -> void:
	var sim := _nest_sim({"from_population": 0, "count": 6, "castes": {"gyne": 1, "male": 2}})
	var nest := _nest(sim)
	var species := sim.colonies[0].species
	_step(sim, 200.0)
	check_eq(nest.alates.raised, 6, "six eggs chosen as alates")
	var gynes := sim.colonies[0].total_of_caste(species.caste_index(&"gyne"))
	var males := sim.colonies[0].total_of_caste(species.caste_index(&"male"))
	check(gynes + males >= 3, "alates emerged: %d gynes, %d males" % [gynes, males])
	check_eq(nest.alates.alive_count(), gynes + males, "every one is an alate")
	check_eq(nest.alates.raised_by, PackedInt32Array([2, 4]), "one gyne to two males")
	for i in nest.alates.ants:
		check_eq(sim.state_id(i), "alate", "state")
		check_eq(sim.layer[i], nest.underground_layer, "waiting in the nest")
	check_eq(nest.alates.flown, 0, "none flown without a flight")

func test_no_alates_below_the_population() -> void:
	var sim := _nest_sim({"from_population": 5000, "count": 6})
	_step(sim, 120.0)
	check_eq(_nest(sim).alates.raised, 0, "none chosen")

func test_nuptial_flight() -> void:
	var sim := _nest_sim({"gather": 6, "every": 1.0, "climb": 4, "escort": 5},
		{"gyne": 2, "male": 4}, [{"t": 5, "type": "nuptial_flight", "colony": 0}])
	var nest := _nest(sim)
	var a := nest.alates
	_step(sim, 1.0)
	check_eq(a.alive_count(), 6, "six alates from the population")
	check(not a.flying, "no flight yet")
	var most_out := 0
	var most_escorts := 0
	var highest := 0.0
	var winged_max := 0
	var gone_at := INF
	for t in roundi(150.0 * _config.tick_rate):
		sim.step()
		var out := 0
		for i in a.ants:
			if sim.layer[i] == 0:
				out += 1
		most_out = maxi(most_out, out)
		most_escorts = maxi(most_escorts, _count_state(sim, "escort"))
		var w := nest.winged_ants(sim)
		winged_max = maxi(winged_max, w.size())
		for i: int in w:
			highest = maxf(highest, w[i].y)
		if a.flown == 6 and gone_at == INF:
			gone_at = sim.time()
	check(most_out >= 3, "gathered on the mound together: %d" % most_out)
	check(most_escorts >= 3, "workers escorted them: %d" % most_escorts)
	check_eq(winged_max, 6, "all drawn with wings")
	check(highest > 200.0, "climbed: %.0f" % highest)
	check_eq(a.flown, 6, "all flew")
	check_eq(a.flown_by, PackedInt32Array([2, 4]), "by caste")
	check(gone_at < 90.0, "gone by %.1f s" % gone_at)
	check_eq(a.alive_count(), 0, "none left")
	check(not a.flying, "flight over")
	check_eq(_count_state(sim, "escort"), 0, "escorts back to work")
	check(sim.colonies[0].population >= 67, "the workers and queen stay: %d" % sim.colonies[0].population)
	check_eq(sim.alive[nest.queen_ant], 1, "the queen stays")

func test_alates_emerging_after_a_flight_wait_for_the_next() -> void:
	var sim := _nest_sim({"gather": 4, "climb": 3}, {"male": 2}, [{"t": 2, "type": "nuptial_flight"}])
	var a := _nest(sim).alates
	_step(sim, 60.0)
	check_eq(a.flown, 2, "first flight")
	var sp := sim.colonies[0].species
	var m := sim.spawn_ant(sim.colonies[0], sp.caste_index(&"male"), _nest(sim).queen_spot(), 0.0, _nest(sim).underground_layer)
	_step(sim, 20.0)
	check_eq(sim.state_id(m), "alate", "a new male")
	check_eq(sim.layer[m], _nest(sim).underground_layer, "waits in the nest")
	check(_nest(sim).start_nuptial_flight(sim), "another flight")
	_step(sim, 60.0)
	check_eq(a.flown, 3, "flew in the second")

func test_flight_is_deterministic() -> void:
	var hashes: Array[String] = []
	for n in 2:
		var sim := _nest_sim({"gather": 4, "climb": 3}, {"gyne": 1, "male": 2}, [{"t": 3, "type": "nuptial_flight"}])
		_step(sim, 40.0)
		hashes.append(sim.state_hash())
	check_eq(hashes[0], hashes[1], "same run, same hash")

func test_off_without_params() -> void:
	var sim := _nest_sim(null, {}, [{"t": 2, "type": "nuptial_flight"}])
	_step(sim, 60.0)
	check(_nest(sim).alates == null, "no alates")
	var sp := sim.colonies[0].species
	check_eq(sim.colonies[0].total_of_caste(sp.caste_index(&"gyne")) + sim.colonies[0].total_of_caste(sp.caste_index(&"male")), 0, "none raised")
	check(not sim.colonies[0].allows(sp.caste_index(&"major"), sim.behaviour_index["escort"]), "no escort state")
	check(not sim.colonies[0].allows(sp.caste_index(&"gyne"), sim.behaviour_index["alate"]), "no alate state")

func test_alate_castes_left_out_of_hashed_castes() -> void:
	var sp: SpeciesDef = _registry.species["leafcutter"]
	check_eq(sp.hashed_castes(), sp.caste_index(&"gyne"), "castes before the first alate")
	check_eq(sp.castes[sp.hashed_castes() - 1].id, &"queen", "the queen is the last hashed")
