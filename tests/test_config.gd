extends TestCase

func test_default_config_loads() -> void:
	var config := load("res://sim/default_config.tres") as SimConfig
	check(config != null, "default_config.tres should load as SimConfig")
	if config == null:
		return
	check_eq(config.world_size, Vector2i(1080, 1920), "world size")
	check_eq(config.grid_size(), Vector2i(270, 480), "grid size")
	check(config.tick_rate > 0, "tick_rate must be positive")

## M16j: a scenario's world size lives on the Simulation, not the config, so the tuning
## panel's Save (which writes sim.config) never writes it.
func test_scenario_world_leaves_config_world_size() -> void:
	var config := (load("res://sim/default_config.tres") as SimConfig).duplicate() as SimConfig
	config.resource_path = ""
	var sim := Simulation.new(config, Registry.create_default(), 1, Vector2i(1920, 1080))
	check_eq(sim.world.size, Vector2i(1920, 1080), "the sim has the scenario's world")
	check_eq(sim.config.world_size, Vector2i(1080, 1920), "the config keeps the default")
	var path := "user://test_saved_config.tres"
	check_eq(ResourceSaver.save(sim.config, path), OK, "saved")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SimConfig
	check(loaded != null, "reloads as a SimConfig")
	if loaded != null:
		check_eq(loaded.world_size, Vector2i(1080, 1920), "saved world_size is the default")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_get_param_prefers_overrides() -> void:
	var config := SimConfig.new()
	check_eq(config.get_param(&"sensor_distance"), config.sensor_distance, "no override")
	check_eq(config.get_param(&"sensor_distance", {&"sensor_distance": 20.0}), 20.0, "override")
