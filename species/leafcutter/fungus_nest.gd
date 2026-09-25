class_name FungusNest
extends ColonyNest
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
##       while fungus stays above brood_reserve, up to max_population.
##       By default new ants appear at once; with nest_params "brood" the
##       queen lays eggs that develop into workers (see Brood)
##
## So growth is limited by the garden, which is limited by leaf supply: a
## colony cut off from leaves stops growing and its garden slowly shrinks.
## The garden fills chambers of chamber_capacity fungus; a new chamber is dug
## when the last one is nearly full (up to max_chambers). Waste is carried out
## in loads of waste_load mass by carry_waste workers to a dump beside the
## entrance (`dump`: offset from the entrance).
##
## With nest_params "underground" the nest digs its own underground and
## everything in it is simulated (ColonyNest: chambers, the queen, brood that
## needs care, nest roles, founding sealed in, more entrances). Here:
##   - the gardens grow cell by cell in the chambers (GardenGrid); the
##     founding garden in the royal chamber;
##   - nurses feed larvae gongylidia from the gardens;
##   - minims garden (cut up leaf, plant it, weed), medias forage or dig;
##   - chambers are planned as the gardens fill them (garden_pressure()).
##
## params: ColonyNest's, and initial_fungus, digest_rate, fungus_yield,
##         upkeep_per_ant, chamber_capacity, waste_load; with an underground:
##         queen_reserve (a sealed nest: 30), queen_feed_rate, garden_reserve
##         (replaces brood_reserve: a share of garden capacity)

var fungus: float = 60.0
var substrate: float = 0.0
var waste: float = 0.0
## Totals, for stats and tests.
var leaf_received: float = 0.0
## Leaf fragments delivered (views play one carrier going down per delivery).
var leaf_items: int = 0
var fungus_grown: float = 0.0
## Fungus nurses have taken from the garden to feed larvae (layered nests).
var fed_mass: float = 0.0

var digest_rate: float = 0.02
var fungus_yield: float = 0.6
var upkeep_per_ant: float = 0.0002
var chamber_capacity: float = 150.0
var waste_load: float = 0.25

var _brood_budget: float = 0.0

## Share of the gardens' capacity kept back from brood (see reserve()).
var garden_reserve: float = 0.3
## The gardens, cell by cell (nests with an underground; see GardenGrid).
var garden: GardenGrid
## Fungus the colony has eaten (upkeep) and leaf pulp planted in the gardens.
var fungus_eaten: float = 0.0
var planted_mass: float = 0.0
## Leaf fragments carried down and lying by a garden, waiting to be cut up
## (item ids).
var leaf_on_floor: PackedInt32Array = []
## Spent material weeded out, and mass of it carried out of the nest.
var weeded_mass: float = 0.0
## Body reserves a founding queen feeds her garden with (as substrate, at
## queen_feed_rate per second) until the first leaf comes in.
var queen_reserve: float = 0.0
var queen_feed_rate: float = 0.15
## Gardens grow this many cells (of the nest layer) in from a chamber's walls.
const GARDEN_DEPTH := 2

func setup(sim: Simulation, owner_colony: Colony, params: Dictionary) -> void:
	brood_food_type = "gongylidia"
	# A low cone of loose soil round the hole.
	entrance_style = "mound"
	super.setup(sim, owner_colony, params)
	fungus = params.get("initial_fungus", fungus)
	digest_rate = params.get("digest_rate", digest_rate)
	fungus_yield = params.get("fungus_yield", fungus_yield)
	upkeep_per_ant = params.get("upkeep_per_ant", upkeep_per_ant)
	chamber_capacity = params.get("chamber_capacity", chamber_capacity)
	waste_load = params.get("waste_load", waste_load)
	if chambers_layout != null:
		_setup_layered(sim, owner_colony, params, &"minim")
		return
	_fit_chambers()
	if params.has("brood"):
		brood = Brood.new()
		brood.setup(sim, self, owner_colony.species, params["brood"])

