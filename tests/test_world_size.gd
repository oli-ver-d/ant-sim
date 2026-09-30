extends TestCase
## M16j: a scenario's "world": {"size": [w, h]} sets the surface world (the
## wide_world fixture is 1920x1080); without it the config's world_size holds.

const WIDE := "res://tests/fixtures/scenarios/wide_world.json"

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _wide(seed_override: int = -1) -> Simulation:
	return ScenarioLoader.load_simulation(WIDE, _registry, _config, seed_override)

func _run(sim: Simulation, ticks: int) -> void:
	for t in ticks:
		sim.step()

func test_wide_world_builds_at_its_size() -> void:
	var sim := _wide()
	check_eq(sim.world.size, Vector2i(1920, 1080), "surface world size")
	check_eq(sim.layers[0].world.size, Vector2i(1920, 1080), "surface layer's world size")
	var p := sim.pheromones
	check_eq(Vector2i(p.width, p.height), Vector2i(1920 / p.cell_size, 1080 / p.cell_size), "pheromone grid from the world")
	check_eq(Vector2i(p.width, p.height), Vector2i(480, 270), "pheromone grid 480x270")
	check(sim.ground != null, "has a ground map")
	check_eq(sim.ground.size, Vector2i(1920 / int(GroundMap.TEXEL), 1080 / int(GroundMap.TEXEL)), "ground map from the world")
	check_eq(sim.ground.size, Vector2i(240, 135), "ground map 240x135")
	check_eq(_config.world_size, Vector2i(1080, 1920), "the shared config is untouched")

func test_wide_world_ants_use_the_whole_width() -> void:
	for seed_value: int in [4, 5, 6]:
		var sim := _wide(seed_value)
		_run(sim, 300)
		var far := 0
		for i in sim.pos.size():
			if sim.pos[i].x > 1080.0:
				far += 1
		check(far > 0, "seed %d: some ant beyond x = 1080 after 300 ticks (%d)" % [seed_value, far])

func test_wide_world_rain_covers_the_whole_world() -> void:
	var sim := _wide()
	check_eq(sim.rain.size(), 0, "no shower yet")
	_run(sim, 100)
	check_eq(sim.rain.size(), 1, "the shower has started (t = 3 s)")
	check_eq(sim.rain[0]["area"]["rect"], [0, 0, 1920, 1080], "no area = the whole world")

func test_wide_world_is_deterministic() -> void:
	var a := _wide()
	var b := _wide()
	_run(a, 200)
	_run(b, 200)
	check_eq(a.state_hash(), b.state_hash(), "same hash twice")

func test_world_size_defaults_to_the_config() -> void:
	var sim := ScenarioLoader.build({"seed": 1, "colonies": []}, _registry, _config)
	check_eq(sim.world.size, _config.world_size, "no world: config size")
	check_eq(sim.world.size, Vector2i(1080, 1920), "1080x1920")
	check_eq(Vector2i(sim.pheromones.width, sim.pheromones.height), Vector2i(270, 480), "pheromone grid 270x480")

func test_world_size_reads_the_scenario() -> void:
	check_eq(ScenarioLoader.world_size({"world": {"size": [1920, 1080]}}, _config), Vector2i(1920, 1080), "size")
	check_eq(ScenarioLoader.world_size({"world": {"size": [2160.0, 3840.0]}}, _config), Vector2i(2160, 3840), "float sizes")

func test_world_size_falls_back_on_missing_or_malformed() -> void:
	var default := _config.world_size
	var cases: Array[Dictionary] = [
		{},
		{"world": {}},
		{"world": "big"},
		{"world": {"size": 1920}},
		{"world": {"size": [1920]}},
		{"world": {"size": [1920, 1080, 5]}},
		{"world": {"size": ["a", "b"]}},
		{"world": {"size": [0, 1080]}},
		{"world": {"size": [-8, 1080]}},
		{"world": {"size": null}},
	]
	for data: Dictionary in cases:
		check_eq(ScenarioLoader.world_size(data, _config), default, "falls back for %s" % [data])
