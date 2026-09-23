class_name FungusNest
extends NestType
## Leafcutter nest. Leafcutters don't eat leaves: they farm a fungus on them,
## and the fungus feeds the colony. Model (per tick):
##
##   delivered leaf  -> substrate (fresh leaf pulp waiting in the garden)
##   the garden digests substrate at digest_rate * fungus mass per second:
##       fungus += digested * fungus_yield
##       waste  += digested * (1 - fungus_yield)   (spent substrate)
##   the colony eats upkeep_per_ant * population fungus per second
##   brood: the garden feeds brood_rate * fungus new ants per second (a
##       bigger garden raises more brood), each costing ant_cost fungus,
##       while fungus stays above brood_reserve, up to max_population
##
## So growth is limited by the garden, which is limited by leaf supply: a
## colony cut off from leaves stops growing and its garden slowly shrinks.
## The garden fills chambers of chamber_capacity fungus; a new chamber is dug
## when the last one is nearly full (up to max_chambers). Waste is carried out
## in loads of waste_load mass by carry_waste workers to a dump beside the
## entrance (`dump`: offset from the entrance).
##
## params: radius, sense_radius, initial_fungus, digest_rate, fungus_yield,
##         upkeep_per_ant, ant_cost, brood_reserve, brood_rate,
##         max_population, chamber_capacity, max_chambers, waste_load, dump

var fungus: float = 60.0
var substrate: float = 0.0
var waste: float = 0.0
var chambers: int = 1
## Totals, for stats and tests.
var leaf_received: float = 0.0
var fungus_grown: float = 0.0
var ants_raised: int = 0

var digest_rate: float = 0.02
var fungus_yield: float = 0.6
var upkeep_per_ant: float = 0.0002
var ant_cost: float = 1.5
var brood_reserve: float = 30.0
var brood_rate: float = 0.004
var max_population: int = 3000
var chamber_capacity: float = 150.0
var max_chambers: int = 5
var waste_load: float = 0.25
var dump_offset: Vector2 = Vector2(120, 40)

var _brood_budget: float = 0.0

func setup(sim: Simulation, owner_colony: Colony, params: Dictionary) -> void:
	super.setup(sim, owner_colony, params)
	fungus = params.get("initial_fungus", fungus)
	digest_rate = params.get("digest_rate", digest_rate)
	fungus_yield = params.get("fungus_yield", fungus_yield)
	upkeep_per_ant = params.get("upkeep_per_ant", upkeep_per_ant)
	ant_cost = params.get("ant_cost", ant_cost)
	brood_reserve = params.get("brood_reserve", brood_reserve)
	brood_rate = params.get("brood_rate", brood_rate)
	max_population = int(params.get("max_population", max_population))
	chamber_capacity = params.get("chamber_capacity", chamber_capacity)
	max_chambers = int(params.get("max_chambers", max_chambers))
	waste_load = params.get("waste_load", waste_load)
	if params.has("dump"):
		dump_offset = ScenarioEvents.vec2(params["dump"])
	_fit_chambers()

func receive_item(_sim: Simulation, item: Item) -> void:
	substrate += item.mass
	leaf_received += item.mass

func update(sim: Simulation, dt: float) -> void:
	var colony := sim.colonies[colony_id]
	# The garden digests fresh leaf.
	var digested := minf(substrate, digest_rate * fungus * dt)
	substrate -= digested
	fungus += digested * fungus_yield
	fungus_grown += digested * fungus_yield
	waste += digested * (1.0 - fungus_yield)
	# The colony eats from it.
	fungus = maxf(0.0, fungus - upkeep_per_ant * colony.population * dt)
	# Brood: spend surplus fungus on new workers.
	_brood_budget = minf(_brood_budget + brood_rate * fungus * dt, 1.0)
	if _brood_budget >= 1.0 and fungus - ant_cost >= brood_reserve and colony.population < max_population:
		_brood_budget -= 1.0
		fungus -= ant_cost
		ants_raised += 1
		spawn_ants(sim, 1)
	_fit_chambers()

## Digs another chamber when the garden has nearly filled the ones it has.
func _fit_chambers() -> void:
	while chambers < max_chambers and fungus > chambers * chamber_capacity * 0.85:
		chambers += 1

func has_waste() -> bool:
	return waste >= waste_load

func take_waste(sim: Simulation) -> Item:
	if not has_waste():
		return null
	waste -= waste_load
	var item := sim.create_item("waste", waste_load)
	item.radius = 1.8
	item.color = Color(0.36, 0.33, 0.27)
	return item

func dump_position() -> Vector2:
	return position + dump_offset
