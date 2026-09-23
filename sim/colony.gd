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
## Global state index -> that state's params, with *_channel names resolved to indices.
var state_params_by_index: Array[Dictionary] = []
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
func build_params(config: SimConfig, state_index: Dictionary[String, int]) -> void:
	for prop in config.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			params[StringName(prop["name"])] = config.get(prop["name"])
	for key: Variant in species.tunables:
		params[StringName(str(key))] = species.tunables[key]

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
	arrive_distance = params[&"arrive_distance"]

	state_params_by_index.resize(state_index.size())
	for i in state_params_by_index.size():
		state_params_by_index[i] = {}
	for state_id: Variant in species.state_params:
		var idx: int = state_index.get(str(state_id), -1)
		assert(idx >= 0, "Species %s has params for unknown state %s" % [species.id, state_id])
		var resolved: Dictionary = {}
		var raw: Dictionary = species.state_params[state_id]
		for key: Variant in raw:
			var value: Variant = raw[key]
			if str(key).ends_with("_channel") and value is String:
				assert(channels.has(StringName(value)), "Unknown channel %s" % value)
				value = channels[StringName(value)]
			resolved[str(key)] = value
		state_params_by_index[idx] = resolved

	caste_initial_state.resize(species.castes.size())
	for c in species.castes.size():
		var caste := species.castes[c]
		assert(state_index.has(caste.initial_state), "Unknown initial state %s" % caste.initial_state)
		caste_initial_state[c] = state_index[caste.initial_state]

func param(key: StringName) -> Variant:
	return params[key]
