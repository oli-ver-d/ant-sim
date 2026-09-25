class_name GranaryNest
extends ColonyNest
## Harvester nest that digs its own underground (nest_params "underground"
## is required; for a plain hole in the ground use SeedNest). Harvesters live
## on the seeds they store: foragers carry each seed down into a granary
## chamber (store_seed) and drop it on the heap there, the colony eats from
## the granaries, and every seed eaten leaves its husk behind as chaff, which
## workers tending the granaries (tend_granary) carry out to the midden
## beside the entrance (carry_spent).
##
## Everything else is ColonyNest's: the queen in the royal chamber, brood
## that nurses feed with seed meal chewed from the granaries, nest roles,
## chambers dug as the nest needs room, a founding nest sealed in, more
## entrances as the colony grows. The founding queen's cache (initial_seeds)
## lies in the royal chamber: it feeds the first brood until the first
## forager comes home.
##
## Economy (per second):
##   the colony eats upkeep_per_ant * population of stored seed
##   the queen lays paced by brood_rate * stored seed (Brood), while the
##   store is above brood_reserve; each larva eats ant_cost over its stage
##   a seed eaten leaves husk * its mass as chaff in its granary
## Chambers: the first dug is the brood chamber, the rest are granaries,
## each holding granary_capacity (for a chamber of radius 40, by area; the
## royal chamber a third of that). A new chamber is planned when the
## granaries are nearly full or the colony has outgrown its chambers
## (ants_per_chamber per chamber dug), see space_pressure().
##
## params: ColonyNest's, and upkeep_per_ant, granary_capacity, initial_seeds,
##         seed_mass (of the cache's seeds), ants_per_chamber, husk,
##         chaff_load, disc_radius (the cleared disc around the entrance)

var upkeep_per_ant: float = 0.0002
var granary_capacity: float = 60.0
var ants_per_chamber: float = 120.0
var husk: float = 0.3
var chaff_load: float = 0.3
var disc_radius: float = 70.0

## Stored seeds, one record each (in the order they were stored): where it
## lies, its mass left (it shrinks as it is eaten), the chamber it lies in,
## and its look (colour index and a seed for its size and angle).
var seed_pos: PackedVector2Array = []
var seed_mass: PackedFloat32Array = []
var seed_chamber: PackedInt32Array = []
var seed_color: PackedColorArray = []
var seed_look: PackedInt32Array = []
## Seed mass stored per chamber (index = chamber), and chaff lying in it.
var stored_in: PackedFloat64Array = []
var chaff: PackedFloat64Array = []
## Bumped whenever a chamber's seeds or chaff change (index = chamber), for
## renderers.
var chamber_version: PackedInt32Array = []

## Totals, for stats and tests.
var stored: float = 0.0
var seeds_received: int = 0
var received_mass: float = 0.0
var eaten_mass: float = 0.0
var fed_mass: float = 0.0
var chaff_made: float = 0.0
var chaff_taken: float = 0.0
## The colony's size, as of the last role count (once a second).
var sim_population: float = 0.0
var _hunger: float = 0.0
var _looks: int = 0

## Seed colours of the founding cache.
const CACHE_COLORS: Array[Color] = [Color(0.8, 0.63, 0.36), Color(0.68, 0.5, 0.27), Color(0.87, 0.74, 0.47)]
## A seed eaten down to this much is gone.
const CRUMB := 0.03

func setup(sim: Simulation, owner_colony: Colony, params: Dictionary) -> void:
	brood_food_type = "seed_meal"
	dump_offset = Vector2(90, 55)
	# Most harvesters forage; a few keep the granaries when nothing is short.
	inside_share = 0.15
	super.setup(sim, owner_colony, params)
	upkeep_per_ant = float(params.get("upkeep_per_ant", upkeep_per_ant))
	granary_capacity = float(params.get("granary_capacity", granary_capacity))
	ants_per_chamber = float(params.get("ants_per_chamber", ants_per_chamber))
	husk = float(params.get("husk", husk))
	chaff_load = float(params.get("chaff_load", chaff_load))
	disc_radius = float(params.get("disc_radius", disc_radius))
	if chambers_layout == null:
		push_error("GranaryNest needs nest_params \"underground\" (use seed_nest for a nest without one)")
		return
	_grow_chamber_arrays()
	_setup_layered(sim, owner_colony, params, &"minor")
	_grow_chamber_arrays()
	# The founding queen's cache, in a heap in the royal chamber (placed with
	# its own RNG, so the simulation's random stream is untouched).
	var rng := RandomNumberGenerator.new()
	rng.seed = sim.rng.seed * 29 + colony_id
	var mass := float(params.get("seed_mass", 0.4))
	for n in int(params.get("initial_seeds", 0)):
		var at := _heap_point(0, rng)
		var s := rng.randf_range(0.8, 1.2)
		_add_seed(at, mass * s * s, 0, CACHE_COLORS[n % CACHE_COLORS.size()])

