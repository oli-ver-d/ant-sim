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
##       while fungus stays above brood_reserve, up to max_population.
##       By default new ants appear at once; with nest_params "brood" the
##       queen lays eggs that develop into workers (see LeafcutterBrood)
##
## So growth is limited by the garden, which is limited by leaf supply: a
## colony cut off from leaves stops growing and its garden slowly shrinks.
## The garden fills chambers of chamber_capacity fungus; a new chamber is dug
## when the last one is nearly full (up to max_chambers). Waste is carried out
## in loads of waste_load mass by carry_waste workers to a dump beside the
## entrance (`dump`: offset from the entrance).
##
## With nest_params "underground" the nest digs its own underground (see
## NestType) and everything in it is simulated:
##   - chambers (FungusChambers): the royal chamber, then garden chambers
##     planned as the garden fills them and dug by the workers;
##   - the queen, a real ant ("queen" state) in the royal chamber, laying
##     eggs at the tip of her abdomen; brood with care on (LeafcutterBrood:
##     positioned, needs nurses to move, feed, groom and free it);
##   - minims take nest roles by colony need (nest_role: nurse, tend_queen,
##     dig, or up to the surface), medias dig or go out to forage;
##   - a founding nest ("open": false) starts sealed: the queen tends her
##     brood alone until workers hatch, and once there are open_entrance_at
##     workers they dig the entrance shaft open.
##
## params: radius, sense_radius, initial_fungus, digest_rate, fungus_yield,
##         upkeep_per_ant, ant_cost, brood_reserve, brood_rate,
##         max_population, chamber_capacity, max_chambers, waste_load, dump,
##         brood (optional, see LeafcutterBrood), underground (optional, see
##         NestType and FungusChambers) with, for it: open_entrance_at,
##         brood_per_nurse, retinue_max, dig_fraction, queen_groom_time,
##         queen_reserve (a sealed nest: 30), queen_feed_rate, initial_chambers

var fungus: float = 60.0
var substrate: float = 0.0
var waste: float = 0.0
var chambers: int = 1
## Totals, for stats and tests.
var leaf_received: float = 0.0
## Leaf fragments delivered (views play one carrier going down per delivery).
var leaf_items: int = 0
var fungus_grown: float = 0.0
var ants_raised: int = 0
## Fungus nurses have taken from the garden to feed larvae (layered nests).
var fed_mass: float = 0.0

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
## Egg-to-worker brood model, or null for the instant-spawn path.
var brood: LeafcutterBrood

# --- Underground (layered) state -------------------------------------------------------
## The nest's chambers, or null without an underground.
var chambers_layout: FungusChambers
## The queen's ant index (-1 until she is placed).
var queen_ant: int = -1
## Workers needed before a sealed nest digs its entrance open.
var open_entrance_at: int = 4
var brood_per_nurse: float = 6.0
var retinue_max: int = 5
var dig_fraction: float = 0.3
## Share of a caste that works inside when no role is short (see pick_role).
var inside_share: float = 0.6
## Seconds a grooming keeps the queen laying at her full pace.
var queen_groom_time: float = 60.0
## Simulated time the queen was last groomed.
var queen_groomed_at: float = 0.0
## Ants per role state (counted once a second) and the roles wanted then.
var role_count: Dictionary[String, int] = {}
var role_need: Dictionary[String, int] = {}
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
## queen_feed_rate per second) while the nest is sealed and has no leaf.
var queen_reserve: float = 0.0
var queen_feed_rate: float = 0.05
var _entrance_planned: bool = false
var _role_timer: float = 0.0

func setup(sim: Simulation, owner_colony: Colony, params: Dictionary) -> void:
	var p := params
	if params.has("underground"):
		p = params.duplicate()
		p["underground"] = _prepare_underground(sim, params["underground"], params)
	super.setup(sim, owner_colony, p)
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
	if chambers_layout != null:
		_setup_layered(sim, owner_colony, params)
		return
	_fit_chambers()
	if params.has("brood"):
		brood = LeafcutterBrood.new()
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

func dump_position() -> Vector2:
	return position + dump_offset

func hash_state(ctx: HashingContext) -> void:
	# Only the brood model is hashed, so runs without it keep their old hashes.
	if brood != null:
		brood.hash_into(ctx)
	if chambers_layout != null:
		hash_underground(ctx)
		ctx.update(PackedFloat64Array([fungus, substrate, waste, queen_groomed_at, chambers_layout.count()]).to_byte_array())