func receive_item(_sim: Simulation, item: Item) -> void:
	substrate += item.mass
	leaf_received += item.mass
	leaf_items += 1

func update(sim: Simulation, dt: float) -> void:
	var colony := sim.colonies[colony_id]
	if chambers_layout != null:
		_update_layered(sim, dt)
		return
	# The garden digests fresh leaf.
	var digested := minf(substrate, digest_rate * fungus * dt)
	substrate -= digested
	fungus += digested * fungus_yield
	fungus_grown += digested * fungus_yield
	waste += digested * (1.0 - fungus_yield)
	# The colony eats from it.
	fungus = maxf(0.0, fungus - upkeep_per_ant * colony.population * dt)
	if brood != null:
		brood.update(sim, self, dt)
		_fit_chambers()
		return
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
	# With gardens cell by cell, gardeners weed spent material out themselves.
	return garden == null and waste >= waste_load

func take_waste(sim: Simulation) -> Item:
	if not has_waste():
		return null
	waste -= waste_load
	var item := sim.create_item("waste", waste_load)
	item.radius = 1.8
	item.color = Color(0.36, 0.33, 0.27)
	return item

func hash_state(ctx: HashingContext) -> void:
	# Only the brood model is hashed, so runs without it keep their old hashes.
	if brood != null:
		brood.hash_into(ctx)
	if chambers_layout != null:
		hash_underground(ctx)
		ctx.update(PackedFloat64Array([fungus, substrate, waste, queen_groomed_at, chambers_layout.count()]).to_byte_array())


# --- Underground ----------------------------------------------------------------------------

func _prepare_underground(sim: Simulation, under: Dictionary, params: Dictionary) -> Dictionary:
	var u := super._prepare_underground(sim, under, params)
	queen_reserve = float(params.get("queen_reserve", 0.0 if bool(u.get("open", true)) else 30.0))
	queen_feed_rate = float(params.get("queen_feed_rate", queen_feed_rate))
	garden_reserve = float(params.get("garden_reserve", garden_reserve))
	return u

func _setup_layered(sim: Simulation, owner_colony: Colony, params: Dictionary, first_caste: StringName) -> void:
	super._setup_layered(sim, owner_colony, params, first_caste)
	var l := sim.layers[underground_layer]
	var royal := chambers_layout.royal()
	# The founding garden in the royal chamber, grown from the starting fungus.
	garden = GardenGrid.new()
	garden.setup(Vector2(l.world.size), params.get("underground", {}))
	garden.cap = chamber_capacity / (PI * 50.0 * 50.0 / (GardenGrid.CELL * GardenGrid.CELL))
	var spot := garden_spot()
	var r2 := royal.radius * 0.62 * royal.radius * 0.62
	var layout := chambers_layout
	garden.add_chamber_where(0, Rect2(spot, Vector2.ZERO).grow(royal.radius * 0.62), func(at: Vector2) -> bool:
		return at.distance_squared_to(spot) <= r2 and layout.chamber_at(at) == 0 and layout.depth_at(at) >= GARDEN_DEPTH \
				and not layout.in_alcove(0, at) \
				and not l.world.is_blocked(at))
	for c in chambers_layout.list:
		if c.dug and c.kind == NestChambers.Kind.CHAMBER:
			_add_garden_chamber(c)
	_seed_garden(fungus)
	_sync_garden_totals(0.0)

