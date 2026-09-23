extends TestCase

func test_default_config_loads() -> void:
	var config := load("res://sim/default_config.tres") as SimConfig
	check(config != null, "default_config.tres should load as SimConfig")
	if config == null:
		return
	check_eq(config.world_size, Vector2i(1080, 1920), "world size")
	check_eq(config.grid_size(), Vector2i(270, 480), "grid size")
	check(config.tick_rate > 0, "tick_rate must be positive")

func test_get_param_prefers_overrides() -> void:
	var config := SimConfig.new()
	check_eq(config.get_param(&"sensor_distance"), config.sensor_distance, "no override")
	check_eq(config.get_param(&"sensor_distance", {&"sensor_distance": 20.0}), 20.0, "override")
