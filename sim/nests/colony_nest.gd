class_name ColonyNest
extends NestType
## Base for a species nest with a queen, brood and (optionally) an
## underground it digs itself. The species nest adds what the colony lives on
## (its food store) and the work that goes with it; this class has what every
## such nest shares:
##
##   - the economy's shared params (ant_cost, brood_rate, brood_reserve,
##     max_population) and the brood model (Brood; nest_params "brood");
##   - with nest_params "underground" (see NestType) everything in it is
##     simulated:
##       - chambers (NestChambers): the royal chamber, then chambers planned
##         as the nest runs short of room (space_pressure()) and dug by the
##         workers, up to max_chambers;
##       - the queen, a real ant ("queen" state) in the royal chamber, laying
##         eggs at the tip of her abdomen; brood with care on (Brood:
##         positioned, needs nurses to move, feed, groom and free it);
##       - workers take nest roles by colony need (nest_role: nurse,
##         tend_queen, dig, the species' own roles, or up to the surface);
##       - a founding nest ("open": false) starts sealed: the queen tends her
##         brood alone until workers hatch, and once there are
##         open_entrance_at workers they dig the entrance shaft open;
##       - more entrances as the colony grows (nest_params "entrances").
##
## Species nests provide the food interface below (food_stock(), eat_stock(),
## food_point(), take_food_at(), return_food(), make_brood_food()) and
## space_pressure(), and may add roles (role_order(), _count_more_roles(),
## _idle_role()).
##
## params: radius, sense_radius, ant_cost, brood_reserve, brood_rate,
##         max_population, max_chambers, dump, brood (optional, see Brood),
##         underground (optional, see NestType and NestChambers) with, for it:
##         open_entrance_at, brood_per_nurse, retinue_max, dig_fraction,
##         inside_share, queen_groom_time, initial_chambers, entrances,
##         shaft_hardness (in underground)

var ant_cost: float = 1.5
var brood_reserve: float = 30.0
var brood_rate: float = 0.004
var max_population: int = 3000
var max_chambers: int = 5
## Chambers dug (with an underground), or the chambers the store fills.
var chambers: int = 1
var ants_raised: int = 0
## Where refuse is dumped, relative to the nest's position.
var dump_offset: Vector2 = Vector2(120, 40)
## Egg-to-worker brood model, or null for a species' own growth.
var brood: Brood
## Item type nurses carry to larvae (see make_brood_food()).
var brood_food_type: String = ""

# --- Underground (layered) state -------------------------------------------------------
## The nest's chambers, or null without an underground.
var chambers_layout: NestChambers
## The queen's ant index (-1 until she is placed).
var queen_ant: int = -1
## Workers needed before a sealed nest digs its entrance open.
var open_entrance_at: int = 4
## Larvae a nurse can feed (eggs and pupae: four times as many).
var brood_per_nurse: float = 2.5
var retinue_max: int = 5
var dig_fraction: float = 0.3
## How much each role's shortfall counts when choosing (see pick_role; 1 if
## not listed).
var role_weight: Dictionary = {"nurse": 3.0, "tend_queen": 1.5, "dig": 1.2}
## Share of a caste that works inside when no role is short (see _idle_role).
var inside_share: float = 0.6
## Seconds a grooming keeps the queen laying at her full pace.
var queen_groom_time: float = 60.0
## Simulated time the queen was last groomed.
var queen_groomed_at: float = 0.0
## Ants per role state (counted once a second) and the roles wanted then.
var role_count: Dictionary[String, int] = {}
var role_need: Dictionary[String, int] = {}
var _entrance_planned: bool = false
## Colony sizes at which another entrance is dug (nest_params "entrances":
## {"at": [900, 2200], "spacing": 150}), and how far apart entrances are.
var entrance_steps: PackedInt32Array = []
var entrance_spacing: float = 150.0
var _entrance_retry_at: float = 0.0
var _role_timer: float = 0.0
var _plan_retry_at: float = 0.0
var _rescue_timer: float = 60.0
## Cached places in chambers (see _spot).
var _spots: Dictionary[Vector3, Vector2] = {}
## Default roughness of dug outlines (nest_params underground "overdig").
const OVERDIG := 4.5
## Seconds after which a chamber whose way in hasn't opened stops holding up
## new ones (see _plan_chambers).
const STUCK_CHAMBER := 600.0
## Seconds before trying again when no new chamber fits.
const PLAN_RETRY := 30.0

