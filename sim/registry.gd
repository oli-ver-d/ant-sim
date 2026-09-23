class_name Registry
extends RefCounted
## Maps string ids to the pluggable pieces of the simulation: behaviour states,
## food source types, item types, nest types and species definitions.
##
## The core registers its generic pieces; each species module registers its own
## through res://species/<module>/register.gd, which is discovered by scanning
## the folder. The core therefore never refers to a species by name.
##
## A module's register.gd must be instantiable (extends RefCounted) and provide:
##     func register(registry: Registry) -> void

const SPECIES_ROOT := "res://species"
const MODULE_ENTRY := "register.gd"

## Shared, stateless behaviour instances (per-ant data lives in the Simulation).
var behaviours: Dictionary[String, Behaviour] = {}
## Scripts instantiated per placement (one FoodSource per placed source).
var food_source_types: Dictionary[String, Script] = {}
## Item type scripts (anything an ant can carry).
var item_types: Dictionary[String, Script] = {}
## NestType scripts, instantiated once per colony.
var nest_types: Dictionary[String, Script] = {}
## Species definitions (SpeciesDef resources) by species id.
var species: Dictionary[String, Resource] = {}
## Names of species modules loaded by discover_modules(), in load order.
var loaded_modules: PackedStringArray = []

func register_behaviour(id: String, behaviour: Behaviour) -> bool:
	return _add(behaviours, "behaviour", id, behaviour)

func register_food_source_type(id: String, script: Script) -> bool:
	return _add(food_source_types, "food source type", id, script)

func register_item_type(id: String, script: Script) -> bool:
	return _add(item_types, "item type", id, script)

func register_nest_type(id: String, script: Script) -> bool:
	return _add(nest_types, "nest type", id, script)

func register_species(id: String, def: Resource) -> bool:
	return _add(species, "species", id, def)

func get_behaviour(id: String) -> Behaviour:
	assert(behaviours.has(id), "Unknown behaviour: %s" % id)
	return behaviours.get(id)

## Loads every <root>/<module>/register.gd (sorted by folder name, so load order
## is deterministic) and calls its register(). Returns false if any module failed.
func discover_modules(root: String = SPECIES_ROOT) -> bool:
	var ok := true
	var dirs := DirAccess.get_directories_at(root)
	dirs.sort()
	for dir_name in dirs:
		var path := root.path_join(dir_name).path_join(MODULE_ENTRY)
		if not ResourceLoader.exists(path):
			continue
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			push_error("Registry: cannot load species module %s" % path)
			ok = false
			continue
		var module: Object = script.new()
		if not module.has_method("register"):
			push_error("Registry: %s has no register(registry) method" % path)
			ok = false
			continue
		module.call("register", self)
		loaded_modules.append(dir_name)
	return ok

func _add(table: Dictionary, kind: String, id: String, value: Variant) -> bool:
	if id.is_empty() or value == null:
		push_error("Registry: invalid %s registration '%s'" % [kind, id])
		return false
	if table.has(id):
		push_error("Registry: duplicate %s id '%s'" % [kind, id])
		return false
	table[id] = value
	return true