func _update_layered(sim: Simulation, dt: float) -> void:
	var colony := sim.colonies[colony_id]
	_ensure_queen(sim)
	# The gardens grow (the M8 model per cell, see GardenGrid) and the colony
	# eats from them.
	garden.digest_rate = digest_rate
	garden.fungus_yield = fungus_yield
	var before := garden.total_fungus() + garden.total_substrate()
	garden.update(dt, sim.rng)
	fungus_eaten += garden.eat(upkeep_per_ant * colony.total_population() * dt)
	# Until the first leaf comes in, the queen manures her garden.
	if queen_reserve > 0.0 and leaf_items == 0 and queen_ant >= 0 and sim.alive[queen_ant] != 0:
		var m := minf(queen_reserve, queen_feed_rate * dt)
		if garden.plant(garden_spot(), m, chambers_layout.royal().radius * 0.4) > 0.0:
			queen_reserve -= m
			planted_mass += m
	_sync_garden_totals(before)
	_update_colony(sim, dt)

## Newly dug chambers get their garden, started with fungus from another.
func _chambers_dug(sim: Simulation) -> void:
	for c in chambers_layout.list:
		if c.dug and c.kind == NestChambers.Kind.CHAMBER and not garden.has_chamber(c.index):
			_add_garden_chamber(c)
			_seed_new_garden(sim, c.index)

## Chamber c's garden: its open floor, GARDEN_DEPTH cells in from the walls
## (its alcoves are kept for brood).
func _add_garden_chamber(c: NestChambers.Chamber) -> void:
	var layout := chambers_layout
	var w := layout.world
	var k := c.index
	var bounds := Rect2(w.cell_center(c.cells[0]), Vector2.ZERO)
	for cell in c.cells:
		bounds = bounds.expand(w.cell_center(cell))
	garden.add_chamber_where(k, bounds.grow(w.cell_size), func(at: Vector2) -> bool:
		return layout.chamber_at(at) == k and layout.depth_at(at) >= GARDEN_DEPTH and not layout.in_alcove(k, at) \
				and not w.is_blocked(at))

# --- Food and roles (ColonyNest) --------------------------------------------------------

func food_stock() -> float:
	return fungus

func eat_stock(mass: float) -> void:
	fungus -= mass

func food_point(sim: Simulation, near: Vector2) -> Vector2:
	return harvest_point(sim, near)

func take_food_at(at: Vector2, mass: float) -> float:
	return take_fungus_at(at, mass)

func return_food(at: Vector2, mass: float) -> void:
	return_fungus(at, mass)

func space_pressure() -> float:
	return garden_pressure()

func role_order() -> Array[String]:
	return ["nurse", "tend_queen", "garden", "dig"]

## Gardeners: to cut up leaf waiting by the gardens, weed, and tend.
func _count_more_roles(_sim: Simulation, workers: int) -> void:
	role_need["garden"] = ceili(leaf_on_floor.size() * 1.5 + garden.total_spent() / (waste_load * 3.0)
			+ garden.cells.size() / 2500.0) if workers >= 2 else 0

## Nothing short: minims garden by default (they mostly work inside), up to
## inside_share of them; the rest, and bigger castes, go out (or keep
## working inside while the nest is sealed).
func _idle_role(sim: Simulation, caste: int, roles: Array[String]) -> String:
	var colony := sim.colonies[colony_id]
	var inside: int = role_count.get("nurse", 0) + role_count.get("tend_queen", 0) + role_count.get("garden", 0)
	var minim := colony.species.castes[caste].id == &"minim"
	if roles.has("garden") and minim and (not has_entrance() or inside < colony.population_by_caste[caste] * inside_share):
		return "garden"
	return super._idle_role(sim, caste, roles)

## A place to harvest gongylidia near `near`: the best of a few cells of
## the nearest garden that has fungus (GardenGrid.harvest_cell).
func harvest_point(sim: Simulation, near: Vector2) -> Vector2:
	var k := _nearest_garden(near, true)
	var c := garden.harvest_cell(k, sim.rng)
	if c < 0:
		return garden_spot() if k <= 0 else chambers_layout.list[k].centre
	return garden.cell_center(c)