# --- Underground ----------------------------------------------------------------------------

## Lays out the chambers and fills in the NestType underground params: the
## shaft, the royal chamber carved out, and (when open) the shaft's tunnel.
func _prepare_underground(sim: Simulation, under: Dictionary, params: Dictionary) -> Dictionary:
	var u := under.duplicate()
	var size := ScenarioEvents.vec2(u.get("size", [1280, 1280]))
	chambers_layout = FungusChambers.new()
	chambers_layout.setup(size, sim.rng.seed, u)
	var shaft := chambers_layout.shaft
	var royal := chambers_layout.royal()
	u["shaft"] = [shaft.x, shaft.y]
	var carve: Array = [{"center": [royal.centre.x, royal.centre.y], "radius": royal.radius}]
	if bool(u.get("open", true)):
		var r := float(u.get("shaft_radius", 10.0))
		carve.append({"from": [royal.centre.x, royal.centre.y], "to": [shaft.x, shaft.y], "radius": chambers_layout.tunnel_radius})
		carve.append({"center": [shaft.x, shaft.y], "radius": r})
	u["carve"] = carve
	open_entrance_at = int(params.get("open_entrance_at", open_entrance_at))
	brood_per_nurse = float(params.get("brood_per_nurse", brood_per_nurse))
	retinue_max = int(params.get("retinue_max", retinue_max))
	dig_fraction = float(params.get("dig_fraction", dig_fraction))
	queen_groom_time = float(params.get("queen_groom_time", queen_groom_time))
	queen_reserve = float(params.get("queen_reserve", 0.0 if bool(u.get("open", true)) else 30.0))
	queen_feed_rate = float(params.get("queen_feed_rate", queen_feed_rate))
	return u

func _setup_layered(sim: Simulation, owner_colony: Colony, params: Dictionary) -> void:
	var l := sim.layers[underground_layer]
	var royal := chambers_layout.royal()
	royal.nav_field = l.nav().set_target_point(&"chamber:0", royal.centre)
	# An established nest starts with garden chambers already dug.
	for n in int(params.get("initial_chambers", 0)):
		var ch := chambers_layout.propose()
		if ch != null:
			chambers_layout.add_dug(ch, l.world, l.nav())
	# The entrance shaft of a sealed nest takes extra digging (it goes all
	# the way up to the surface).
	if not portal.open:
		var hard := float(params["underground"].get("shaft_hardness", 3.0))
		for c in l.world.cells_in_segment(chambers_layout.shaft, chambers_layout.shaft, float(params["underground"].get("shaft_radius", 10.0))):
			if l.world.is_soil(c):
				l.world.soil[c] *= hard
	_entrance_planned = portal.open
	chambers = chambers_layout.dug_count()
	var b: Dictionary = params.get("brood", {}).duplicate()
	b["care"] = true
	if not b.has("first_caste"):
		b["first_caste"] = owner_colony.species.caste_index(&"minim")
	if not b.has("first_workers"):
		b["first_workers"] = 12
	brood = LeafcutterBrood.new()
	brood.setup(sim, self, owner_colony.species, b)
	# The founding garden in the royal chamber, grown from the starting fungus.
	garden = GardenGrid.new()
	garden.setup(Vector2(l.world.size), params.get("underground", {}))
	garden.cap = chamber_capacity / (PI * 50.0 * 50.0 / (GardenGrid.CELL * GardenGrid.CELL))
	garden.add_chamber(0, garden_spot(), royal.radius * 0.5)
	for c in chambers_layout.list:
		if c.dug and c.kind == FungusChambers.Kind.GARDEN:
			garden.add_chamber(c.index, c.centre, c.radius * 0.9)
	_seed_garden(fungus)
	_sync_garden_totals(0.0)

