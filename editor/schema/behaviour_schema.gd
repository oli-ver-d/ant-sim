class_name BehaviourSchema
extends RefCounted
## A colony's "state_params" (per behaviour state) and "channels" (pheromone
## channel overrides). See ScenarioSchema.

const F = preload("res://editor/schema/field_spec.gd")

static func register(_schema: ScenarioSchema) -> void:
	pass

static func _state(help_text: String) -> FieldSpec:
	return F.choice([], null, help_text).from_registry("states")

static func _channel(help_text: String) -> FieldSpec:
	return F.choice([], null, help_text).from_registry("channels")

## The keys behaviour states read from their params (Behaviour scripts, the
## native kernel, Colony._resolve_channels). Every state shares this union;
## each state reads only its own keys, the others are ignored. Keys ending in
## "_channel" name a species channel and are resolved to its index.
static func state_keys() -> Dictionary:
	return {
		# Channels
		"follow_channel": _channel("Channel to steer along (explore, follow_trail, carry_home, patrol_trail); none if absent"),
		"lay_channel": _channel("Channel to deposit while in this state (explore, go_to_food, follow_trail, carry_home); none if absent"),
		"avoid_channel": _channel("Channel to steer away from (explore)"),
		"trail_channel": _channel("Trail whose side debris is carried off to (clear_debris)"),
		# Steering
		"home_bias": F.number(0.0, "Pull toward home while following a trail (0 = none)").limits(0, 1),
		"home_cone_deg": F.number(0.0, "Half-angle of the cone (degrees) inside which home_bias applies").limits(0, 180),
		"speed_factor": F.number(null, "Walking speed as a fraction of the ant's speed (dig 1.0, linger 0.5, patrol_trail 0.7)").limits(0, 3),
		"turn_around": F.boolean(true, "Turn back along the trail when entering follow_trail"),
		"goal": F.text(null, "Unused; kept for readability in species files"),
		# Timing
		"give_up_after": F.number(null, "Seconds in the state before giving up (explore: 0 = never; dig 90)").limits(0),
		"timeout": F.number(null, "Seconds before the state times out (follow_trail 60, go_to_food 20, clear_debris 30, seek_ride 40)").limits(0),
		"duration": F.number(0.0, "Seconds to stay (linger; 0 = no limit)").limits(0),
		"stint": F.number(null, "Seconds of a nest job before looking for another (nurse 90, tend_queen 70, tend_granary 90)").limits(0),
		"retarget_interval": F.number(0.5, "Seconds between re-aiming at the food source (go_to_food)").limits(0),
		"dig_time": F.number(2.5, "Seconds of biting per dig step (dig)").limits(0),
		"gather_time": F.number(1.8, "Seconds to gather a seed (tend_granary)").limits(0),
		"sort_time": F.number(3.0, "Seconds to sort a seed (tend_granary)").limits(0),
		"cut_time": F.number(1.6, "Seconds to cut a fragment (garden)").limits(0),
		"plant_time": F.number(1.0, "Seconds to plant pulp on the fungus (garden)").limits(0),
		"weed_time": F.number(1.8, "Seconds to weed the fungus (garden)").limits(0),
		"pulp_mass": F.number(0.5, "Pulp mass per cut, times the caste's carry_capacity (garden)").limits(0),
		# Geometry
		"radius": F.number(80.0, "Wander radius round the start point (linger)").limits(0),
		"spoil_spread": F.number(22.0, "How far spoil is scattered round the heap (carry_spoil)").limits(0),
		# Transitions
		"next": _state("State to go to afterwards (deliver, go_up, linger, carry_down, store_seed, clear_debris)"),
		"on_arrive": _state("State on arriving (follow_trail, carry_home, go_to_food)"),
		"on_timeout": _state("State when timed out (follow_trail, seek_ride)"),
		"on_give_up": _state("State when giving up (explore, patrol_trail)"),
		"on_food": _state("State when food is sensed (explore)"),
		"on_lost": _state("State when the target is gone (go_to_food, cut_leaf, seek_ride)"),
		"on_pickup": _state("State after picking the food up (go_to_food)"),
		"on_cut": _state("State after cutting a fragment (cut_leaf)"),
		"on_missed": _state("State when the leaf was taken meanwhile (cut_leaf)"),
		"on_done": _state("State when the job is finished (nurse, tend_queen, carry_spent, carry_spoil, carry_waste, tend_granary)"),
		"on_none": _state("State when there is nothing to carry (carry_waste)"),
		"on_idle": _state("State when there is nothing to dig (dig)"),
		"on_spoil": _state("State after biting off spoil (dig)"),
		"on_waste": _state("State to take waste out (tend_granary, garden)"),
		"on_debris": _state("State on finding debris on the trail (patrol_trail)"),
		"on_ride": _state("State once mounted on a carrier (seek_ride)"),
		"on_dismount": _state("State on getting off (hitchhike)"),
		"hitchhiker": _state("State for ants that ride (assign_role)"),
		"stayer": _state("State for ants that stay behind (assign_role)"),
	}

static func state_params() -> FieldSpec:
	return F.map(F.dict(state_keys(), "Parameters of one behaviour state"), "states",
			"Per-state behaviour parameters, merged over the species' and caste's")

## The overridable PheromoneChannelDef properties.
static func channel_keys() -> Dictionary:
	return {
		"half_life": F.number(30.0, "Seconds for a deposit to evaporate to half strength").limits(0.01),
		"diffusion": F.number(0.2, "Fraction per second blended toward the 3x3 neighbourhood mean").limits(0, 1),
		"cap": F.number(10.0, "Maximum value a cell can hold").limits(0),
		"reinforce": F.number(0.1, "Extra from repeated deposits: cell = max(cell, deposit) + reinforce * deposit").limits(0),
		"color": F.color(null, "Colour in the pheromone overlay"),
		"render_intensity": F.number(1.0, "Overlay brightness multiplier").limits(0),
	}

static func channels() -> FieldSpec:
	return F.map(F.dict(channel_keys(), "Overrides of one pheromone channel"), "channels",
			"Pheromone channel overrides, by the species' channel name")
