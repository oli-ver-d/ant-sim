extends TestCase
## The native ant kernel (native/, NativeAnts): runs with it give exactly the
## results of the GDScript ants. Skipped (passing) when the extension isn't
## built.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

## Scenarios and fixtures compared, with how many ticks to run each.
const RUNS := {
	"basic_forage": 900,
	"chaos_to_highway": 600,
	"fungus_farm": 900,
	"leaf_strip": 600,
	"maze": 600,
	"rain_reset": 600,
	"trunk_trail": 600,
	"twig_bridge": 600,
	"two_species": 600,
	"colony_founding": 1500,
	"res://tests/fixtures/scenarios/dig_demo.json": 900,
	"res://tests/fixtures/scenarios/shapes_demo.json": 900,
	"res://tests/fixtures/scenarios/highway_demo.json": 900,
	"res://tests/fixtures/scenarios/brood_demo.json": 900,
	"res://tests/fixtures/scenarios/garden_demo.json": 900,
	"res://tests/fixtures/scenarios/nest_bench.json": 450,
}

func _native() -> bool:
	return NativeAnts.enabled and ClassDB.class_exists(&"AntKernel") and not OS.get_cmdline_user_args().has("--no-native")

## Runs a scenario `ticks` ticks with or without the kernel (and its grid
## helpers); returns the state hash every 150 ticks and at the end, and
## whether the kernel ran to the end.
func _run(scenario: String, ticks: int, native: bool) -> Dictionary:
	var was := NativeAnts.enabled
	NativeAnts.enabled = native
	var sim := ScenarioLoader.load_simulation(scenario, _registry, _config)
	var hashes: PackedStringArray = []
	for t in ticks:
		sim.step()
		if (t + 1) % 150 == 0 or t + 1 == ticks:
			hashes.append(sim.state_hash())
	NativeAnts.enabled = was
	return {"hashes": hashes, "native": sim.native != null}

## Runs `scenario` (a RUNS key) with and without the kernel and compares.
func _check_matches(scenario: String) -> void:
	if not _native():
		print("    (native kernel not built: skipped)")
		return
	var ticks: int = RUNS[scenario]
	var fast := _run(scenario, ticks, true)
	var slow := _run(scenario, ticks, false)
	check(fast["native"], "%s: the kernel ran to the end" % scenario)
	check_eq(fast["hashes"], slow["hashes"], "%s: native and GDScript state hashes" % scenario)

## Its name for a test: the scenario name, or a fixture's file name.
static func _matches_test(scenario: String) -> String:
	return "test_native_matches_gdscript_" + scenario.get_file().get_basename()

## One test per RUNS entry (so tools/test.sh can run them in parallel); every
## entry must have one.
func test_native_matches_gdscript_covers_every_run() -> void:
	for scenario: String in RUNS:
		check(has_method(_matches_test(scenario)), "%s() for %s" % [_matches_test(scenario), scenario])

func test_native_matches_gdscript_basic_forage() -> void: _check_matches("basic_forage")
func test_native_matches_gdscript_chaos_to_highway() -> void: _check_matches("chaos_to_highway")
func test_native_matches_gdscript_fungus_farm() -> void: _check_matches("fungus_farm")
func test_native_matches_gdscript_leaf_strip() -> void: _check_matches("leaf_strip")
func test_native_matches_gdscript_maze() -> void: _check_matches("maze")
func test_native_matches_gdscript_rain_reset() -> void: _check_matches("rain_reset")
func test_native_matches_gdscript_trunk_trail() -> void: _check_matches("trunk_trail")
func test_native_matches_gdscript_twig_bridge() -> void: _check_matches("twig_bridge")
func test_native_matches_gdscript_two_species() -> void: _check_matches("two_species")
func test_native_matches_gdscript_colony_founding() -> void: _check_matches("colony_founding")
func test_native_matches_gdscript_dig_demo() -> void: _check_matches("res://tests/fixtures/scenarios/dig_demo.json")
func test_native_matches_gdscript_shapes_demo() -> void: _check_matches("res://tests/fixtures/scenarios/shapes_demo.json")
func test_native_matches_gdscript_highway_demo() -> void: _check_matches("res://tests/fixtures/scenarios/highway_demo.json")
func test_native_matches_gdscript_brood_demo() -> void: _check_matches("res://tests/fixtures/scenarios/brood_demo.json")
func test_native_matches_gdscript_garden_demo() -> void: _check_matches("res://tests/fixtures/scenarios/garden_demo.json")
func test_native_matches_gdscript_nest_bench() -> void: _check_matches("res://tests/fixtures/scenarios/nest_bench.json")