func update(sim: Simulation, dt: float) -> void:
	if chambers_layout == null:
		return
	_grow_chamber_arrays()
	_ensure_queen(sim)
	# The colony eats from the granaries, the fullest first.
	_hunger = minf(_hunger + upkeep_per_ant * sim.colonies[colony_id].total_population() * dt, 1.0)
	while _hunger > 1e-4 and not seed_mass.is_empty():
		var k := _fullest_granary()
		var s := _top_seed(k)
		if s < 0:
			break
		var got := _eat_seed(s, _hunger)
		eaten_mass += got
		_hunger -= got
	_update_colony(sim, dt)

func _grow_chamber_arrays() -> void:
	var n := chambers_layout.count()
	while stored_in.size() < n:
		stored_in.append(0.0)
		chaff.append(0.0)
		chamber_version.append(0)

func hash_state(ctx: HashingContext) -> void:
	if brood != null:
		brood.hash_into(ctx)
	if chambers_layout == null:
		return
	hash_underground(ctx)
	ctx.update(PackedFloat64Array([stored, _hunger, chaff_made, chaff_taken, queen_groomed_at, chambers_layout.count()]).to_byte_array())
	if not seed_mass.is_empty():
		ctx.update(seed_pos.to_byte_array())
		ctx.update(seed_mass.to_byte_array())
		ctx.update(seed_chamber.to_byte_array())

# --- Seeds ------------------------------------------------------------------------------

## Adds a stored seed record.
func _add_seed(at: Vector2, mass: float, k: int, color: Color) -> void:
	seed_pos.append(at)
	seed_mass.append(mass)
	seed_chamber.append(k)
	seed_color.append(color)
	seed_look.append(_looks)
	_looks += 1
	stored += mass
	stored_in[k] += mass
	chamber_version[k] += 1

## Takes up to `want` off seed s; a seed eaten down to a crumb is gone. Its
## husk is left as chaff in its chamber. Returns the mass taken.
func _eat_seed(s: int, want: float) -> float:
	var k := seed_chamber[s]
	var got := minf(want, seed_mass[s])
	var left := seed_mass[s] - got
	if left <= CRUMB:
		got += left
		left = 0.0
	stored -= got
	stored_in[k] = maxf(0.0, stored_in[k] - got)
	chaff[k] += got * husk
	chaff_made += got * husk
	chamber_version[k] += 1
	if left <= 0.0:
		seed_pos.remove_at(s)
		seed_mass.remove_at(s)
		seed_chamber.remove_at(s)
		seed_color.remove_at(s)
		seed_look.remove_at(s)
	else:
		seed_mass[s] = left
	return got

## The last seed stored in chamber k (the top of its heap), or -1.
func _top_seed(k: int) -> int:
	for s in range(seed_chamber.size() - 1, -1, -1):
		if seed_chamber[s] == k:
			return s
	return -1

## Chambers seeds are kept in: the royal chamber (the founding cache) and
## every chamber dug but the brood chamber.
func is_granary(k: int) -> bool:
	if k == 0:
		return true
	var c := chambers_layout.list[k]
	return c.dug and k != brood_chamber()

## Seed mass chamber k holds when full.
func capacity_of(k: int) -> float:
	var c := chambers_layout.list[k]
	return granary_capacity * pow(c.radius / 40.0, 2.0) * (0.34 if k == 0 else 1.0)

func granary_capacity_total() -> float:
	var cap := 0.0
	for c in chambers_layout.list:
		if is_granary(c.index):
			cap += capacity_of(c.index)
	return cap

