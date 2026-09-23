class_name ScenarioLoader
extends RefCounted
## Builds a Simulation from a JSON scenario file (res://scenarios/<name>.json).
##
## Simulation content (used here):
##   "seed": 1,
##   "colonies":  [{"species": "...", "nest": [x, y], "nest_params": {}, "population": {"<caste>": n}}],
##   "food":      [{"type": "food_pile", "pos": [x, y], ...type params}],
##   "obstacles": [shape, ...]              (see ScenarioEvents for shapes)
##   "debris":    [{"type": "twig" | "pebble", "pos": [x, y], ...}]  (see Debris)
##   "events":    [{"t": seconds, "type": ..., ...}]   (see ScenarioEvents)
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
	var seed_value: int = seed_override if seed_override >= 0 else int(data.get("seed", 1))
	var sim := Simulation.new(config, registry, seed_value)
	for ob: Dictionary in data.get("obstacles", []):
		ScenarioEvents.add_obstacle(sim.world, ob)
	for food: Dictionary in data.get("food", []):
		sim.add_food_source(food["type"], food)
	for d: Dictionary in data.get("debris", []):
		Debris.create(sim, d)
	for col: Dictionary in data.get("colonies", []):
		ScenarioEvents.add_colony(sim, col)
	var events: Array[Dictionary] = []
	for ev: Dictionary in data.get("events", []):
		events.append(ev)
	sim.schedule_events(events)
	return sim

static func load_simulation(scenario_name: String, registry: Registry, config: SimConfig, seed_override: int = -1) -> Simulation:
	return build(load_data(scenario_name), registry, config, seed_override)