func _update_layered(sim: Simulation, dt: float) -> void:
	var colony := sim.colonies[colony_id]
	if queen_ant < 0:
		queen_ant = spawn_initial(sim, colony.species.caste_index(&"queen"))
	# The gardens grow (the M8 model per cell, see GardenGrid) and the colony
	# eats from them.
	garden.digest_rate = digest_rate
	garden.fungus_yield = fungus_yield
	var before := garden.total_fungus() + garden.total_substrate()
	garden.update(dt, sim.rng)
	fungus_eaten += garden.eat(upkeep_per_ant * colony.population * dt)
	# A sealed founding nest gets no leaf: the queen manures her garden.
	if queen_reserve > 0.0 and not has_entrance() and queen_ant >= 0 and sim.alive[queen_ant] != 0:
		var m := minf(queen_reserve, queen_feed_rate * dt)
		if garden.plant(garden_spot(), m, chambers_layout.royal().radius * 0.4) > 0.0:
			queen_reserve -= m
			planted_mass += m
	_sync_garden_totals(before)
	brood.update(sim, self, dt)
	_role_timer -= dt
	if _role_timer <= 0.0:
		_role_timer = 1.0
		_count_roles(sim)
		var workers := workers_alive(sim)
		if not _entrance_planned and workers >= open_entrance_at:
			_plan_entrance()
		_plan_chambers()
	if chambers_layout.update_dug(plan) > 0:
		chambers = chambers_layout.dug_count()
		for c in chambers_layout.list:
			if c.dug and c.kind == FungusChambers.Kind.GARDEN and not garden.has_chamber(c.index):
				garden.add_chamber(c.index, c.centre, c.radius * 0.9)

## Ants of this colony other than the queen.
func workers_alive(sim: Simulation) -> int:
	var q := 1 if queen_ant >= 0 and sim.alive[queen_ant] != 0 else 0
	return sim.colonies[colony_id].population - q

## True while there are no workers yet: the founding queen cares for her
## brood herself.
func queen_cares(sim: Simulation) -> bool:
	return workers_alive(sim) == 0

## Seconds between eggs now: the queen lays at `base` while groomed (or
## founding alone), at half the pace when her retinue has neglected her.
func lay_interval_now(sim: Simulation, base: float) -> float:
	if queen_cares(sim) or sim.time() - queen_groomed_at <= queen_groom_time:
		return base
	return base * 2.0

## Where the queen sits in the royal chamber.
func queen_spot() -> Vector2:
	var royal := chambers_layout.royal()
	return royal.centre + Vector2(-royal.radius * 0.22, royal.radius * 0.05)

## The chamber brood lives in: the first garden chamber dug, else the royal one.
func brood_chamber() -> int:
	for c in chambers_layout.list:
		if c.kind == FungusChambers.Kind.GARDEN and c.dug:
			return c.index
	return 0

## Centre of a brood pile (LeafcutterBrood.Pile): eggs beside the queen,
## larvae in the garden, pupae at a drier spot near the wall.
func pile_centre(p: int) -> Vector2:
	var royal := chambers_layout.royal()
	match p:
		LeafcutterBrood.Pile.EGGS, LeafcutterBrood.Pile.QUEEN:
			return royal.centre + Vector2(royal.radius * 0.3, royal.radius * 0.22)
		LeafcutterBrood.Pile.LARVAE:
			var k := brood_chamber()
			var c := chambers_layout.list[k]
			return c.centre + (Vector2(royal.radius * 0.28, -royal.radius * 0.35) if k == 0 else Vector2(-c.radius * 0.25, 0.0))
		_:
			var k := brood_chamber()
			var c := chambers_layout.list[k]
			return c.centre + (Vector2(-royal.radius * 0.1, -royal.radius * 0.62) if k == 0 else Vector2(c.radius * 0.45, c.radius * 0.3))

## Position of slot `s` in pile p: a sunflower spiral out from the centre.
func pile_slot(p: int, s: int) -> Vector2:
	var spacing := 1.5 if p == LeafcutterBrood.Pile.EGGS else (3.6 if p == LeafcutterBrood.Pile.LARVAE else 4.4)
	return pile_centre(p) + Vector2.from_angle(s * 2.39996) * spacing * sqrt(s + 0.5)

## A place to harvest gongylidia near `near`: the best of a few cells of
## the nearest garden that has fungus (GardenGrid.harvest_cell).
func harvest_point(sim: Simulation, near: Vector2) -> Vector2:
	var k := _nearest_garden(near, true)
	var c := garden.harvest_cell(k, sim.rng)
	if c < 0:
		return garden_spot() if k <= 0 else chambers_layout.list[k].centre
	return garden.cell_center(c)

## Nav field (on the nest's layer) of the chamber containing `at`, or the
## portal's field outside chambers.
func field_toward(at: Vector2) -> int:
	var k := chambers_layout.chamber_at(at)
	if k >= 0:
		return chambers_layout.list[k].nav_field
	return portal.nav_field

## Radius of the chamber containing `at` (how close to it an ant can head
## straight there), or 0.
func direct_range(at: Vector2) -> float:
	var k := chambers_layout.chamber_at(at)
	return chambers_layout.list[k].radius if k >= 0 else 0.0