## The granary new seeds go to: the first (nearest the middle) with room,
## else the least full. The royal chamber only until another is dug.
func store_chamber() -> int:
	var best := -1
	var best_fill := INF
	for c in chambers_layout.list:
		var k := c.index
		if not is_granary(k) or (k == 0 and _granaries_dug() > 0):
			continue
		var fill := stored_in[k] / maxf(1e-6, capacity_of(k))
		if fill < 0.95:
			return k
		if fill < best_fill:
			best_fill = fill
			best = k
	return maxi(best, 0)

func _granaries_dug() -> int:
	var n := 0
	for c in chambers_layout.list:
		if c.index > 0 and is_granary(c.index):
			n += 1
	return n

## The granary with the most seed in it (-1 if they are all empty).
func _fullest_granary() -> int:
	var best := -1
	var most := 0.0
	for k in stored_in.size():
		if stored_in[k] > most:
			most = stored_in[k]
			best = k
	return best

## Where chamber k's heap of seeds lies: the royal chamber's across from
## the pupae's alcove (the brood lies between it and the queen's niche),
## other chambers' a little off their middle.
func heap_centre(k: int) -> Vector2:
	if k == 0:
		var royal := chambers_layout.royal()
		if royal.alcoves.size() >= 2:
			var a := (royal.centre - royal.alcoves[1]).angle()
			return _spot(0, Vector2.from_angle(a) * 0.55)
		return _spot(0, Vector2(0.35, -0.3))
	return _spot(k, Vector2(0.12, 0.1))

## A place on chamber k's heap, which spreads as it grows.
func _heap_point(k: int, rng: RandomNumberGenerator) -> Vector2:
	var centre := heap_centre(k)
	var spread := 4.0 + sqrt(stored_in[k] / 0.4) * 1.7
	spread = minf(spread, chambers_layout.list[k].radius * 0.75)
	var at := centre + Vector2.from_angle(rng.randf() * TAU) * spread * sqrt(rng.randf())
	if chambers_layout.chamber_at(at) != k or chambers_layout.world.is_blocked(at):
		at = chambers_layout.random_point(k, rng, 2)
	return at

## Where a forager carrying a seed down drops it: on the heap of
## store_chamber().
func store_point(sim: Simulation) -> Vector2:
	return _heap_point(store_chamber(), sim.rng)

## A seed carried down is put on the heap at `at` (the forager's drop
## point, or a place on the heap if that isn't in a granary: stored seeds
## always lie inside a chamber, where nurses can find their way). It counts
## as delivered; the caller destroys the item.
func store_seed(sim: Simulation, item: Item, at: Vector2) -> void:
	_grow_chamber_arrays()
	var k := chambers_layout.chamber_at(at)
	if k < 0 or not is_granary(k) or chambers_layout.world.is_blocked(at):
		k = store_chamber()
		at = _heap_point(k, sim.rng)
	_add_seed(at, item.mass, k, item.color)
	seeds_received += 1
	received_mass += item.mass
	var colony := sim.colonies[colony_id]
	colony.delivered_items += 1
	colony.delivered_mass += item.mass

## Seeds delivered to a nest without an underground (not used: this nest
## always has one) count as stored at the store's heap.
func receive_item(sim: Simulation, item: Item) -> void:
	if chambers_layout != null:
		store_seed(sim, item, store_point(sim))

# --- Food for the brood (ColonyNest) --------------------------------------------------------

func food_stock() -> float:
	return stored

func eat_stock(mass: float) -> void:
	var left := mass
	while left > 1e-6 and not seed_mass.is_empty():
		left -= _eat_seed(seed_mass.size() - 1, left)

## The top of the heap in the granary nearest `near` that has seeds.
func food_point(_sim: Simulation, near: Vector2) -> Vector2:
	var best := -1
	var best_d := INF
	for k in stored_in.size():
		if stored_in[k] <= CRUMB:
			continue
		var d := chambers_layout.list[k].centre.distance_squared_to(near)
		if d < best_d:
			best_d = d
			best = k
	var s := _top_seed(best) if best >= 0 else -1
	return seed_pos[s] if s >= 0 else heap_centre(0)

## Chews up to `mass` off the seeds lying nearest `at` (up to four seeds
## within reach). Nothing while the store is at its reserve.
func take_food_at(at: Vector2, mass: float) -> float:
	if stored - mass <= reserve() * 0.5:
		return 0.0
	var got := 0.0
	for n in 4:
		var s := _nearest_seed(at, 9.0)
		if s < 0:
			break
		got += _eat_seed(s, mass - got)
		if got >= mass - 1e-6:
			break
	fed_mass += got
	return got

