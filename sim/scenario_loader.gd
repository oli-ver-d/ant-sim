class_name ScenarioLoader
extends RefCounted
## Builds a Simulation from a JSON scenario file (res://scenarios/<name>.json).
##
## {
##   "name": "basic_forage", "seed": 1, "duration": 30,
##   "colonies": [{"species": "...", "nest": [540, 1600], "nest_params": {},
##                 "population": {"<caste id>": 100}}],
##   "food": [{"type": "food_pile", "pos": [540, 300], ...type params}],
##   "obstacles": [{"shape": "polyline", "points": [[x, y], ...], "width": 16, "kind": "wall"},
##                 {"shape": "rect", "rect": [x, y, w, h], "kind": "water"},
##                 {"shape": "circle", "center": [x, y], "radius": 30},
##                 {"shape": "polygon", "points": [[x, y], ...]}]
## }
## Timed events, camera keyframes and ticks_per_frame arrive with the scenario
## system in a later milestone.

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
		_add_obstacle(sim.world, ob)

	for food: Dictionary in data.get("food", []):
		sim.add_food_source(food["type"], food)

	for col: Dictionary in data.get("colonies", []):
		var colony := sim.add_colony(col["species"], _vec2(col["nest"]), col.get("nest_params", {}))
		var population: Dictionary = col.get("population", {})
		# Iterate castes in SpeciesDef order so spawn order doesn't depend on JSON key order.
		for c in colony.species.castes.size():
			var count := int(population.get(str(colony.species.castes[c].id), 0))
			for n in count:
				sim.spawn_ant(colony, c, colony.nest.entrance_position(), sim.rng.randf_range(-PI, PI))
	return sim

static func load_simulation(scenario_name: String, registry: Registry, config: SimConfig, seed_override: int = -1) -> Simulation:
	return build(load_data(scenario_name), registry, config, seed_override)

static func _add_obstacle(world: World, ob: Dictionary) -> void:
	var kind: int = World.Cell.WATER if ob.get("kind", "wall") == "water" else World.Cell.WALL
	match ob.get("shape", "polyline"):
		"polyline":
			world.draw_polyline(_points(ob["points"]), float(ob.get("width", 16.0)), kind)
		"polygon":
			world.fill_polygon(_points(ob["points"]), kind)
		"rect":
			var r: Array = ob["rect"]
			world.fill_rect(Rect2(r[0], r[1], r[2], r[3]), kind)
		"circle":
			world.fill_circle(_vec2(ob["center"]), float(ob["radius"]), kind)
		var other:
			push_error("Unknown obstacle shape %s" % other)

static func _points(arr: Array) -> PackedVector2Array:
	var out: PackedVector2Array = []
	for p: Variant in arr:
		out.append(_vec2(p))
	return out

static func _vec2(v: Variant) -> Vector2:
	var a: Array = v
	return Vector2(a[0], a[1])
