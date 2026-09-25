class_name SeedNest
extends BasicNest
## Harvester nest: stores delivered seeds as food mass and spawns ants from
## it (BasicNest), and keeps a count of seeds for the renderer, which shows the
## cleared disc harvesters keep around their entrance and the growing pile of
## discarded husks.
##
## params: BasicNest params, disc_radius

var seeds_received: int = 0
var disc_radius: float = 70.0

func setup(sim: Simulation, owner_colony: Colony, params: Dictionary) -> void:
	# A crater of chaff and grit in a disc cleared of plants.
	entrance_style = "crater"
	clears_plants = true
	super.setup(sim, owner_colony, params)
	disc_radius = params.get("disc_radius", disc_radius)
	if clear_radius <= 0.0:
		clear_radius = disc_radius

func receive_item(sim: Simulation, item: Item) -> void:
	super.receive_item(sim, item)
	seeds_received += 1