func setup(sim: Simulation, owner_colony: Colony, params: Dictionary) -> void:
	var p := params
	if params.has("underground"):
		p = params.duplicate()
		p["underground"] = _prepare_underground(sim, params["underground"], params)
	super.setup(sim, owner_colony, p)
	ant_cost = params.get("ant_cost", ant_cost)
	brood_reserve = params.get("brood_reserve", brood_reserve)
	brood_rate = params.get("brood_rate", brood_rate)
	max_population = int(params.get("max_population", max_population))
	max_chambers = int(params.get("max_chambers", max_chambers))
	if params.has("dump"):
		dump_offset = ScenarioEvents.vec2(params["dump"])

func dump_position() -> Vector2:
	return position + dump_offset

# --- What the colony lives on (species nests override) ---------------------------------

## Food the colony has in store (paces the queen's laying: brood_rate * it).
func food_stock() -> float:
	return 0.0

## Takes `mass` off the store (larvae eating, without brood care).
func eat_stock(_mass: float) -> void:
	pass

## Food kept back from brood: larvae aren't fed and the queen doesn't lay
## while the store is at or below it.
func reserve() -> float:
	return brood_reserve

## Where a nurse fetches food for a larva lying near `near`.
func food_point(_sim: Simulation, near: Vector2) -> Vector2:
	return near

## Takes up to `mass` of food from the store around `at`; returns what was
## taken (0 if there is too little).
func take_food_at(_at: Vector2, _mass: float) -> float:
	return 0.0

## Puts food an ant was carrying back into the store nearest `at`.
func return_food(_at: Vector2, _mass: float) -> void:
	pass

## The item a nurse carries `mass` of food to a larva in (of brood_food_type).
func make_brood_food(sim: Simulation, mass: float) -> Item:
	var item := sim.create_item(brood_food_type, mass)
	item.radius = 1.3
	item.color = Color(0.95, 0.94, 0.86)
	return item

## How short of room the nest is (1 = full): a new chamber is planned from 0.8.
func space_pressure() -> float:
	return 0.0

# --- Underground ----------------------------------------------------------------------------

## Lays out the chambers and fills in the NestType underground params: the
## shaft, the royal chamber carved out, and (when open) the shaft's tunnel.
## Soil has texture (clay, roots, stones), dug walls are rough and busy
## tunnels become highways unless the scenario says otherwise.
func _prepare_underground(sim: Simulation, under: Dictionary, params: Dictionary) -> Dictionary:
	var u := under.duplicate()
	var size := ScenarioEvents.vec2(u.get("size", [1280, 1280]))
	if not u.has("texture"):
		u["texture"] = {}
	if not u.has("overdig"):
		u["overdig"] = OVERDIG
	# Busy tunnels become highways, with lanes (see Highways).
	if not u.has("highways"):
		u["highways"] = {}
	chambers_layout = NestChambers.new()
	chambers_layout.setup(size, sim.rng.seed, u)
	var shaft := chambers_layout.shaft
	var royal := chambers_layout.royal()
	u["shaft"] = [shaft.x, shaft.y]
	var carve: Array = [chambers_layout.royal_carve()]
	if bool(u.get("open", true)):
		var r := float(u.get("shaft_radius", 10.0))
		carve.append({"from": [royal.centre.x, royal.centre.y], "to": [shaft.x, shaft.y], "radius": chambers_layout.tunnel_radius})
		carve.append({"center": [shaft.x, shaft.y], "radius": r})
	u["carve"] = carve
	# No stones between the royal chamber and the shaft (the first tunnel).
	var clear: Array = u.get("keep_clear", []).duplicate()
	for k in 6:
		var p := royal.centre.lerp(shaft, k / 5.0)
		clear.append([p.x, p.y, chambers_layout.tunnel_radius + 10.0])
	u["keep_clear"] = clear
	open_entrance_at = int(params.get("open_entrance_at", open_entrance_at))
	brood_per_nurse = float(params.get("brood_per_nurse", brood_per_nurse))
	retinue_max = int(params.get("retinue_max", retinue_max))
	dig_fraction = float(params.get("dig_fraction", dig_fraction))
	inside_share = float(params.get("inside_share", inside_share))
	queen_groom_time = float(params.get("queen_groom_time", queen_groom_time))
	return u

