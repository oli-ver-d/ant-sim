class_name Scenery
extends RefCounted
## The surface's scenery props (rocks, logs, plants, grass...). Each prop is
## built by its PropType (Registry.scenery_types) with its own RNG seeded from
## the scenario seed and the prop's id, never the Simulation's `rng`, and none
## of it is hashed: the only thing that reaches the simulation is a blocking
## prop's footprint, stamped into the surface World as WALL cells (tracked in
## World.prop_mask so renderers draw the prop there instead of stone).

var world: World
var registry: Registry
var seed_value: int = 0
var props: Array[Prop] = []
## Incremented whenever a prop is added or removed, for renderers.
var version: int = 0
var _types: Dictionary[String, PropType] = {}
var _next_id: int = 0

func _init(surface: World, reg: Registry, scenario_seed: int) -> void:
	world = surface
	registry = reg
	seed_value = scenario_seed

## Seed of prop `id`'s RNG for a scenario seed.
static func prop_seed_for(scenario_seed: int, id: int) -> int:
	return (scenario_seed * 1000003 + id * 7919 + 12345) & 0x7FFFFFFFFFFFFFFF

## Builds and places a prop from a scenario entry ({"type": ..., ...}; see
## the PropType scripts). Returns null for an unknown type.
func add(data: Dictionary) -> Prop:
	var type_id := str(data.get("type", ""))
	var type := prop_type(type_id)
	if type == null:
		push_error("Unknown scenery type '%s'" % type_id)
		return null
	var prop := Prop.new()
	prop.id = _next_id
	_next_id += 1
	prop.type_id = type_id
	prop.name = str(data.get("name", ""))
	prop.params = data.duplicate(true)
	prop.prop_seed = prop_seed_for(seed_value, prop.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = prop.prop_seed
	type.build(prop, rng)
	prop.bounds = _bounds_of(prop)
	type.stamp(world, prop)
	props.append(prop)
	version += 1
	return prop

## Takes a prop away, freeing the cells it blocked.
func remove(prop: Prop) -> void:
	var i := props.find(prop)
	if i < 0:
		return
	props.remove_at(i)
	if not prop.cells.is_empty():
		world.remove_prop_cells(prop.cells)
		prop.cells = PackedInt32Array()
	version += 1

## Props with this scenario name.
func named(prop_name: String) -> Array[Prop]:
	var out: Array[Prop] = []
	for p in props:
		if p.name == prop_name:
			out.append(p)
	return out

## Props whose base or canopy covers `at`.
func props_at(at: Vector2) -> Array[Prop]:
	var out: Array[Prop] = []
	for p in props:
		if p.bounds.grow(1.0).has_point(at) and p.contains(at):
			out.append(p)
	return out

func prop_type(type_id: String) -> PropType:
	if not _types.has(type_id):
		var script: Script = registry.scenery_types.get(type_id)
		if script == null:
			return null
		_types[type_id] = script.new()
	return _types[type_id]

static func _bounds_of(prop: Prop) -> Rect2:
	var pts := prop.outline + prop.canopy
	if pts.is_empty():
		return Rect2(prop.position, Vector2.ZERO)
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r