## Seed meal a nurse didn't feed goes back on the nearest heap as a crumb of
## seed.
func return_food(at: Vector2, mass: float) -> void:
	var k := chambers_layout.chamber_at(at)
	if k < 0 or not is_granary(k) or chambers_layout.world.is_blocked(at):
		k = store_chamber()
		at = heap_centre(k)
	_add_seed(at, mass, k, Color(0.9, 0.84, 0.66))
	fed_mass -= mass

func make_brood_food(sim: Simulation, mass: float) -> Item:
	var item := sim.create_item(brood_food_type, mass)
	item.radius = 1.2
	item.color = Color(0.93, 0.88, 0.72)
	return item

func _nearest_seed(at: Vector2, reach: float) -> int:
	var best := -1
	var best_d := reach * reach
	for s in seed_pos.size():
		var d := seed_pos[s].distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = s
	return best

## Short of room: the granaries nearly full, or more ants than the chambers
## dug hold.
func space_pressure() -> float:
	var cap := granary_capacity_total()
	var seeds := stored / cap if cap > 0.0 else 0.0
	var crowd := sim_population / maxf(1.0, ants_per_chamber * chambers)
	return maxf(seeds, crowd)

# --- Roles --------------------------------------------------------------------------------

func role_order() -> Array[String]:
	return ["nurse", "tend_queen", "tend_granary", "dig"]

## Granary workers: to carry out chaff, and some to keep the heaps.
func _count_more_roles(sim: Simulation, workers: int) -> void:
	sim_population = sim.colonies[colony_id].total_population()
	var total_chaff := 0.0
	for k in chaff.size():
		total_chaff += chaff[k]
	var out := total_chaff / (chaff_load * 3.0) if has_entrance() else 0.0
	role_need["tend_granary"] = ceili(out + seed_mass.size() / 500.0) if workers >= 2 else 0

## Nothing short: minors keep the granaries, up to inside_share of them,
## everyone else goes out to forage (or keeps working inside while the
## nest is sealed).
func _idle_role(sim: Simulation, caste: int, roles: Array[String]) -> String:
	var colony := sim.colonies[colony_id]
	var inside: int = role_count.get("nurse", 0) + role_count.get("tend_queen", 0) + role_count.get("tend_granary", 0)
	var minor := colony.species.castes[caste].id == &"minor"
	if roles.has("tend_granary") and minor and (not has_entrance() or inside < colony.population_by_caste[caste] * inside_share):
		return "tend_granary"
	return super._idle_role(sim, caste, roles)

## A place by the heap of the granary with the most chaff to carry out
## (Vector2.INF if there is little, or the nest is sealed).
func chaff_point(sim: Simulation) -> Vector2:
	if not has_entrance():
		return Vector2.INF
	var best := -1
	var most := chaff_load
	for k in chaff.size():
		if chaff[k] > most:
			most = chaff[k]
			best = k
	if best < 0:
		return Vector2.INF
	return _heap_point(best, sim.rng)

## A load of chaff from the chamber at `at`, for a worker to carry out, or
## null if there is too little there.
func take_chaff(sim: Simulation, at: Vector2) -> Item:
	var k := chambers_layout.chamber_at(at)
	if k < 0 or k >= chaff.size() or chaff[k] < chaff_load * 0.5:
		return null
	var m := minf(chaff_load, chaff[k])
	chaff[k] -= m
	chaff_taken += m
	chamber_version[k] += 1
	var item := sim.create_item("chaff", m)
	item.radius = 1.7
	item.color = Color(0.74, 0.62, 0.4)
	return item

## A place on a granary's heap for a worker with nothing else to do to sort
## seeds at (the royal chamber's while the nest has no other).
func tend_point(sim: Simulation) -> Vector2:
	var k := _fullest_granary()
	return _heap_point(maxi(k, 0), sim.rng)

func _chambers_dug(_sim: Simulation) -> void:
	_grow_chamber_arrays()

func stats_lines(sim: Simulation) -> PackedStringArray:
	var out := super.stats_lines(sim)
	var n := seed_mass.size()
	out.append("%s %s stored" % [_thousands(n), "seed" if n == 1 else "seeds"])
	return out