## Sets up the underground once the layer exists: chambers, the sealed shaft,
## highways, entrances and the brood (with care). `first_caste` is the caste
## id of a founding colony's first workers (nest_params brood "first_caste"
## overrides it with an index).
func _setup_layered(sim: Simulation, owner_colony: Colony, params: Dictionary, first_caste: StringName) -> void:
	var l := sim.layers[underground_layer]
	chambers_layout.attach(l)
	var royal := chambers_layout.royal()
	royal.nav_field = l.nav().set_target_point(&"chamber:0", royal.centre)
	# An established nest starts with chambers already dug.
	for n in int(params.get("initial_chambers", 0)):
		chambers_layout.plan_chamber(plan, float(n + 1), true)
	# The entrance shaft of a sealed nest takes extra digging (it goes all
	# the way up to the surface).
	if not portal.open:
		var hard := float(params["underground"].get("shaft_hardness", 3.0))
		for c in l.world.cells_in_segment(chambers_layout.shaft, chambers_layout.shaft, float(params["underground"].get("shaft_radius", 10.0))):
			if l.world.is_soil(c):
				l.world.soil[c] *= hard
	_entrance_planned = portal.open
	# Tunnels carved at the start are watched for traffic like dug ones.
	if highways != null:
		for g in chambers_layout.galleries:
			highways.watch(g.points, g.radii)
		for c in chambers_layout.list:
			if c.dug and c.tunnel.size() >= 2:
				var w := chambers_layout.tunnel_radius * NestChambers.CAPILLARY_WIDTH
				highways.watch(c.tunnel, NestChambers._taper(c.tunnel, w, w * 0.9))
	entrance_steps = PackedInt32Array(params.get("entrances", {}).get("at", []))
	entrance_spacing = float(params.get("entrances", {}).get("spacing", entrance_spacing))
	chambers = chambers_layout.dug_count()
	var b: Dictionary = params.get("brood", {}).duplicate()
	b["care"] = true
	if not b.has("first_caste"):
		b["first_caste"] = owner_colony.species.caste_index(first_caste)
	if not b.has("first_workers"):
		b["first_workers"] = 12
	brood = Brood.new()
	brood.setup(sim, self, owner_colony.species, b)

## Places the queen once (the first update after setup).
func _ensure_queen(sim: Simulation) -> void:
	if queen_ant < 0:
		queen_ant = spawn_initial(sim, sim.colonies[colony_id].species.caste_index(&"queen"))

## The colony's life underground, once a tick: brood, then once a second the
## roles, entrances and chamber planning; chambers finished digging go to
## _chambers_dug().
func _update_colony(sim: Simulation, dt: float) -> void:
	brood.update(sim, self, dt)
	_role_timer -= dt
	if _role_timer <= 0.0:
		_role_timer = 1.0
		_count_roles(sim)
		var workers := workers_alive(sim)
		if _entrance_planned:
			_plan_extra_entrances(sim)
		if not _entrance_planned and workers >= open_entrance_at:
			_plan_entrance()
		_plan_chambers(sim)
		# Now and then, reconnect digging whose way in will never open.
		_rescue_timer -= 1.0
		if _rescue_timer <= 0.0:
			_rescue_timer = 60.0
			chambers_layout.rescue(plan)
	if chambers_layout.update_dug(plan) > 0:
		chambers = chambers_layout.dug_count()
		_chambers_dug(sim)

## Called when chambers have finished digging (chambers_layout.list[k].dug).
func _chambers_dug(_sim: Simulation) -> void:
	pass

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

## Where the queen sits: her niche off the royal chamber.
func queen_spot() -> Vector2:
	var royal := chambers_layout.royal()
	return royal.alcoves[0] if not royal.alcoves.is_empty() else _spot(0, Vector2(-0.22, 0.05))

## The way the queen faces when resting: into her niche.
func queen_heading() -> float:
	var royal := chambers_layout.royal()
	if royal.alcoves.is_empty():
		return 0.0
	return (royal.alcoves[0] - royal.centre).angle()

## The chamber brood lives in: the first chamber dug, else the royal one.
func brood_chamber() -> int:
	for c in chambers_layout.list:
		if c.kind == NestChambers.Kind.CHAMBER and c.dug:
			return c.index
	return 0

