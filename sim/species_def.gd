class_name SpeciesDef
extends Resource
## A species as data. Colonies are instances of a SpeciesDef.

@export var id: StringName = &""
@export var display_name: String = ""
@export var castes: Array[CasteDef] = []
@export var channels: Array[PheromoneChannelDef] = []

@export_group("Nest")
## Registry id of the NestType this species builds.
@export var nest_type: String = "basic_nest"
## Passed to NestType.setup(); meaning is defined by the nest type.
@export var nest_params: Dictionary = {}

@export_group("Interactions")
## FoodSource type ids this species forages from.
@export var food_source_types: PackedStringArray = []
## Item type ids this species handles.
@export var item_types: PackedStringArray = []

@export_group("Behaviour")
## Per-state parameters: state id -> {param: value}. Values of keys ending in
## "_channel" are local channel names and get resolved to field indices.
@export var state_params: Dictionary = {}
## Overrides for SimConfig values plus species-only tunables.
@export var tunables: Dictionary = {}
## State params merged over state_params (before caste overrides) when the
## colony's nest has an underground, e.g. so workers come back in to take
## nest roles instead of looping outside.
@export var underground_state_params: Dictionary = {}

func caste_index(caste_id: StringName) -> int:
	for i in castes.size():
		if castes[i].id == caste_id:
			return i
	return -1