## Fungus the dug chambers hold: chamber_capacity per chamber of radius 50,
## scaled by area (the royal chamber holds less; the queen and brood live there).
func garden_capacity() -> float:
	if garden != null:
		return garden.capacity()
	var cap := 0.0
	for c in chambers_layout.list:
		if c.dug:
			cap += chamber_capacity * pow(c.radius / 50.0, 2.0) * (0.5 if c.kind == NestChambers.Kind.ROYAL else 1.0)
	return cap

# --- Gardens (nests with an underground) ------------------------------------------------

## Centre of the founding garden in the royal chamber.
func garden_spot() -> Vector2:
	var royal := chambers_layout.royal()
	if royal.alcoves.size() >= 2:
		# The side of the chamber away from the pupae, half way out.
		var a := (royal.centre - royal.alcoves[1]).angle()
		return _spot(0, Vector2.from_angle(a) * 0.5)
	return _spot(0, Vector2(0.3, -0.3))

## Spreads `mass` of fungus over the gardens from the founding garden's
## middle outward, filling cells to 90% of their capacity; any more is
## shared out over every cell (the gardens are then over-full, which calls
## for new chambers).
func _seed_garden(mass: float) -> void:
	var order := garden.cells.duplicate()
	var spot := garden_spot()
	var keyed: Array[Vector2] = []
	for c in order:
		keyed.append(Vector2(garden.cell_center(c).distance_squared_to(spot) + (0.0 if garden.chamber_of[c] == 0 else 1e9), c))
	keyed.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var left := mass
	for kc in keyed:
		if left <= 0.0:
			break
		var put := minf(left, garden.cap * 0.9)
		garden.add_fungus(int(kc.y), put)
		left -= put
	if left > 0.0 and not garden.cells.is_empty():
		var each := left / garden.cells.size()
		for c in garden.cells:
			garden.add_fungus(c, each)
	garden.recount()

## Mirrors the grid's totals in the M8 fields (fungus, substrate, waste).
func _sync_garden_totals(_before: float) -> void:
	fungus = garden.total_fungus()
	substrate = garden.total_substrate()
	waste = garden.total_spent()
	fungus_grown = garden.grown

## Takes up to `mass` of fungus (gongylidia) from the garden around `at`.
## Returns what was taken: 0 if the garden is at its reserve or there is
## too little here (under a quarter of `mass`, which is put back).
func take_fungus_at(at: Vector2, mass: float) -> float:
	if fungus - mass <= reserve() * 0.5:
		return 0.0
	var got := garden.take_around(at, mass)
	if got < mass * 0.25:
		if got > 0.0:
			garden.add_fungus(maxi(0, garden.cell_at(at)), got)
		return 0.0
	fed_mass += got
	fungus = garden.total_fungus()
	return got

## Puts fungus an ant was carrying back into the garden nearest `at`.
func return_fungus(at: Vector2, mass: float) -> void:
	var k := _nearest_garden(at, false)
	var c := garden.cell_at(at)
	if c < 0 or garden.chamber_of[c] == GardenGrid.NONE:
		c = garden.cells[garden.chamber_first[k]] if garden.has_chamber(k) else garden.cells[0]
	garden.add_fungus(c, mass)
	fed_mass -= mass
	fungus = garden.total_fungus()

## The garden chamber nearest `at` (with fungus, if `with_fungus`), else the
## royal chamber's founding garden (0).
func _nearest_garden(at: Vector2, with_fungus: bool) -> int:
	var best := 0
	var best_d := INF
	for c in chambers_layout.list:
		if not garden.has_chamber(c.index) or c.index == 0:
			continue
		if with_fungus and garden.fill(c.index) < 0.05:
			continue
		var d := c.centre.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = c.index
	return best

## The garden leaf should go to: where fungus grows with room to spare
## (fungus x room, so a garden that is just starting counts too).
func leaf_chamber() -> int:
	var best := 0
	var best_score := -1.0
	for c in chambers_layout.list:
		if not garden.has_chamber(c.index):
			continue
		var f := garden.fill(c.index)
		var score := minf(f, 0.25) * (1.0 - f)
		if score > best_score:
			best_score = score
			best = c.index
	return best