## Centre of a brood pile (Brood.Pile): eggs at the mouth of the queen's
## niche, larvae in the brood chamber, pupae in an alcove (a drier niche)
## where the chamber has one.
func pile_centre(p: int) -> Vector2:
	var royal := chambers_layout.royal()
	match p:
		Brood.Pile.EGGS, Brood.Pile.QUEEN:
			if royal.alcoves.is_empty():
				return _spot(0, Vector2(0.3, 0.22))
			return royal.alcoves[0].lerp(royal.centre, 0.5)
		Brood.Pile.LARVAE:
			var k := brood_chamber()
			if k == 0 and royal.alcoves.size() >= 2:
				return royal.centre.lerp(royal.alcoves[1], 0.35)
			return _spot(k, Vector2(0.28, -0.35) if k == 0 else Vector2(-0.25, 0.0))
		_:
			var k := brood_chamber()
			var c := chambers_layout.list[k]
			if k == 0 and royal.alcoves.size() >= 2:
				return royal.alcoves[1]
			if not c.alcoves.is_empty():
				return c.alcoves[0]
			return _spot(k, Vector2(-0.1, -0.62) if k == 0 else Vector2(0.45, 0.3))

## A place in chamber k at `rel` from its centre, as a share of the way to
## its edge in that direction (NestChambers.point_in; works for any shape).
## Cached: chambers don't change shape.
func _spot(k: int, rel: Vector2) -> Vector2:
	var key := Vector3(k, rel.x, rel.y)
	if not _spots.has(key):
		_spots[key] = chambers_layout.point_in(k, rel.angle(), rel.length())
	return _spots[key]

## Position of slot `s` in pile p: a sunflower spiral out from the centre.
func pile_slot(p: int, s: int) -> Vector2:
	var spacing := 1.5 if p == Brood.Pile.EGGS else (3.6 if p == Brood.Pile.LARVAE else 4.4)
	var at := pile_centre(p) + Vector2.from_angle(s * 2.39996) * spacing * sqrt(s + 0.5)
	# A small alcove: slots that would be in the wall go to the nearest open spot.
	var w := chambers_layout.world
	return at if not w.is_blocked(at) else w.nearest_free(at, 6)

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
	# Its furthest cell from the centre (callers take 0.9 of it), so every
	# point in an elongated chamber is within reach.
	return (chambers_layout.list[k].reach_max + 8.0) if k >= 0 else 0.0

## Places a colony's starting ant: the queen at her spot in the royal
## chamber, workers in the royal chamber taking nest roles.
func spawn_initial(sim: Simulation, caste: int) -> int:
	if chambers_layout == null:
		return super.spawn_initial(sim, caste)
	var colony := sim.colonies[colony_id]
	if colony.species.castes[caste].id == &"queen":
		var q := sim.spawn_ant(colony, caste, queen_spot(), 0.0, underground_layer)
		queen_ant = q
		return q
	var at := chambers_layout.random_point(0, sim.rng, 2)
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
	for k in Brood.EVENT_LOG:
		if brood.emerge_ants[k] == i and sim.tick_count - brood.emerge_ticks[k] < 60 * sim.config.tick_rate:
			highlight_ant = i
			return

# --- Roles ------------------------------------------------------------------------------

## Roles workers can take, in the order ties are settled (the species adds
## its own; each must be a state the caste allows to be chosen for it).
func role_order() -> Array[String]:
	return ["nurse", "tend_queen", "dig"]

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
	# Larvae need feeding; eggs and pupae only moving and grooming.
	var larvae := brood.count_stage(Brood.Stage.LARVA)
	role_need["nurse"] = ceili(larvae / brood_per_nurse + (brood.count() - larvae) / (brood_per_nurse * 4.0)) if brood.count() > 0 else 0
	@warning_ignore("integer_division")
	role_need["tend_queen"] = clampi(workers / 25, 1, retinue_max) if workers >= 3 else 0
	var dig_work := 0
	var dig_slots := 0
	for job in plan.jobs:
		if plan.is_open(job):
			dig_work += job.remaining
			dig_slots += job.max_diggers
	# Digging gets more hands the more the nest is short of room.
	var dig_cap := maxi(2, int(workers * dig_fraction * clampf(space_pressure(), 0.3, 1.7)))
	# A digger per few cells of open work (galleries, capillaries and chambers
	# open one after another, so there is seldom much open at once).
	role_need["dig"] = mini(mini(ceili(dig_work / 6.0), dig_cap), dig_slots) if dig_work > 0 else 0
	_count_more_roles(sim, workers)

## The species' own roles' needs (role_need), after the shared ones.
func _count_more_roles(_sim: Simulation, _workers: int) -> void:
	pass

