extends TestCase
## M7: rain, bridges, narrow passages, detours, per-colony overrides, and the
## rain_reset / twig_bridge / maze scenarios.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _sim() -> Simulation:
	var sim := Simulation.new(_config, _registry, 1)
	sim.add_colony("leafcutter", Vector2(540, 1700))
	return sim

func _run_seconds(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

func test_wipe_scales_by_keep() -> void:
	var sim := _sim()
	var ch := sim.colonies[0].channels[&"home"]
	sim.pheromones.deposit(ch, Vector2(300, 300), 4.0)
	sim.pheromones.deposit(ch, Vector2(800, 300), 4.0)
	var v := sim.pheromones.sample(ch, Vector2(300, 300))
	sim.pheromones.wipe_rect(Rect2(200, 200, 200, 200), 0.25)
	check(absf(sim.pheromones.sample(ch, Vector2(300, 300)) - v * 0.25) < 1e-4, "inside scaled by keep")
	check(absf(sim.pheromones.sample(ch, Vector2(800, 300)) - v) < 1e-4, "outside untouched")
	sim.pheromones.wipe_circle(Vector2(300, 300), 20.0)
	check_eq(sim.pheromones.sample(ch, Vector2(300, 300)), 0.0, "keep 0 clears")

func test_rain_washes_out_gradually_and_is_remembered() -> void:
	var sim := _sim()
	sim.start_rain({}, 2.0, 0.5)
	var shower := sim.rain[0]
	check(absf(float(shower["keep"]) - pow(0.5, sim.dt / 0.5)) < 1e-6, "per-tick keep from the half-life")
	check_eq(shower["area"]["rect"], [0, 0, _config.world_size.x, _config.world_size.y], "no area = whole world")
	_run_seconds(sim, 3.0)
	check(not sim.rain_active(shower), "over after its duration")
	check_eq(sim.rain.size(), 1, "kept for renderers (drying ground)")

func test_bridge_carves_a_path_over_water() -> void:
	var data := {"seed": 1, "colonies": [], "obstacles": [
		{"shape": "rect", "kind": "water", "rect": [0, 900, 1080, 160]},
		{"shape": "polyline", "kind": "bridge", "points": [[300, 1100], [300, 860]], "width": 14},
	]}
	var sim := ScenarioLoader.build(data, _registry, _config)
	var world := sim.world
	check(world.line_clear(Vector2(300, 1090), Vector2(300, 870)), "walkable along the bridge")
	check(world.is_blocked(Vector2(330, 980)), "water beside the bridge")
	check(not world.line_clear(Vector2(600, 1090), Vector2(600, 870)), "no way across elsewhere")
	check_eq(world.bridges.size(), 1, "listed for rendering")
	check_eq(world.bridged.get(world.cell_at(Vector2(300, 980)), -1), World.Cell.WATER, "remembers water underneath")

func test_ants_walk_straight_through_a_narrow_passage() -> void:
	var sim := _sim()
	# A corridor 12 units (3 cells) wide along +x, from x=300 to x=450.
	sim.world.fill_rect(Rect2(300, 480, 150, 20), World.Cell.WALL)
	sim.world.fill_rect(Rect2(300, 512, 150, 20), World.Cell.WALL)
	sim.world.ensure_near_blocked(_config.avoid_lookahead)
	check_eq(Steering.avoid_turn(sim.world, Vector2(320, 506), 0.0, _config.avoid_lookahead), 0.0, "no avoidance in the corridor")
	var ant := sim.spawn_ant(sim.colonies[0], 1, Vector2(290, 506), 0.0)
	for t in 300:
		Steering.move(sim, ant, 0.0, 40.0, sim.dt)
		check(not sim.world.is_blocked(sim.pos[ant]), "never inside a wall")
		if sim.pos[ant].x > 460.0:
			break
	check(sim.pos[ant].x > 460.0, "came out the far end (x=%.0f)" % sim.pos[ant].x)

func test_sense_away_prefers_untrodden_ground_but_not_walls() -> void:
	var sim := _sim()
	var colony := sim.colonies[0]
	var ch := colony.channels[&"home"]
	var at := Vector2(500, 500)
	var fwd := Vector2(colony.sensor_distance, 0)
	sim.pheromones.deposit(ch, at + fwd, 1.0)
	sim.pheromones.deposit(ch, at + fwd.rotated(-colony.sensor_angle), 1.0)
	sim.pheromones.deposit(ch, at + fwd.rotated(colony.sensor_angle), 0.2)
	check_eq(Steering.sense_away(sim, ch, at, 0.0, colony), 1.0, "turns toward the weaker (right) side")
	sim.world.fill_circle(at + fwd.rotated(colony.sensor_angle), 3.0, World.Cell.WALL)
	check_eq(Steering.sense_away(sim, ch, at, 0.0, colony), 0.0, "a wall is not unexplored ground")

func test_colony_overrides_apply_to_that_colony_only() -> void:
	var data := {"seed": 1, "colonies": [
		{"species": "leafcutter", "nest": [300, 1600]},
		{"species": "leafcutter", "nest": [800, 1600],
		 "params": {"deposit_half_life": 60},
		 "state_params": {"explore": {"give_up_after": 90, "avoid_channel": "home"}},
		 "channels": {"home": {"reinforce": 0.0}}},
	]}
	var sim := ScenarioLoader.build(data, _registry, _config)
	var plain := sim.colonies[0]
	var tuned := sim.colonies[1]
	var media := plain.species.caste_index(&"media")
	var explore := sim.behaviour_index["explore"]
	check_eq(tuned.params[&"deposit_half_life"], 60, "param override")
	check(plain.params[&"deposit_half_life"] != 60, "other colony keeps the default")
	check_eq(tuned.params_for(media, explore).get("give_up_after"), 90, "state param override")
	check_eq(tuned.params_for(media, explore).get("avoid_channel"), tuned.channels[&"home"], "channel names resolved")
	check_eq(plain.params_for(media, explore).get("avoid_channel", -1), -1, "other colony unchanged")
	check_eq(sim.pheromones.reinforce[tuned.channels[&"home"]], 0.0, "channel override")
	check(sim.pheromones.reinforce[plain.channels[&"home"]] > 0.0, "other colony's channel unchanged")
	check(plain.species.channels[0].reinforce > 0.0, "species resource not modified")

# --- Scenarios --------------------------------------------------------------

## Runs a scenario, checking every second that no ant is inside an obstacle.
func _run_checked(sim: Simulation, seconds: float) -> int:
	var worst := 0
	for t in roundi(seconds * _config.tick_rate):
		sim.step()
		if t % _config.tick_rate == 0:
			worst = maxi(worst, SimChecks.ants_in_obstacles(sim))
	return worst

## rain_reset: the downpour washes the trail out; the colony rebuilds it
## while carriers already out keep bringing leaf home.
func test_rain_reset_trail_washes_out_and_rebuilds() -> void:
	var sim := ScenarioLoader.load_simulation("rain_reset", _registry, _config)
	var colony := sim.colonies[0]
	var food := colony.channels[&"food"]
	_run_seconds(sim, 142.0)
	var before := sim.pheromones.total(food)
	var delivered_before := colony.delivered_items
	_run_seconds(sim, 8.0)  # rain from 143 to 149 s
	var after_rain := sim.pheromones.total(food)
	check(after_rain < before * 0.2, "trail washed out (%.0f -> %.0f)" % [before, after_rain])
	_run_seconds(sim, 35.0)
	var rebuilt := sim.pheromones.total(food)
	check(rebuilt > before * 0.5, "trail rebuilt 35 s later (%.0f of %.0f)" % [rebuilt, before])
	check(colony.delivered_items > delivered_before + 50, "deliveries continued (%d -> %d)" % [delivered_before, colony.delivered_items])
	check(absf(SimChecks.mass_error(sim)) < 0.001, "food mass conserved")

## twig_bridge: the only way to the leaf is over the twig.
func test_twig_bridge_colony_crosses_the_stream() -> void:
	var sim := ScenarioLoader.load_simulation("twig_bridge", _registry, _config)
	var in_obstacles := _run_checked(sim, 180.0)
	check_eq(in_obstacles, 0, "no ant ever in the water")
	check(sim.colonies[0].delivered_items >= 100, "leaf carried over the bridge (%d delivered)" % sim.colonies[0].delivered_items)
	check(absf(SimChecks.mass_error(sim)) < 0.001, "food mass conserved")

## maze: explorers find the gaps; a trail forms through them.
func test_maze_colony_finds_its_way_through() -> void:
	var sim := ScenarioLoader.load_simulation("maze", _registry, _config)
	var in_obstacles := _run_checked(sim, 280.0)
	check_eq(in_obstacles, 0, "no ant ever in a wall")
	check(sim.colonies[0].delivered_items >= 50, "leaf delivered through the maze (%d)" % sim.colonies[0].delivered_items)
