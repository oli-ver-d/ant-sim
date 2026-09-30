class_name ScenarioLoader
extends RefCounted
## Builds a Simulation from a JSON scenario file (res://scenarios/<name>.json).
##
## Simulation content (used here):
##   "seed": 1,
##   "colonies":  [{"species": "...", "nest": [x, y], "nest_params": {}, "population": {"<caste>": n}}],
##   "food":      [{"type": "food_pile", "pos": [x, y], ...type params}],
##   "obstacles": [shape, ...]              (see ScenarioEvents for shapes)
##   "ground":    {"base": "soil", "regions": [...]}   surface materials (see GroundMap)
##   "scenery":   [{"type": "rock" | "log" | "plant" | "grass", ...}]   surface props
##                (see Scenery and the PropType scripts in sim/scenery), or
##                {"scatter": {"preset": "meadow", ...}} (see Scatter; placed after the colonies)
##   "debris":    [{"type": "twig" | "pebble", "pos": [x, y], ...}]  (see Debris)
##   "events":    [{"t": seconds, "type": ..., ...}]   (see ScenarioEvents)
##   "max_agents": {"surface": n, "nest": n}   agents per layer, beyond which
##                colonies grow as an abstract population (Simulation.balance_pools)
##
## Playback settings (used by ScenarioPlayer, not the simulation):
##   "duration": video seconds,
##   "warmup": simulated seconds to run before the first frame,
##   "ticks_per_frame": 0.5 | [{"t": video s, "tpf": 0.5}, ...]  (ramped linearly),
##   "camera": [{"t": video s, "pos": [x, y] | "follow": {...}, "zoom": 1, "ease": "in_out"}, ...]

const SCENARIO_DIR := "res://scenarios"

static func path_for(scenario_name: String) -> String:
	if scenario_name.begins_with("res://") or scenario_name.ends_with(".json"):
		return scenario_name
	return SCENARIO_DIR.path_join(scenario_name + ".json")

static func load_data(scenario_name: String) -> Dictionary:
	var path := path_for(scenario_name)
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("Scenario %s is missing or not valid JSON" % path)
		return {}
	return data

## seed_override < 0 uses the scenario's own seed.
static func build(data: Dictionary, registry: Registry, config: SimConfig, seed_override: int = -1) -> Simulation:
	var sim := build_base(data, registry, config, seed_override)
	add_scatters(sim, data)
	finish(sim, data)
	return sim

## build() in stages, so the editor can redo the ground and the scatters of a
## built sim without the rest: build_base (everything up to the scatters),
## add_scatters, finish.
static func build_base(data: Dictionary, registry: Registry, config: SimConfig, seed_override: int = -1) -> Simulation:
	var seed_value: int = seed_override if seed_override >= 0 else int(data.get("seed", 1))
	var p := Profiler.start()
	var sim := Simulation.new(config, registry, seed_value, world_size(data, config))
	Profiler.stop("load: simulation", p)
	p = Profiler.start()
	for ob: Dictionary in data.get("obstacles", []):
		ScenarioEvents.place_obstacle(sim, ob)
	Profiler.stop("load: obstacles", p)
	p = Profiler.start()
	set_ground(sim, data)
	Profiler.stop("load: ground", p)
	for prop: Dictionary in data.get("scenery", []):
		if not prop.has("scatter"):
			p = Profiler.start()
			ScenarioEvents.add_scenery(sim, prop)
			Profiler.stop("load: scenery %s" % prop.get("type", "?"), p)
	p = Profiler.start()
	for food: Dictionary in data.get("food", []):
		sim.add_food_source(food["type"], food)
	Profiler.stop("load: food", p)
	p = Profiler.start()
	for d: Dictionary in data.get("debris", []):
		Debris.create(sim, d)
	Profiler.stop("load: debris", p)
	p = Profiler.start()
	for col: Dictionary in data.get("colonies", []):
		ScenarioEvents.add_colony(sim, col)
	Profiler.stop("load: colonies", p)
	return sim

## The surface GroundMap from data["ground"] (none without it).
static func set_ground(sim: Simulation, data: Dictionary) -> void:
	sim.ground = null
	if data.has("ground"):
		sim.ground = GroundMap.from_data(data["ground"], Vector2(sim.world.size), sim.scenery.seed_value)

## The surface world size of scenario `data`: its "world": {"size": [w, h]}, else
## config.world_size. Sizes that are not two positive numbers fall back too (the
## editor's validator reports them).
static func world_size(data: Dictionary, config: SimConfig) -> Vector2i:
	var world: Variant = data.get("world")
	if world is Dictionary:
		var s: Variant = (world as Dictionary).get("size")
		if s is Array and (s as Array).size() == 2 and (s[0] is float or s[0] is int) \
				and (s[1] is float or s[1] is int) and s[0] > 0 and s[1] > 0:
			return Vector2i(int(s[0]), int(s[1]))
	return config.world_size

## Scatters keep clear of the nests and food, so they come last. Returns each
## scatter's Scatter.Result by its index in data["scenery"]. The editor redoes
## only the scatters from index `from` on, and gets each one's
## Scenery.mark() from just before it in `marks`.
static func add_scatters(sim: Simulation, data: Dictionary, from: int = 0, marks: Dictionary = {}) -> Dictionary:
	var results := {}
	var scenery: Array = data.get("scenery", [])
	for k in range(from, scenery.size()):
		if scenery[k].has("scatter"):
			marks[k] = sim.scenery.mark()
			var p := Profiler.start()
			results[k] = Scatter.apply(sim, scenery[k]["scatter"], k)
			Profiler.stop("load: scatter %d (%s)" % [k, scenery[k]["scatter"].get("preset", "custom")], p)
	return results

## Agent caps and scheduled events, after everything is placed.
static func finish(sim: Simulation, data: Dictionary) -> void:
	var p := Profiler.start()
	# Agent caps per layer: "surface", or "nest" for every nest's underground.
	var caps: Dictionary = data.get("max_agents", {})
	for l in sim.layers:
		var key := "surface" if l.index == 0 else "nest"
		if caps.has(key):
			sim.set_max_agents(l.index, int(caps[key]))
	var events: Array[Dictionary] = []
	for ev: Dictionary in data.get("events", []):
		events.append(ev)
	sim.schedule_events(events)
	Profiler.stop("load: finish", p)

static func load_simulation(scenario_name: String, registry: Registry, config: SimConfig, seed_override: int = -1) -> Simulation:
	var p := Profiler.start()
	var data := load_data(scenario_name)
	Profiler.stop("load: read json", p)
	return build(data, registry, config, seed_override)