## Places a colony's starting ant: the queen at her spot in the royal
## chamber, workers in the royal chamber taking nest roles.
func spawn_initial(sim: Simulation, caste: int) -> int:
	if chambers_layout == null:
		return super.spawn_initial(sim, caste)
	var colony := sim.colonies[colony_id]
	var royal := chambers_layout.royal()
	if colony.species.castes[caste].id == &"queen":
		var q := sim.spawn_ant(colony, caste, queen_spot(), 0.0, underground_layer)
		queen_ant = q
		return q
	var at := royal.centre + Vector2.from_angle(sim.rng.randf() * TAU) * royal.radius * 0.6 * sqrt(sim.rng.randf())
	var i := sim.spawn_ant(colony, caste, at, sim.rng.randf_range(-PI, PI), underground_layer)
	if i >= 0:
		sim.change_state(i, first_state(sim, caste))
	return i

## The state a new worker of `caste` starts in underground: a nest role if
## the caste takes them, else straight up to the surface.
func first_state(sim: Simulation, caste: int) -> String:
	var idx: int = sim.behaviour_index.get("nest_role", -1)
	return "nest_role" if idx >= 0 and sim.colonies[colony_id].allows(caste, idx) else "go_up"

## A new worker coming up for the first time is pointed out by views.
func ant_surfaced(sim: Simulation, i: int) -> void:
	if brood == null:
		return
	for k in LeafcutterBrood.EVENT_LOG:
		if brood.emerge_ants[k] == i and sim.tick_count - brood.emerge_ticks[k] < 60 * sim.config.tick_rate:
			highlight_ant = i
			return

## Counts ants per role state and works out how many each role needs.
func _count_roles(sim: Simulation) -> void:
	role_count.clear()
	var col := colony_id
	for i in sim.high_water:
		if sim.alive[i] == 0 or sim.colony_id[i] != col:
			continue
		var s := sim.state_id(i)
		role_count[s] = role_count.get(s, 0) + 1
	role_count["dig"] = role_count.get("dig", 0) + role_count.get("carry_spoil", 0)
	var workers := workers_alive(sim)
	role_need.clear()
	role_need["nurse"] = ceili(brood.count() / brood_per_nurse) if brood.count() > 0 else 0
	@warning_ignore("integer_division")
	role_need["tend_queen"] = clampi(workers / 25, 1, retinue_max) if workers >= 3 else 0
	var dig_work := 0
	var dig_slots := 0
	for job in plan.jobs:
		if plan.is_open(job):
			dig_work += job.remaining
			dig_slots += job.max_diggers
	# Digging gets more hands the fuller the gardens are.
	var dig_cap := maxi(2, int(workers * dig_fraction * clampf(garden_pressure(), 0.3, 1.0)))
	role_need["dig"] = mini(mini(ceili(dig_work / 20.0), dig_cap), dig_slots) if dig_work > 0 else 0
	# Gardeners: to cut up leaf waiting by the gardens, weed, and tend.
	role_need["garden"] = ceili(leaf_on_floor.size() * 1.5 + garden.total_spent() / (waste_load * 3.0)
			+ garden.cells.size() / 2500.0) if workers >= 2 else 0

## The role (state id) a worker of `caste` should take now: the one most
## short of ants, or up to the surface if none is (or keep nursing while
## the nest is sealed).
func pick_role(sim: Simulation, caste: int) -> String:
	var colony := sim.colonies[colony_id]
	var roles: Array[String] = []
	for r: String in ["nurse", "tend_queen", "garden", "dig"]:
		if colony.allows(caste, sim.behaviour_index[r]):
			roles.append(r)
	var best := ""
	var best_short := 0
	for r in roles:
		var short: int = role_need.get(r, 0) - role_count.get(r, 0)
		if short > best_short:
			best_short = short
			best = r
	if best == "":
		# Nothing short: gardeners by default (minims mostly work inside),
		# up to inside_share of the caste; the rest go out.
		var inside: int = role_count.get("nurse", 0) + role_count.get("tend_queen", 0) + role_count.get("garden", 0)
		if roles.has("garden") and (not has_entrance() or inside < colony.population_by_caste[caste] * inside_share):
			best = "garden"
		elif has_entrance():
			best = "go_up"
		else:
			best = roles[0] if not roles.is_empty() else "go_up"
	role_count[best] = role_count.get(best, 0) + 1
	return best