## Where leaf carriers drop fragments: at the edge of leaf_chamber()'s
## garden, on the side the tunnel comes in.
func leaf_drop_point(sim: Simulation) -> Vector2:
	var k := leaf_chamber()
	var c := chambers_layout.list[k]
	var at: Vector2
	if k == 0:
		var spot := garden_spot()
		at = spot + (c.centre - spot).normalized().rotated(0.6) * c.radius * 0.5 + Vector2.from_angle(sim.rng.randf() * TAU) * 3.0
	else:
		var inward := (c.centre - c.door).normalized()
		at = c.door + inward * c.radius * 0.25 + inward.orthogonal() * sim.rng.randf_range(-0.5, 0.5) * c.radius * 0.6
	# Irregular chambers: somewhere else on its floor if that missed it.
	if chambers_layout.chamber_at(at) != k or chambers_layout.world.is_blocked(at):
		at = chambers_layout.random_point(k, sim.rng, 2)
	return at

## A fragment arrives underground (dropped at a garden's edge).
func leaf_arrived(sim: Simulation, item: Item) -> void:
	leaf_items += 1
	leaf_received += item.mass
	sim.colonies[colony_id].delivered_items += 1
	leaf_on_floor.append(item.id)

## Claims the unclaimed fragment lying nearest `at` for ant i to cut up.
## Returns the item, or null.
func claim_fragment(sim: Simulation, i: int, at: Vector2) -> Item:
	var best: Item = null
	var best_d := INF
	for id in leaf_on_floor:
		var item: Item = sim.items.get(id)
		if item == null or item.reserved_by >= 0 or item.carrier >= 0:
			continue
		var d := item.position.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = item
	if best != null:
		best.reserved_by = i
	return best

## Cuts a bite of pulp (up to `mass`) off a fragment. The fragment shrinks,
## and is gone once used up. Returns the pulp item (for the cutter to carry).
func cut_pulp(sim: Simulation, fragment: Item, mass: float) -> Item:
	var take := minf(mass, fragment.mass)
	var pulp := sim.create_item("pulp", take)
	pulp.source_id = fragment.source_id
	pulp.radius = 1.2 + take * 1.2
	pulp.color = Color(0.42, 0.62, 0.24)
	var left := fragment.mass - take
	if left <= 1e-4:
		var k := leaf_on_floor.find(fragment.id)
		if k >= 0:
			leaf_on_floor.remove_at(k)
		sim.destroy_item(fragment.id)
	else:
		fragment.pixel_size *= sqrt(left / fragment.mass)
		fragment.mass = left
		sim.items_version += 1
	return pulp

## Where to plant pulp in chamber k (a cell on the garden's surface or
## edge), or the chamber's middle if none looks good.
func plant_point(sim: Simulation, k: int) -> Vector2:
	var c := garden.plant_cell(k, sim.rng)
	if c < 0:
		return garden_spot() if k == 0 else chambers_layout.list[k].centre
	return garden.cell_center(c)

## Plants a pulp item's leaf at `at`: it becomes substrate in the garden,
## and counts as delivered to the colony.
func plant_pulp(sim: Simulation, at: Vector2, pulp: Item) -> void:
	var planted := garden.plant(at, pulp.mass)
	if planted <= 0.0:
		at = plant_point(sim, _nearest_garden(at, false))
		planted = garden.plant(at, pulp.mass)
	_inoculate(sim, at, pulp.mass * 0.15)
	planted_mass += planted
	sim.colonies[colony_id].delivered_mass += planted
	substrate = garden.total_substrate()

