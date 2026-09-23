class_name Colony
extends RefCounted
## One colony: an instance of a SpeciesDef with its own nest, stats and
## namespaced pheromone channels ("c<id>.<name>"). Also caches merged
## parameters so behaviours don't rebuild them per ant per tick.

var id: int
var species: SpeciesDef
var nest_position: Vector2
var nest: NestType

var population: int = 0
var population_by_caste: PackedInt32Array = []
var delivered_items: int = 0
var delivered_mass: float = 0.0

## Local channel name -> PheromoneField channel index.
var channels: Dictionary[StringName, int] = {}
## SimConfig values overlaid with species tunables.
var params: Dictionary = {}
## Params per (caste, state), at index caste * num_states + state, with
## *_channel names resolved to field indices. Use params_for().
var state_params_by_index: Array[Dictionary] = []
var num_states: int = 0
## Set of FoodSource type ids this colony forages from.
var food_types: Dictionary[String, bool] = {}
## Global state index of each caste's initial state.
var caste_initial_state: PackedInt32Array = []

# Hot parameters, cached as typed fields (read per ant per tick).
var sensor_angle: float
var sensor_cos: float
var sensor_sin: float
var sensor_distance: float
var sense_threshold: float
var wander_strength: float
var avoid_lookahead: float
var deposit_base: float
var deposit_decay_per_second: float
var food_check_interval: int
var carry_mass_slowdown: float
var clutter_slowdown: float
var obstacle_memory: float
var arrive_distance: float

func _init(colony_id: int, def: SpeciesDef, nest_pos: Vector2) -> void:
	id = colony_id
	species = def
	nest_position = nest_pos
	population_by_caste.resize(def.castes.size())
	for t in def.food_source_types:
		food_types[t] = true

## Merges config + species tunables and resolves channel names. Called by the
## Simulation after the colony's channels have been registered.
## `overrides` are this colony's own tweaks (e.g. from a scenario):
##   {"params": {"deposit_half_life": 20, ...}, "state_params": {"explore": {...}}}
## "params" win over config and species tunables; "state_params" are merged
## over the species' and caste's state params for every caste.
func build_params(config: SimConfig, state_index: Dictionary[String, int], overrides: Dictionary = {}) -> void:
	for prop in config.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			params[StringName(prop["name"])] = config.get(prop["name"])
	for key: Variant in species.tunables:
		params[StringName(str(key))] = species.tunables[key]
	var param_overrides: Dictionary = overrides.get("params", {})
	for key: Variant in param_overrides:
		assert(params.has(StringName(str(key))), "Unknown parameter %s" % key)
		params[StringName(str(key))] = param_overrides[key]
	var state_overrides: Dictionary = overrides.get("state_params", {})

	sensor_angle = deg_to_rad(params[&"sensor_angle_deg"])
	sensor_cos = cos(sensor_angle)
	sensor_sin = sin(sensor_angle)
	sensor_distance = params[&"sensor_distance"]
	sense_threshold = params[&"sense_threshold"]
	wander_strength = params[&"wander_strength"]
	avoid_lookahead = params[&"avoid_lookahead"]
	deposit_base = params[&"deposit_base"]
	deposit_decay_per_second = log(2.0) / maxf(params[&"deposit_half_life"], 0.001)
	food_check_interval = maxi(1, int(params[&"food_check_interval"]))
	carry_mass_slowdown = params[&"carry_mass_slowdown"]
	clutter_slowdown = params[&"clutter_slowdown"]
	obstacle_memory = params[&"obstacle_memory"]
	arrive_distance = params[&"arrive_distance"]

	# One params dictionary per (caste, state): the species' state_params with
	# the caste's own state_params, then the colony's overrides, merged over
	# them key by key.
	num_states = state_index.size()
	state_params_by_index.resize(species.castes.size() * num_states)
	for c in species.castes.size():
		var caste_overrides := species.castes[c].state_params
		for state_id: String in state_index:
			var merged: Dictionary = {}
			merged.merge(species.state_params.get(state_id, {}), true)
			merged.merge(caste_overrides.get(state_id, {}), true)
			merged.merge(state_overrides.get(state_id, {}), true)
			state_params_by_index[c * num_states + state_index[state_id]] = _resolve_channels(merged)
		for state_id: Variant in caste_overrides:
			assert(state_index.has(str(state_id)), "Caste %s has params for unknown state %s" % [species.castes[c].id, state_id])
	for state_id: Variant in species.state_params:
		assert(state_index.has(str(state_id)), "Species %s has params for unknown state %s" % [species.id, state_id])

	caste_initial_state.resize(species.castes.size())
	for c in species.castes.size():
		var caste := species.castes[c]
		assert(state_index.has(caste.initial_state), "Unknown initial state %s" % caste.initial_state)
		caste_initial_state[c] = state_index[caste.initial_state]

func param(key: StringName) -> Variant:
	return params[key]

## Params the species (and caste override) set for a caste in a state.
func params_for(caste: int, state: int) -> Dictionary:
	return state_params_by_index[caste * num_states + state]

## Replaces "*_channel" channel names with PheromoneField channel indices.
func _resolve_channels(raw: Dictionary) -> Dictionary:
	var resolved: Dictionary = {}
	for key: Variant in raw:
		var value: Variant = raw[key]
		if str(key).ends_with("_channel") and value is String:
			assert(channels.has(StringName(value)), "Unknown channel %s" % value)
			value = channels[StringName(value)]
		resolved[str(key)] = value
	return resolved
