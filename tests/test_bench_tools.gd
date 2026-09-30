extends TestCase
## The measurement hooks (M18a): Profiler timers, per-state timing of ant
## updates (bench.gd --by-state). Off, they record nothing; on, they don't
## change the simulation, and the kernel and GDScript attribute ant updates to
## states the same way.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

const LAYERED := "res://tests/fixtures/scenarios/nest_bench.json"

func _native() -> bool:
	return NativeAnts.enabled and ClassDB.class_exists(&"AntKernel") and not OS.get_cmdline_user_args().has("--no-native")

## Runs `scenario` `ticks` ticks; with `profile` Profiler and per-state timing
## are on. Returns the hash, the state profile and the ants' total time.
func _run(scenario: String, ticks: int, profile: bool, native: bool) -> Dictionary:
	var was := NativeAnts.enabled
	NativeAnts.enabled = native
	Profiler.reset()
	Profiler.on = profile
	var sim := ScenarioLoader.load_simulation(scenario, _registry, _config)
	sim.set_state_profiling(profile)
	for t in ticks:
		sim.step()
	var result := {"hash": sim.state_hash(), "prof": sim.take_state_profile(),
			"ants_us": sim.profile_usec["ants"], "keys": Profiler.usec.size(), "native": sim.kernel != null}
	sim.set_state_profiling(false)
	Profiler.on = false
	Profiler.reset()
	NativeAnts.enabled = was
	return result

func test_profiler_off_records_nothing() -> void:
	Profiler.on = false
	Profiler.reset()
	check_eq(Profiler.start(), 0, "start() is 0 while off")
	Profiler.stop("x", 0)
	var r := _run(LAYERED, 60, false, _native())
	check_eq(r["keys"], 0, "no Profiler key recorded while off (load and nest updates)")
	var ticks: PackedInt64Array = r["prof"]["ticks"]
	var n := 0
	for v in ticks:
		n += v
	check_eq(n, 0, "no ant update timed by state while off")

func test_profiler_on_records_load_and_nest_parts() -> void:
	Profiler.reset()
	Profiler.on = true
	var sim := ScenarioLoader.load_simulation(LAYERED, _registry, _config)
	for t in 30:
		sim.step()
	Profiler.on = false
	for key: String in ["load: read json", "load: colonies", "nest.update", "nest.update: brood", "step.nav_grid"]:
		check(Profiler.usec.has(key), "Profiler has %s" % key)
	check_eq(Profiler.calls.get("nest.update", 0), 30, "nest.update timed once per tick")
	Profiler.reset()

## Timing by state doesn't change the run.
func test_state_profiling_keeps_hash_single_layer() -> void:
	check_eq(_run("basic_forage", 300, true, _native())["hash"], _run("basic_forage", 300, false, _native())["hash"])

func test_state_profiling_keeps_hash_layered() -> void:
	check_eq(_run(LAYERED, 90, true, _native())["hash"], _run(LAYERED, 90, false, _native())["hash"])

## The kernel counts an update where GDScript would: same counts per state.
func test_state_counts_match_gdscript() -> void:
	if not _native():
		return
	var a := _run(LAYERED, 90, true, true)
	var b := _run(LAYERED, 90, true, false)
	check(a["native"] and not b["native"], "one run each way")
	check_eq(a["hash"], b["hash"], "same run")
	check_eq(a["prof"]["ticks"], b["prof"]["ticks"], "same ant updates per state")

## The states' times add up to most of the ants' total (the rest is the loop
## and the kernel calls round them), never more. Bounds are loose: the suite
## runs tests side by side.
func test_state_times_add_up() -> void:
	var r := _run(LAYERED, 90, true, _native())
	var us: PackedFloat64Array = r["prof"]["usec"]
	var sum := 0.0
	for v in us:
		sum += v
	var ants_us: float = r["ants_us"]
	check(sum <= ants_us * 1.01, "states %.0f us within the ants' %.0f us" % [sum, ants_us])
	check(sum >= ants_us * 0.6, "states %.0f us are most of the ants' %.0f us" % [sum, ants_us])
