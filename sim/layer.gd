class_name SimLayer
extends RefCounted
## One layer of the simulation: its own obstacle grid (World), pheromone
## field and, if anything asks for one, navigation fields (NavGrid). Layer 0
## is the surface; others are e.g. a nest's underground, linked to the
## surface by Portals. Each layer has its own size, cell size and
## coordinates (world units from its top-left corner).
##
## Every layer's pheromone field has the same channels at the same indices
## (see Simulation.add_layer / add_colony), so a colony's channel index works
## on whichever layer an ant is on.

var index: int
var name: StringName
var world: World
var pheromones: PheromoneField
## Distance fields toward named targets over free cells, or null until the
## first nav() call.
var nav_grid: NavGrid
## Clear pheromone from blocked cells once per diffusion cycle (keeps trails
## from soaking through walls). Only worth it on the surface: an underground
## is almost all soil and its routing doesn't use pheromones.
var clear_blocked: bool = true
## Most agents (ants simulated one by one) this layer holds; beyond it a
## colony grows as an abstract population (Simulation.balance_pools). 0 = no limit.
var max_agents: int = 0

var _blocked_cells: PackedInt32Array = []
var _blocked_version: int = -1

func _init(layer_index: int, layer_name: StringName, world_size: Vector2i, cell: int,
		diffuse_every: int, dt: float) -> void:
	index = layer_index
	name = layer_name
	world = World.new(world_size, cell)
	@warning_ignore("integer_division")
	pheromones = PheromoneField.new(Vector2i(world_size.x / cell, world_size.y / cell), cell, diffuse_every, dt)

## The layer's navigation fields (created on first use).
func nav() -> NavGrid:
	if nav_grid == null:
		nav_grid = NavGrid.new(world)
	return nav_grid

## End-of-tick pheromone work: evaporation, a diffusion band, and clearing
## blocked cells once per diffusion cycle (if clear_blocked).
func update_pheromones(tick_count: int) -> void:
	pheromones.update()
	if clear_blocked and tick_count % pheromones.diffuse_every == 0:
		if _blocked_version != world.version:
			_blocked_cells = world.blocked_cells()
			_blocked_version = world.version
		pheromones.clear_cells(_blocked_cells)

## A route for a new tunnel from `from` to `to` through this layer's soil,
## around stones and clear of other cavities (see Router for the params).
## Empty if there is none.
func route(from: Vector2, to: Vector2, params: Dictionary = {}) -> PackedVector2Array:
	return Router.route(world, from, to, params)