## A spot with spent material or mould to weed out, in the chamber with the
## most spent material, or Vector2.INF if there is little to do.
func weed_point(sim: Simulation) -> Vector2:
	if not has_entrance():
		# Sealed: no way to carry it out yet.
		return Vector2.INF
	var best := -1
	var most := waste_load
	for c in chambers_layout.list:
		if garden.has_chamber(c.index):
			var s := garden.spent_in(c.index)
			if s > most:
				most = s
				best = c.index
	if best < 0:
		return Vector2.INF
	var cell := garden.weed_cell(best, sim.rng, waste_load * 0.05)
	return garden.cell_center(cell) if cell >= 0 else Vector2.INF

## Weeds up to a load of spent material at `at`; returns a waste item for
## the gardener to carry out, or null if there was nothing.
func weed_at(sim: Simulation, at: Vector2) -> Item:
	var got := garden.weed(at, waste_load)
	waste = garden.total_spent()
	if got <= waste_load * 0.05:
		# Hardly anything: leave the crumbs for a later round.
		if got > 0.0:
			garden.spent[maxi(0, garden.cell_at(at))] += got
			garden.recount()
		return null
	weeded_mass += got
	var item := sim.create_item("waste", got)
	item.radius = 1.6
	item.color = Color(0.4, 0.34, 0.24)
	return item

## Fungus kept back from brood: brood_reserve; in a nest whose gardens are
## cells in chambers, garden_reserve of what they can hold (unless 0), so the gardens
## fill up (and grow faster) before brood takes the surplus, and grow on as
## new chambers are dug.
func reserve() -> float:
	if garden == null or garden_reserve <= 0.0:
		return brood_reserve
	return maxf(1.0, garden.capacity() * garden_reserve)

## How full the gardens will be once the pulp waiting on them has grown
## (1 = full).
func garden_pressure() -> float:
	var cap := garden_capacity()
	return (fungus + substrate * fungus_yield) / cap if cap > 0.0 else 0.0

## Pulp planted where no fungus grows yet (a new chamber) gets a pinch of
## fungus brought from the fullest garden, so the new garden can start.
## The fungus is moved, not made.
func _inoculate(sim: Simulation, at: Vector2, mass: float) -> void:
	var c := garden.cell_at(at)
	if c < 0 or garden.chamber_of[c] == GardenGrid.NONE or garden.fungus[c] > 0.0 or garden._neighbour_fungus(c):
		return
	var donor := -1
	var best := 0.3
	for ch in chambers_layout.list:
		if garden.has_chamber(ch.index) and ch.index != garden.chamber_of[c]:
			var f := garden.fill(ch.index)
			if f > best:
				best = f
				donor = ch.index
	if donor < 0:
		return
	var from := garden.harvest_cell(donor, sim.rng)
	if from < 0:
		return
	var moved := garden.take_fungus(from, mass)
	if moved > 0.0:
		garden.add_fungus(c, moved)


## A newly dug garden chamber gets a start: gardeners carry in a little
## fungus from the fullest garden (moved, not made), planted at its middle.
func _seed_new_garden(sim: Simulation, k: int) -> void:
	var donor := -1
	var best := 0.0
	for ch in chambers_layout.list:
		if garden.has_chamber(ch.index) and ch.index != k:
			var f := garden.fill(ch.index)
			if f > best:
				best = f
				donor = ch.index
	if donor < 0:
		return
	var want := minf(3.0, fungus * 0.08)
	var moved := 0.0
	for n in 12:
		var from := garden.harvest_cell(donor, sim.rng)
		if from < 0:
			break
		moved += garden.take_fungus(from, minf(want - moved, garden.fungus_at(from) * 0.5))
		if moved >= want:
			break
	if moved <= 0.0:
		return
	var centre := chambers_layout.list[k].centre
	var cells: PackedInt32Array = []
	for c in garden.cells.slice(garden.chamber_first[k], garden.chamber_first[k] + garden.chamber_count[k]):
		if garden.cell_center(c).distance_to(centre) < 8.0:
			cells.append(c)
	if cells.is_empty():
		cells.append(garden.cells[garden.chamber_first[k]])
	for c in cells:
		garden.add_fungus(c, moved / cells.size())

