class_name BasicNest
extends NestType
## Generic nest: a hole in the ground that stores delivered food mass and
## turns it into new ants.
##
## params: radius, sense_radius, ant_cost (mass per new ant), max_population

var stored_mass: float = 0.0
var ant_cost: float = 5.0
var max_population: int = 1000

func setup(sim: Simulation, owner_colony: Colony, params: Dictionary) -> void:
	super.setup(sim, owner_colony, params)
	ant_cost = params.get("ant_cost", ant_cost)
	max_population = int(params.get("max_population", max_population))

func receive_item(_sim: Simulation, item: Item) -> void:
	stored_mass += item.mass

func update(sim: Simulation, _dt: float) -> void:
	if ant_cost > 0.0 and stored_mass >= ant_cost and sim.colonies[colony_id].population < max_population:
		stored_mass -= ant_cost
		spawn_ants(sim, 1)
