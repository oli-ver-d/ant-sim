class_name SimConfig
extends Resource
## Global simulation tunables. Species-specific values live in each species'
## SpeciesDef and are merged over these via get_param().
## Default values here are the source of truth; res://sim/default_config.tres
## only stores overrides.

## Settings fixed when a Simulation is created (sizes of grids and arrays,
## tick length) or owned by the scenario: live tuning can't change these.
const STRUCTURAL: PackedStringArray = ["world_size", "cell_size", "tick_rate", "ticks_per_frame",
		"max_ants", "diffuse_every_n_ticks"]

@export_group("World")
## World size in world units (1 unit = 1 px at default zoom).
@export var world_size: Vector2i = Vector2i(1080, 1920)
## Side length of one pheromone/obstacle grid cell in world units.
@export var cell_size: int = 4

@export_group("Time")
## Fixed simulation ticks per simulated second. step() always advances 1 / tick_rate.
## 30 keeps GDScript cost down; renderers interpolate between ticks so motion
## stays smooth at 60 fps.
@export var tick_rate: int = 30
## Default sim speed in ticks per rendered frame at 60 fps (scenarios may override).
## Fractional values are fine: 0.5 = real time at tick_rate 30.
@export var ticks_per_frame: float = 0.5

@export_group("Population")
## Hard cap on live ants across all colonies (array capacity).
@export var max_ants: int = 20000

@export_group("Steering")
## Angle between the centre sensor and each side sensor, in degrees.
@export var sensor_angle_deg: float = 35.0
## Distance from the ant to its sensors, in world units.
@export var sensor_distance: float = 12.0
## Max random heading change per second (radians), added on top of sensing.
@export var wander_strength: float = 2.0
## How far ahead (world units) ants look for obstacles and world edges.
@export var avoid_lookahead: float = 10.0
## Pheromone below this (real units) is ignored by sensors.
@export var sense_threshold: float = 0.01
## Distance at which an ant counts as having reached a target point.
@export var arrive_distance: float = 3.0
## Seconds after bumping into an obstacle during which homing ants trust the
## trail over their sense of where home is (path integration), so they can
## follow a detour (along a bank to a bridge, through a maze) instead of
## pushing straight at home into the obstacle.
@export var obstacle_memory: float = 4.0

@export_group("Foraging")
## Explorers check for nearby food sources once every N ticks (staggered per ant).
@export var food_check_interval: int = 4
## Carry speed = speed / (1 + mass * carry_mass_slowdown).
@export var carry_mass_slowdown: float = 0.15
## Speed multiplier for ants crossing ground clutter (debris).
@export var clutter_slowdown: float = 0.35

@export_group("Pheromones")
## Diffusion (3x3 blur) runs once every N ticks; evaporation runs every tick.
@export var diffuse_every_n_ticks: int = 16
## Base amount deposited per tick by a laying ant, before decay.
@export var deposit_base: float = 1.0
## Seconds after touching its source (nest/food) at which an ant's deposit has halved.
@export var deposit_half_life: float = 8.0

## Species or scenario overrides, keyed by property name. Looked up by get_param().
func get_param(key: StringName, overrides: Dictionary = {}) -> Variant:
	if overrides.has(key):
		return overrides[key]
	assert(key in self, "Unknown SimConfig parameter: %s" % key)
	return get(key)

## Grid dimensions (cells) shared by the pheromone field and the obstacle grid.
func grid_size() -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(world_size.x / cell_size, world_size.y / cell_size)

## Duration of one fixed tick in seconds.
func tick_dt() -> float:
	return 1.0 / float(tick_rate)