## Plans the entrance shaft: a tunnel from the royal chamber to the bottom of
## the shaft, then the shaft itself, which opens the portal when done.
func _plan_entrance() -> void:
	_entrance_planned = true
	var royal := chambers_layout.royal()
	var shaft := chambers_layout.shaft
	var dir := (shaft - royal.centre).normalized()
	var start := royal.centre + dir * royal.radius * 0.8
	plan.add_job("entrance_tunnel", start, start, shaft, chambers_layout.tunnel_radius, -2.0, 4)
	var job := plan.add_job("entrance", shaft - dir * 6.0, shaft, shaft, maxf(8.0, portal.radius * 0.8), -1.0, 4)
	plan.open_portal_when_done(job, portal)

## Plans a new garden chamber when the gardens (with the pulp waiting on
## them) are nearly filling the ones
## dug (one at a time, up to max_chambers).
func _plan_chambers() -> void:
	if not has_entrance() or chambers_layout.count() >= max_chambers:
		return
	# One chamber at a time, or two when the gardens are overflowing.
	var undug := 0
	for c in chambers_layout.list:
		if not c.dug:
			undug += 1
	var pressure := garden_pressure()
	if pressure < 0.8 or undug >= (2 if pressure > 1.2 else 1):
		return
	var ch := chambers_layout.propose()
	if ch != null:
		chambers_layout.add(ch, plan, float(ch.index))

## Fungus the dug chambers hold: chamber_capacity per chamber of radius 50,
## scaled by area (the royal chamber holds less; the queen and brood live there).
func garden_capacity() -> float:
	if garden != null:
		return garden.capacity()
	var cap := 0.0
	for c in chambers_layout.list:
		if c.dug:
			cap += chamber_capacity * pow(c.radius / 50.0, 2.0) * (0.5 if c.kind == FungusChambers.Kind.ROYAL else 1.0)
	return cap

# --- Gardens (nests with an underground) ------------------------------------------------

## Centre of the founding garden in the royal chamber.
func garden_spot() -> Vector2:
	var royal := chambers_layout.royal()
	return royal.centre + Vector2(royal.radius * 0.3, -royal.radius * 0.3)

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

## Takes `mass` of fungus (gongylidia) from the garden cell at `at`. False
## (nothing taken) if the cell hasn't enough or the garden is at its reserve.
func take_fungus_at(at: Vector2, mass: float) -> bool:
	if fungus - mass <= reserve() * 0.5:
		return false
	var got := garden.take_around(at, mass)
	if got < mass * 0.999:
		# Not enough here: put it back and try elsewhere.
		if got > 0.0:
			garden.add_fungus(maxi(0, garden.cell_at(at)), got)
		return false
	fed_mass += mass
	fungus = garden.total_fungus()
	return true

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

## The garden chamber leaf should go to: the one with the most room.
func leaf_chamber() -> int:
	var best := 0
	var best_fill := INF
	for c in chambers_layout.list:
		if c.index == 0 or not garden.has_chamber(c.index):
			continue
		var f := garden.fill(c.index)
		if f < best_fill:
			best_fill = f
			best = c.index
	return best

## Where leaf carriers drop fragments: at the edge of leaf_chamber()'s
## garden, on the side the tunnel comes in.
func leaf_drop_point(sim: Simulation) -> Vector2:
	var k := leaf_chamber()
	var c := chambers_layout.list[k]
	if k == 0:
		var spot := garden_spot()
		return spot + (c.centre - spot).normalized().rotated(0.6) * c.radius * 0.5 \
				+ Vector2.from_angle(sim.rng.randf() * TAU) * 3.0
	var inward := (c.centre - c.door).normalized()
	return c.door + inward * c.radius * 0.25 + inward.orthogonal() * sim.rng.randf_range(-0.5, 0.5) * c.radius * 0.6

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
	if got <= 1e-5:
		return null
	weeded_mass += got
	var item := sim.create_item("waste", got)
	item.radius = 1.6
	item.color = Color(0.4, 0.34, 0.24)
	return item

## Fungus kept back from brood: brood_reserve, but in a nest whose gardens
## are cells in chambers at most a fifth of what they can hold (a founding
## garden is small).
func reserve() -> float:
	if garden == null:
		return brood_reserve
	return minf(brood_reserve, garden.capacity() * 0.2)

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

## True if some role other than `except` has fewer ants than it needs (as
## of the last count), so an idle worker should go and take one.
func short_elsewhere(except: String) -> bool:
	for r: String in role_need:
		if r != except and role_need[r] > role_count.get(r, 0):
			return true
	return false