## The role (state id) a worker of `caste` should take now: the one most
## short of ants, or else _idle_role().
func pick_role(sim: Simulation, caste: int) -> String:
	var colony := sim.colonies[colony_id]
	var roles: Array[String] = []
	for r: String in role_order():
		if colony.allows(caste, sim.behaviour_index[r]):
			roles.append(r)
	# The role most short of hands relative to its need, brood care first.
	var best := ""
	var best_short := 0.0
	for r in roles:
		var need: int = role_need.get(r, 0)
		var short: float = float(need - role_count.get(r, 0)) / maxf(1.0, need) * float(role_weight.get(r, 1.0))
		if need > role_count.get(r, 0) and short > best_short:
			best_short = short
			best = r
	if best == "":
		best = _idle_role(sim, caste, roles)
	role_count[best] = role_count.get(best, 0) + 1
	return best

## A worker's role when no role is short of hands: up to the surface, or
## (sealed) the first role it can take.
func _idle_role(_sim: Simulation, _caste: int, roles: Array[String]) -> String:
	if has_entrance():
		return "go_up"
	return roles[0] if not roles.is_empty() else "go_up"

## True if some role other than `except` has fewer ants than it needs (as
## of the last count), so an idle worker should go and take one.
func short_elsewhere(except: String) -> bool:
	for r: String in role_need:
		if r != except and role_need[r] > role_count.get(r, 0):
			return true
	return false

# --- Digging ------------------------------------------------------------------------------

## Plans the entrance shaft: a tunnel from the royal chamber to the bottom of
## the shaft, then the shaft itself, which opens the portal when done.
func _plan_entrance() -> void:
	_entrance_planned = true
	var royal := chambers_layout.royal()
	var shaft := chambers_layout.shaft
	var dir := (shaft - royal.centre).normalized()
	var start := royal.centre + dir * chambers_layout.reach(0, dir.angle()) * 0.8
	var pts := chambers_layout.route_tunnel(start, shaft, plan)
	var radii := PackedFloat32Array()
	for p in pts:
		radii.append(chambers_layout.tunnel_radius)
	plan.add_path_job("entrance_tunnel", start, pts, radii, -2.0, 4)
	var job := plan.add_job("entrance", shaft - dir * 6.0, shaft, shaft, maxf(8.0, portal.radius * 0.8), -1.0, 4)
	plan.open_portal_when_done(job, portal)

## Plans a new chamber when the nest is running short of room
## (space_pressure(); one at a time, up to max_chambers).
func _plan_chambers(sim: Simulation) -> void:
	if not has_entrance() or chambers_layout.count() >= max_chambers:
		return
	# One chamber at a time, more at once (up to four) the more the nest is
	# overflowing.
	# Chambers still being dug; one waiting a long time for its way in to open
	# (e.g. its gallery was abandoned) doesn't hold up new ones.
	var undug := 0
	for c in chambers_layout.list:
		if not c.dug and not c.failed and c.job >= 0 and (plan.is_open(plan.job_by_id(c.job)) or plan.is_open(plan.job_by_id(c.tunnel_job))
				or sim.time() - c.planned_at < STUCK_CHAMBER):
			undug += 1
	var pressure := space_pressure()
	if pressure < 0.8 or undug >= clampi(int(pressure * 2.0), 1, 4):
		return
	if sim.time() < _plan_retry_at:
		return
	var ch := chambers_layout.plan_chamber(plan, float(chambers_layout.count()))
	if ch == null:
		# Nothing fits for now (planning is costly): try again in a while.
		_plan_retry_at = sim.time() + PLAN_RETRY
	if ch != null:
		ch.planned_at = sim.time()

