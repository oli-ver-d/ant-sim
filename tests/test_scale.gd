extends TestCase
## M11d: agents capped per layer, the abstract population beyond them, the
## pools staying representative, and the colony_founding scenario.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _sim(population: Dictionary, caps: Dictionary, brood: Dictionary = {}, seed_value: int = 5) -> Simulation:
	var b := {"lay_interval": 1000, "egg": 20, "larva": 30, "pupa": 10, "callow": 2}
	b.merge(brood, true)
	var data := {"seed": seed_value, "max_agents": caps,
		"colonies": [{"species": "leafcutter", "nest": [540, 1000], "population": population,
			"nest_params": {"initial_fungus": 300, "brood_reserve": 5, "initial_chambers": 2,
				"underground": {"size": [900, 900]}, "brood": b}}]}
	return ScenarioLoader.build(data, _registry, _config)

func _run_seconds(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

func _agents_on(sim: Simulation, l: int) -> int:
	var n := 0
	for i in sim.high_water:
		if sim.alive[i] != 0 and sim.layer[i] == l:
			n += 1
	return n

## Brood emerging into a full nest joins the abstract population; the
## colony's size counts everyone.
func test_full_layer_grows_the_abstract_population() -> void:
	var sim := _sim({"queen": 1, "minim": 20}, {"nest": 22}, {"initial": {"pupa": 12}})
	var colony := sim.colonies[0]
	var nest := colony.nest as FungusNest
	_run_seconds(sim, 70.0)
	check(nest.ants_raised >= 12, "all pupae emerged (%d)" % nest.ants_raised)
	check(colony.abstract > 0, "some joined the abstract population (%d)" % colony.abstract)
	check_eq(colony.total_population(), colony.population + colony.abstract, "total = agents + abstract")
	check_eq(colony.total_population(), 1 + 20 + nest.ants_raised, "everyone counted")
	var nest_layer := nest.underground_layer
	check(_agents_on(sim, nest_layer) <= 22, "the nest holds at most its cap (%d)" % _agents_on(sim, nest_layer))
	check_eq(sim.layer_agents[nest_layer], _agents_on(sim, nest_layer), "per-layer agent count kept up to date")
	check_eq(sim.layer_agents[0], _agents_on(sim, 0), "surface count too")

## Over a cap, idle agents move to the abstract population; with room again
## they come back.
func test_pools_move_agents_out_and_back() -> void:
	var sim := _sim({"queen": 1, "minim": 60, "media": 40}, {})
	var colony := sim.colonies[0]
	var nest := colony.nest as FungusNest
	_run_seconds(sim, 5.0)
	var total := colony.total_population()
	sim.set_max_agents(nest.underground_layer, 25)
	_run_seconds(sim, 20.0)
	check(_agents_on(sim, nest.underground_layer) <= 25, "cut down to the cap (%d)" % _agents_on(sim, nest.underground_layer))
	check(colony.abstract > 0, "into the abstract population (%d)" % colony.abstract)
	check_eq(colony.total_population(), total, "nobody lost")
	check(sim.alive[nest.queen_ant] != 0, "never the queen")
	sim.set_max_agents(nest.underground_layer, 0)
	sim.set_max_agents(0, 0)
	var before := colony.abstract
	sim.set_max_agents(nest.underground_layer, 200)
	_run_seconds(sim, 10.0)
	check(colony.abstract < before, "room again: back as agents (%d -> %d)" % [before, colony.abstract])
	check_eq(colony.total_population(), total, "still nobody lost")

## With a full layer, swaps keep the agents' castes in proportion.
func test_agents_stay_representative() -> void:
	var sim := _sim({"queen": 1, "minim": 40, "media": 40}, {"surface": 30, "nest": 30})
	var colony := sim.colonies[0]
	# Lots of abstract medias, few abstract minims.
	colony.abstract_by_caste[1] += 300
	colony.abstract_by_caste[0] += 20
	colony.abstract += 320
	_run_seconds(sim, 60.0)
	var media_total := float(colony.total_of_caste(1)) / colony.total_population()
	var media_agents := float(colony.population_by_caste[1]) / maxf(1.0, colony.population - 1)
	check(absf(media_agents - media_total) < 0.2, "media share of agents %.2f close to the colony's %.2f" % [media_agents, media_total])

func test_pools_are_deterministic() -> void:
	var a := _sim({"queen": 1, "minim": 30, "media": 30}, {"surface": 20, "nest": 20}, {"initial": {"pupa": 10}})
	var b := _sim({"queen": 1, "minim": 30, "media": 30}, {"surface": 20, "nest": 20}, {"initial": {"pupa": 10}})
	_run_seconds(a, 30.0)
	_run_seconds(b, 30.0)
	check_eq(a.state_hash(), b.state_hash(), "same run, same hash")

func test_colony_founding_scenario() -> void:
	var data := ScenarioLoader.load_data("colony_founding")
	var sim := ScenarioLoader.build(data, _registry, _config)
	var nest := sim.colonies[0].nest as FungusNest
	check(nest.underground_layer >= 0, "a nest that digs")
	check(not nest.has_entrance(), "sealed at the start")
	check_eq(sim.colonies[0].population, 5, "the queen and four minims")
	check(sim.layers[0].max_agents > 0 and sim.layers[nest.underground_layer].max_agents > 0, "agent caps")
	var cams: Dictionary = data["camera"]
	check(cams.has("surface") and cams.has("nest"), "a camera for each part")
	var fit := false
	for kf: Dictionary in cams["nest"]:
		fit = fit or str(kf.get("fit", "")) == "excavation"
	check(fit, "the nest camera follows the excavation")