## Ticks spread across frames (as when rendering) give the same run.
func test_native_split_ticks() -> void:
	if not _native():
		return
	var whole := ScenarioLoader.load_simulation("trunk_trail", _registry, _config)
	var split := ScenarioLoader.load_simulation("trunk_trail", _registry, _config)
	for t in 300:
		whole.step()
		split.begin_step()
		while not split.step_ants(37):
			pass
		split.end_step()
	check_eq(split.state_hash(), whole.state_hash(), "split ticks, same hash")
	check(split.native != null, "the kernel ran to the end")

## Live tuning between ticks reaches the kernel.
func test_native_follows_live_tuning() -> void:
	if not _native():
		return
	var hashes: PackedStringArray = []
	for native: bool in [true, false]:
		var config := _config.duplicate() as SimConfig
		config.resource_path = ""
		NativeAnts.enabled = native
		var sim := ScenarioLoader.load_simulation("basic_forage", _registry, config)
		NativeAnts.enabled = true
		for t in 300:
			sim.step()
			if t == 100:
				config.wander_strength *= 2.0
				config.sensor_distance *= 1.5
				sim.refresh_params()
		hashes.append(sim.state_hash())
	check_eq(hashes[0], hashes[1], "tuned mid-run: native and GDScript hashes")

## An entrance dug open during a tick reaches the kernel at once: surface
## ants updated later in the same tick already head for it (the "digger"
## species and entrance job of test_layers).
func test_native_sees_the_entrance_open() -> void:
	if not _native():
		return
	var registry: Registry = load("res://tests/test_layers.gd")._make_registry()
	var results: Array[Dictionary] = []
	for native: bool in [true, false]:
		NativeAnts.enabled = native
		var sim := Simulation.new(_config, registry, 1)
		NativeAnts.enabled = true
		sim.add_colony("digger", Vector2(540, 1200), {"underground": {"size": [400, 400], "shaft": [200, 200],
				"shaft_radius": 10, "open": false, "carve": [{"center": [200, 240], "radius": 14}],
				"plan": [{"name": "entrance", "origin": [200, 240], "from": [200, 226], "to": [200, 200], "radius": 7}]}})
		var colony := sim.colonies[0]
		for n in 4:
			sim.change_state(sim.spawn_ant(colony, 0, Vector2(200, 240), 0.0, 1), "dig")
		# Lingering on the surface, beyond their 80-unit radius of the entrance.
		for n in 6:
			sim.spawn_ant(colony, 0, Vector2(540, 1200) + Vector2.from_angle(n) * 120.0, n * 1.3)
		var opened_at := -1
		for t in 240 * _config.tick_rate:
			sim.step()
			if opened_at < 0 and colony.nest.has_entrance():
				opened_at = sim.tick_count
			if opened_at > 0 and sim.tick_count > opened_at + 60:
				break
		results.append({"opened_at": opened_at, "hash": sim.state_hash(), "native": sim.native != null})
	check(results[0]["opened_at"] > 0, "dug open")
	check(results[0]["native"], "the kernel ran to the end")
	check_eq(results[0]["opened_at"], results[1]["opened_at"], "opened on the same tick")
	check_eq(results[0]["hash"], results[1]["hash"], "native and GDScript hashes")

## The grid helpers give the same answers natively and in GDScript.
func test_grid_helpers_match() -> void:
	if not _native():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for trial in 20:
		var nx := rng.randi_range(1, 40)
		var ny := rng.randi_range(1, 30)
		var mask := PackedByteArray()
		mask.resize(nx * ny)
		for k in mask.size():
			mask[k] = 1 if rng.randf() < 0.6 else 0
		var points := PackedVector2Array()
		for k in rng.randi_range(0, 60):
			# Coarse coordinates so ties happen.
			points.append(Vector2(rng.randi_range(0, 20), rng.randi_range(0, 20)) * 0.5)
		var at := Vector2(rng.randf_range(-2.0, 12.0), rng.randf_range(-2.0, 12.0))
		var native_edges := NativeAnts.mask_edges(mask, nx, ny, 1)
		var native_near := NativeAnts.nearest_point(points, at)
		NativeAnts.enabled = false
		var gd_edges := NativeAnts.mask_edges(mask, nx, ny, 1)
		var gd_near := NativeAnts.nearest_point(points, at)
		NativeAnts.enabled = true
		check_eq(native_edges, gd_edges, "trial %d: mask edges" % trial)
		check_eq(native_near, gd_near, "trial %d: nearest point" % trial)