## Once the colony has passed the next of `entrance_steps`, plans another
## entrance: a shaft up to the surface, facing food, spaced from the others,
## reached by a gallery routed from the nearest tunnel. Its portal opens when
## the shaft is dug (and the surface gets its own spoil heap and trail).
func _plan_extra_entrances(sim: Simulation) -> void:
	var done := extra_portals.size()
	if done >= entrance_steps.size() or sim.colonies[colony_id].total_population() < entrance_steps[done] \
			or sim.time() < _entrance_retry_at:
		return
	# Facing food: toward the richest source the colony can use, away from
	# the directions entrances already face.
	var colony := sim.colonies[colony_id]
	var main := entrance_position()
	var rng := chambers_layout.layout_rng()
	var best := Vector2.ZERO
	var best_score := -INF
	for src in sim.food_sources:
		if src.is_depleted() or not colony.food_types.has(src.type_id):
			continue
		var to := src.position - main
		var score := src.remaining_mass() / (1.0 + to.length() / 300.0)
		for e in entrances():
			if e != main:
				score *= 0.4 + 0.6 * clampf(1.0 - to.normalized().dot((e - main).normalized()), 0.0, 1.0)
		if score > best_score:
			best_score = score
			best = to.normalized()
	if best == Vector2.ZERO:
		best = Vector2.from_angle(rng.randf() * TAU)
	var l := sim.layers[underground_layer]
	var shaft_r := portal.radius
	for attempt in 32:
		# Facing food first, then anywhere.
		var spread := 0.7 if attempt < 12 else PI
		var dir := best.rotated(rng.randf_range(-spread, spread))
		var surface := main + dir * rng.randf_range(entrance_spacing, entrance_spacing * 2.2)
		var ok := Rect2(Vector2.ZERO, Vector2(sim.world.size)).grow(-40.0).has_point(surface) and not sim.world.is_blocked(surface)
		for e: Vector2 in [main] + Array(_all_entrances()):
			ok = ok and surface.distance_to(e) >= entrance_spacing
		ok = ok and surface.distance_to(spoil_position()) > 50.0 and surface.distance_to(dump_position()) > 50.0
		var under := portal.pos_b + (surface - main)
		ok = ok and Rect2(Vector2.ZERO, Vector2(l.world.size)).grow(-60.0).has_point(under)
		ok = ok and chambers_layout._soil_around(under, shaft_r + 8.0, plan)
		if not ok:
			continue
		var from := chambers_layout.nearest_tunnel_point(under, plan)
		if from == Vector2.INF:
			return
		var pts := chambers_layout.route_tunnel(from, under, plan)
		if Router.length_of(pts) > from.distance_to(under) * 1.8:
			continue
		var w := chambers_layout.tunnel_radius * NestChambers.MAIN_WIDTH
		plan.add_path_job("entrance%d_tunnel" % (done + 1), from, pts, NestChambers._taper(pts, w, w * 0.9), -1.5, 6)
		# The shaft, all the way up: harder digging (stones in it come out too).
		for c in l.world.cells_in_segment(under, under, shaft_r):
			l.world.soften(c, 2.5)
			if l.world.is_soil(c):
				l.world.soil[c] *= 2.0
		var dir_in := (under - pts[pts.size() - 2]).normalized() if pts.size() >= 2 else Vector2.RIGHT
		var job := plan.add_job("entrance%d" % (done + 1), under - dir_in * (shaft_r + 2.0), under, under,
				maxf(8.0, shaft_r * 0.8), -1.0, 4)
		var p := add_entrance(sim, surface, under, shaft_r)
		plan.open_portal_when_done(job, p)
		return
	# Nowhere fits now: try again in a while (the nest keeps changing).
	_entrance_retry_at = sim.time() + 120.0

## Surface ends of every extra entrance, open or not.
func _all_entrances() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in extra_portals:
		out.append(p.pos_a)
	return out

# --- Abstract population ------------------------------------------------------------------

## Ants back from the abstract population: underground, somewhere in a dug
## chamber taking a nest role; on the surface, at the entrance.
func spawn_from_pool(sim: Simulation, caste: int, l: int) -> int:
	if chambers_layout == null or l != underground_layer:
		return super.spawn_from_pool(sim, caste, l)
	var dug: Array[NestChambers.Chamber] = []
	for c in chambers_layout.list:
		if c.dug:
			dug.append(c)
	var ch := dug[sim.rng.randi() % dug.size()]
	var at := chambers_layout.random_point(ch.index, sim.rng, 2)
	var i := sim.spawn_ant(sim.colonies[colony_id], caste, at, sim.rng.randf_range(-PI, PI), l)
	if i >= 0:
		sim.change_state(i, first_state(sim, caste))
	return i

## The colony's size and brood, for the nest view's readout.
func stats_lines(sim: Simulation) -> PackedStringArray:
	var out := PackedStringArray()
	var n := sim.colonies[colony_id].total_population()
	out.append("%s %s" % [_thousands(n), "ant" if n == 1 else "ants"])
	if brood != null:
		var eggs := brood.count_stage(Brood.Stage.EGG)
		var larvae := brood.count_stage(Brood.Stage.LARVA)
		var pupae := brood.count_stage(Brood.Stage.PUPA) + brood.count_stage(Brood.Stage.CALLOW)
		out.append("%d %s  ·  %d %s  ·  %d %s" % [eggs, "egg" if eggs == 1 else "eggs", larvae,
				"larva" if larvae == 1 else "larvae", pupae, "pupa" if pupae == 1 else "pupae"])
	return out

static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
