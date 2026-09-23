extends TestCase
## Scenario system: timed events and playback schedules.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _base_data() -> Dictionary:
	return {
		"seed": 5,
		"colonies": [{"species": "leafcutter", "nest": [540, 1400], "population": {"media": 20}}],
		"food": [],
	}

func _run_seconds(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

func test_spawn_food_event() -> void:
	var data := _base_data()
	data["events"] = [{"t": 1.0, "type": "spawn_food", "food": {"type": "food_pile", "pos": [540, 800], "amount": 10}}]
	var sim := ScenarioLoader.build(data, _registry, _config)
	_run_seconds(sim, 0.9)
	check_eq(sim.food_sources.size(), 0, "no food before t=1")
	_run_seconds(sim, 0.2)
	check_eq(sim.food_sources.size(), 1, "food spawned at t=1")

func test_obstacle_events() -> void:
	var data := _base_data()
	var wall := {"shape": "rect", "rect": [100, 100, 40, 40]}
	data["events"] = [
		{"t": 0.5, "type": "add_obstacle", "obstacle": wall},
		{"t": 1.5, "type": "remove_obstacle", "obstacle": wall},
	]
	var sim := ScenarioLoader.build(data, _registry, _config)
	_run_seconds(sim, 1.0)
	check(sim.world.is_blocked(Vector2(120, 120)), "wall added")
	_run_seconds(sim, 1.0)
	check(not sim.world.is_blocked(Vector2(120, 120)), "wall removed")

func test_rain_wipes_pheromones_in_area_while_active() -> void:
	var data := _base_data()
	data["events"] = [{"t": 1.0, "type": "rain", "duration": 2.0, "area": {"center": [300, 300], "radius": 100}}]
	var sim := ScenarioLoader.build(data, _registry, _config)
	var ch := sim.colonies[0].channels[&"home"]
	sim.pheromones.deposit(ch, Vector2(300, 300), 5.0)
	sim.pheromones.deposit(ch, Vector2(800, 300), 5.0)
	_run_seconds(sim, 1.5)
	check_eq(sim.pheromones.sample(ch, Vector2(300, 300)), 0.0, "rain wiped its area")
	check(sim.pheromones.sample(ch, Vector2(800, 300)) > 0.0, "outside the rain untouched")
	check(sim.rain_active(sim.rain[0]), "rain active")
	_run_seconds(sim, 2.0)
	check(not sim.rain_active(sim.rain[0]), "rain over")

func test_add_colony_event() -> void:
	var data := _base_data()
	data["events"] = [{"t": 0.5, "type": "add_colony", "colony": {"species": "harvester", "nest": [300, 900], "population": {"minor": 5}}}]
	var sim := ScenarioLoader.build(data, _registry, _config)
	_run_seconds(sim, 1.0)
	check_eq(sim.colonies.size(), 2, "second colony added")
	check_eq(sim.colonies[1].population, 5, "with its population")

func test_events_are_deterministic() -> void:
	var data := _base_data()
	data["events"] = [
		{"t": 0.5, "type": "spawn_food", "food": {"type": "food_pile", "pos": [540, 1100], "amount": 30}},
		{"t": 2.0, "type": "rain", "duration": 1.0, "area": {"rect": [0, 900, 1080, 400]}},
	]
	var a := ScenarioLoader.build(data, _registry, _config)
	var b := ScenarioLoader.build(data, _registry, _config)
	_run_seconds(a, 4.0)
	_run_seconds(b, 4.0)
	check_eq(a.state_hash(), b.state_hash(), "same scenario with events, same state")

func test_ticks_per_frame_schedule_ramps() -> void:
	var player := ScenarioPlayer.new()
	player._parse_tpf([{"t": 0, "tpf": 0.5}, {"t": 2, "tpf": 0.5}, {"t": 4, "tpf": 4.5}])
	check_eq(player.ticks_per_frame_at(1.0), 0.5, "hold")
	check(absf(player.ticks_per_frame_at(3.0) - 2.5) < 1e-5, "linear ramp midway")
	check_eq(player.ticks_per_frame_at(10.0), 4.5, "after last point")
	player._parse_tpf(2)
	check_eq(player.ticks_per_frame_at(5.0), 2.0, "constant number")
	player.free()

func test_camera_easing() -> void:
	for kind: String in ["linear", "in", "out", "in_out"]:
		check(absf(CameraDirector._ease(0.0, kind)) < 1e-6, "%s starts at 0" % kind)
		check(absf(CameraDirector._ease(1.0, kind) - 1.0) < 1e-6, "%s ends at 1" % kind)
	check(absf(CameraDirector._ease(0.5, "in_out") - 0.5) < 1e-6, "in_out is symmetric")

func test_gradual_release() -> void:
	var data := _base_data()
	data["colonies"] = [{"species": "leafcutter", "nest": [540, 1400], "population": {"minim": 10, "media": 20}, "release_per_second": 10}]
	var sim := ScenarioLoader.build(data, _registry, _config)
	check_eq(sim.colonies[0].population, 0, "everyone starts inside")
	_run_seconds(sim, 1.0)
	check(absi(sim.colonies[0].population - 10) <= 1, "about 10 out after 1 s (got %d)" % sim.colonies[0].population)
	_run_seconds(sim, 3.0)
	check_eq(sim.colonies[0].population, 30, "all out after 3 s")
	check_eq(sim.colonies[0].population_by_caste[0], 10, "caste counts preserved")
