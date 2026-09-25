class_name NestType
extends RefCounted
## Base interface for a colony's home. One instance per colony, created from
## the Registry by the species' nest_type id. Rendering is hooked up by
## registering a renderer under "nest:<type_id>".
##
## Nests without a fixed entrance (e.g. a moving bivouac) return
## has_entrance() == false and can move `position` in update(); nests that are
## built at runtime can start without an entrance and gain one later.

var type_id: String = ""
## Owning colony, as an index into sim.colonies (not a reference, to avoid a
## Colony <-> NestType reference cycle that would leak).
var colony_id: int = -1
var position: Vector2 = Vector2.ZERO
## Distance from the entrance at which an ant counts as "at the nest".
var radius: float = 12.0
## Distance from which returning ants see the entrance and head straight for it.
var sense_radius: float = 60.0

func setup(sim: Simulation, owner_colony: Colony, params: Dictionary) -> void:
	colony_id = owner_colony.id
	position = owner_colony.nest_position
	radius = params.get("radius", radius)
	sense_radius = params.get("sense_radius", sense_radius)
	var ent: Dictionary = params.get("entrance", {})
	entrance_style = str(ent.get("style", entrance_style))
	if not ENTRANCE_REACH.has(entrance_style):
		push_warning("Unknown entrance style \"%s\" (use %s)" % [entrance_style, ", ".join(ENTRANCE_REACH.keys())])
		entrance_style = "hole"
	clear_radius = float(ent.get("clear_radius", clear_radius))
	clears_plants = bool(ent.get("clears_plants", clears_plants))
	_setup_refuse(params)
	if params.has("underground"):
		setup_underground(sim, params["underground"])

## A nest with an underground has an entrance once one of its portals is open.
func has_entrance() -> bool:
	if portal == null or portal.open:
		return true
	for p in extra_portals:
		if p.open:
			return true
	return false

func entrance_position() -> Vector2:
	return position

func is_at_nest(pos: Vector2) -> bool:
	if extra_portals.is_empty():
		return has_entrance() and pos.distance_squared_to(entrance_position()) <= radius * radius
	for e in entrances():
		if pos.distance_squared_to(e) <= radius * radius:
			return true
	return false

## Surface ends of the open entrances: the main one (entrance_position())
## first, then any added with add_entrance().
func entrances() -> PackedVector2Array:
	if _entrances_changes != Portal.changes or _entrances_count != extra_portals.size():
		_entrances_changes = Portal.changes
		_entrances_count = extra_portals.size()
		_entrances = PackedVector2Array()
		if portal == null or portal.open:
			_entrances.append(entrance_position())
		for p in extra_portals:
			if p.open:
				_entrances.append(p.pos_a)
	if extra_portals.is_empty() and portal == null:
		_entrances = PackedVector2Array([entrance_position()])
	return _entrances

## The open entrance nearest `pos` (the first of equally near ones; the main
## entrance if there is only one).
func nearest_entrance(pos: Vector2) -> Vector2:
	if extra_portals.is_empty():
		return entrance_position()
	var best := entrance_position()
	var best_d := INF
	for e in entrances():
		var d := pos.distance_squared_to(e)
		if d < best_d:
			best_d = d
			best = e
	return best

## Extra entrances (portals besides `portal`, see add_entrance()).
var extra_portals: Array[Portal] = []
var _entrances: PackedVector2Array = []
var _entrances_changes: int = -1
var _entrances_count: int = -1

# --- How the entrances look on the surface ---------------------------------------------
# Render data (and room to keep clear of, for scenery and middens); none of
# it is simulation state. Nest param "entrance": {"style", "clear_radius",
# "clears_plants"}; nest types set their own defaults before setup().

## "hole" (a plain hole with a worn rim), "crater" (a ring of excavated grit
## round a funnel), "mound" (a low cone of loose soil, the hole on top) or
## "turret" (a small raised collar).
var entrance_style: String = "hole"
## Radius of the disc the colony keeps clear round its entrance at full size
## (0 = none), and whether plants and litter are cleared from it.
var clear_radius: float = 0.0
var clears_plants: bool = false

## How far each style's drawing reaches from the middle, in opening radii.
const ENTRANCE_REACH: Dictionary[String, float] = {"hole": 2.4, "crater": 3.6, "mound": 4.6, "turret": 2.4}
## Uses (ants through, both ways) at which an opening is about 63% of the
## way to its full size.
const USES_TO_WIDEN := 3000.0

## One opening on the surface (see entrance_sites()).
class EntranceSite:
	var position: Vector2
	## Radius of the opening (see entrance_radius()).
	var radius: float
	## False for a sealed entrance (a founding nest not dug open yet).
	var open: bool = true
	var main: bool = true
	## Ants through it so far (0 for a nest without portals).
	var uses: int = 0
	## Its spoil heap (spoil_position_of / spoil_count; 0 = the main one).
	var index: int = 0

	## How far its drawing reaches in `style` (for keep-clear rules).
	func reach(style: String) -> float:
		return radius * NestType.ENTRANCE_REACH.get(style, 2.4)

## The entrances as drawn on the surface: the main one first (also while
## sealed), then every open extra one.
func entrance_sites() -> Array[EntranceSite]:
	var out: Array[EntranceSite] = []
	var main := EntranceSite.new()
	main.position = entrance_position()
	main.open = portal == null or portal.open
	main.uses = portal.uses if portal != null else 0
	main.radius = entrance_radius(main.uses, true)
	out.append(main)
	for k in extra_portals.size():
		var p := extra_portals[k]
		if not p.open:
			continue
		var s := EntranceSite.new()
		s.position = p.pos_a
		s.main = false
		s.uses = p.uses
		s.radius = entrance_radius(p.uses, false)
		s.index = k + 1
		out.append(s)
	return out

## Radius of an opening after `uses` ants: the main one opens at 85% of the
## nest radius and widens to 120%; extra ones start at 55%, reach 100%.
func entrance_radius(uses: int, main: bool) -> float:
	var grown := 1.0 - exp(-uses / USES_TO_WIDEN)
	return radius * (0.85 + 0.35 * grown if main else 0.55 + 0.45 * grown)

## Radius of the cleared disc now: it widens as the colony grows (none while
## the nest is sealed or doesn't clear one).
func cleared_radius(sim: Simulation) -> float:
	if clear_radius <= 0.0 or not has_entrance():
		return 0.0
	var size := sqrt(sim.colonies[colony_id].total_population())
	return clear_radius * clampf(0.35 + size / 60.0, 0.35, 1.0)

## Takes ownership of a delivered item. The Simulation destroys the item afterwards.
func receive_item(_sim: Simulation, _item: Item) -> void:
	pass

## Growth and internal processes; called once per tick.
func update(_sim: Simulation, _dt: float) -> void:
	pass

## Adds any nest state that affects the simulation to a state_hash() fingerprint.
func hash_state(_ctx: HashingContext) -> void:
	pass

# --- Gradual release ---------------------------------------------------------------
# Ants can start "inside" the nest and emerge over time instead of all at once
# (scenario colony option "release_per_second"). The Simulation calls
# release_waiting() every tick, before update(), for every nest type.

## Caste indices of ants still inside, in emergence order.
var waiting: PackedInt32Array = []
## Ants released per second.
var release_rate: float = 0.0
var _release_budget: float = 0.0

## Queues ants to emerge at `per_second`.
func queue_release(castes: PackedInt32Array, per_second: float) -> void:
	waiting.append_array(castes)
	release_rate = per_second

func release_waiting(sim: Simulation, dt: float) -> void:
	if waiting.is_empty() or not has_entrance():
		return
	_release_budget += release_rate * dt
	var colony := sim.colonies[colony_id]
	while _release_budget >= 1.0 and not waiting.is_empty():
		_release_budget -= 1.0
		sim.spawn_ant(colony, waiting[0], entrance_position(), sim.rng.randf_range(-PI, PI))
		waiting.remove_at(0)

## Spawns `count` ants at the entrance, choosing castes by spawn_ratio.
func spawn_ants(sim: Simulation, count: int) -> void:
	for n in count:
		var caste := pick_caste(sim)
		var heading := sim.rng.randf_range(-PI, PI)
		sim.spawn_ant(sim.colonies[colony_id], caste, entrance_position(), heading)

## Weighted random caste index by CasteDef.spawn_ratio. Pass the species
## during setup(), before the colony is in sim.colonies.
func pick_caste(sim: Simulation, species: SpeciesDef = null) -> int:
	var castes := (species if species != null else sim.colonies[colony_id].species).castes
	var total := 0.0
	for c in castes:
		total += c.spawn_ratio
	var r := sim.rng.randf() * total
	for i in castes.size():
		r -= castes[i].spawn_ratio
		if r <= 0.0 and castes[i].spawn_ratio > 0.0:
			return i
	# Rounding left some over: the last caste that is ever spawned.
	for i in range(castes.size() - 1, -1, -1):
		if castes[i].spawn_ratio > 0.0:
			return i
	return 0

# --- Refuse ----------------------------------------------------------------------------
# Nests may produce refuse that workers carry out to a midden on the surface
# (the core carry_waste and carry_spent behaviours; dead nestmates with
# carry_corpse). The base nest makes none.
#
# Middens (Midden) are sited when the first load is ready, and again when
# the one in use is full, up to "sites" of them: the best of a ring of
# points "distance" from the entrance, scored away from trails (the
# colony's pheromones there and halfway out) and from the directions of
# food, clear of entrances, spoil heaps, props, walls and other nests, and
# next to the last midden. The scoring is deterministic and draws no random
# numbers. An explicit "dump" keeps one fixed site (position + dump).
#
#   "midden": {"style": "pile", "distance": [100, 200], "sites": 2,
#              "capacity": 30, "avoid_trails": true}, "dump": [120, 40]
#
# Styles: see Midden. A "ring" lies at the edge of the cleared disc
# (clear_radius) if the nest keeps one, else at the nearer distance.

## Mass of refuse carried out and dropped on middens so far.
var dumped_mass: float = 0.0
## Number of loads dropped on middens so far.
var dumped_items: int = 0
## The nest's middens in the order they were sited; the last is in use.
var middens: Array[Midden] = []
var midden_style: String = "pile"
## Nearest and furthest distance of a midden from the entrance.
var midden_distance: Vector2 = Vector2(100, 200)
var midden_sites: int = 2
var midden_capacity: float = 30.0
var midden_avoid_trails: bool = true
## Where refuse goes before a midden is sited, and with "dump" the one
## fixed site, relative to the nest's position.
var dump_offset: Vector2 = Vector2(120, 40)
var fixed_dump: bool = false
## Bumped when a midden is sited (renderers watch each midden's version).
var middens_version: int = 0
## Angles tried round the entrance, and the weights of the siting scores.
const MIDDEN_ANGLES := 32
const MIDDEN_TRAIL_WEIGHT := 2.0
const MIDDEN_FOOD_WEIGHT := 2.0
## How far round a candidate site trails are looked for.
const MIDDEN_TRAIL_REACH := 40.0

func _setup_refuse(params: Dictionary) -> void:
	var m: Dictionary = params.get("midden", {})
	midden_style = str(m.get("style", midden_style))
	if not Midden.STYLES.has(midden_style):
		push_warning("Unknown midden style \"%s\" (use %s)" % [midden_style, ", ".join(Midden.STYLES)])
		midden_style = "pile"
	if m.has("distance"):
		midden_distance = ScenarioEvents.vec2(m["distance"])
	midden_sites = maxi(1, int(m.get("sites", midden_sites)))
	midden_capacity = float(m.get("capacity", midden_capacity))
	midden_avoid_trails = bool(m.get("avoid_trails", midden_avoid_trails))
	if params.has("dump"):
		dump_offset = ScenarioEvents.vec2(params["dump"])
		fixed_dump = true

## True if there is waste ready to be carried out.
func has_waste() -> bool:
	return false

## Hands out one load of waste as a new Item (the caller picks it up), or
## null if there is none.
func take_waste(_sim: Simulation) -> Item:
	return null

## Where refuse goes: the midden in use (before one is sited, the default
## dump beside the nest).
func dump_position() -> Vector2:
	return middens[-1].position if not middens.is_empty() else position + dump_offset

## The midden new loads go to, siting one first if there is none yet or the
## one in use is full (and another may be sited).
func midden_for(sim: Simulation) -> Midden:
	if middens.is_empty() or (not fixed_dump and middens[-1].is_full() and middens.size() < midden_sites):
		var at := position + dump_offset if fixed_dump else site_midden(sim)
		if at == Vector2.INF:
			if not middens.is_empty():
				return middens[-1]
			at = position + dump_offset
		var m := Midden.new(at, entrance_position(), midden_style, midden_capacity)
		m.index = middens.size()
		middens.append(m)
		middens_version += 1
	return middens[-1]

## Where a worker should drop the load it is setting off with, from two
## uniform random numbers (drawn by the caller from sim.rng).
func refuse_target(sim: Simulation, u1: float, u2: float) -> Vector2:
	var m := midden_for(sim)
	var at := m.drop_point(u1, u2)
	return at if not sim.world.is_blocked(at) else m.position

## Called when a load of refuse is dropped at `at`: a deposit on the midden
## it lies on (the one in use may have filled up since the worker set off),
## judged by distance from each one's middle over its size. The caller
## destroys the item afterwards.
func drop_refuse(sim: Simulation, item: Item, at: Vector2) -> void:
	var best := midden_for(sim)
	var best_d := at.distance_to(best.centre()) / best.radius()
	for m in middens:
		var d := at.distance_to(m.centre()) / m.radius()
		if d < best_d - 1e-6:
			best_d = d
			best = m
	var caste := (item as Corpse).caste_id if item is Corpse else -1
	best.add(sim.registry.refuse_kind_for(item.type_id), at, item.mass, sim.time(), sim.registry, caste)
	receive_waste(sim, item)

## Keeps the totals of what was dropped (see drop_refuse()).
func receive_waste(_sim: Simulation, item: Item) -> void:
	dumped_mass += item.mass
	dumped_items += 1

## True if `at` is within `margin` of a midden (or of the default dump
## while there is none).
func near_midden(at: Vector2, margin: float) -> bool:
	if middens.is_empty():
		return at.distance_to(dump_position()) <= margin
	for m in middens:
		if at.distance_to(m.centre()) <= margin + m.radius():
			return true
	return false

## The best place for a new midden, or Vector2.INF if nowhere will do.
func site_midden(sim: Simulation) -> Vector2:
	var from := entrance_position()
	var world := sim.world
	var colony := sim.colonies[colony_id]
	var field := sim.layers[0].pheromones
	var bounds := Rect2(Vector2.ZERO, Vector2(world.size)).grow(-30.0)
	var foods: Array[Vector2] = []
	for src in sim.food_sources:
		if colony.food_types.has(src.type_id) and not src.is_depleted():
			foods.append(src.position)
	var dists: Array[float] = []
	if midden_style == "ring":
		dists.append(clear_radius + 6.0 if clear_radius > 0.0 else midden_distance.x)
	else:
		for k in 3:
			dists.append(lerpf(midden_distance.x, midden_distance.y, k * 0.5))
	var sites := entrance_sites()
	var best := Vector2.INF
	var best_score := -INF
	for a in MIDDEN_ANGLES:
		var dir := Vector2.from_angle(a * TAU / MIDDEN_ANGLES)
		for d in dists:
			var p := from + dir * d
			if not _midden_fits(sim, p, sites, bounds):
				continue
			var score := -0.5 * (d - dists[0]) / maxf(midden_distance.y - midden_distance.x, 1.0)
			if midden_avoid_trails:
				# On the site, halfway out, and round it (weighted less).
				var trail := 0.0
				for c: int in colony.channels.values():
					trail += field.sample(c, p) + field.sample(c, from.lerp(p, 0.5))
					for k in 8:
						trail += 0.5 * field.sample(c, p + Vector2.from_angle(k * TAU / 8.0) * MIDDEN_TRAIL_REACH)
				score -= MIDDEN_TRAIL_WEIGHT * trail / (1.0 + trail)
			for f in foods:
				# Best on the far side from food.
				var toward := (dir.dot((f - from).normalized()) + 1.0) * 0.5
				score -= MIDDEN_FOOD_WEIGHT * toward * toward / foods.size()
				if p.distance_to(f) < 100.0:
					score -= 2.0
			if world.prop_near(p, 28.0):
				score -= 0.5
			if not middens.is_empty():
				score += 1.0 - minf(1.0, p.distance_to(middens[-1].position) / 150.0)
			if score > best_score + 1e-6:
				best_score = score
				best = p
	return best

func _midden_fits(sim: Simulation, p: Vector2, sites: Array[EntranceSite], bounds: Rect2) -> bool:
	if not bounds.has_point(p) or sim.world.is_blocked(p) or sim.world.prop_near(p, 12.0):
		return false
	for s in sites:
		if p.distance_to(s.position) < s.reach(entrance_style) + 20.0:
			return false
	for e in spoil_by_entrance.size():
		if underground_layer >= 0 and p.distance_to(spoil_position_of(e)) < 45.0:
			return false
	for m in middens:
		if p.distance_to(m.centre()) < m.radius() * 2.0 + 10.0:
			return false
	for c in sim.colonies:
		if c.id != colony_id and p.distance_to(c.nest.position) < c.nest.radius * ENTRANCE_REACH.get(c.nest.entrance_style, 2.4) + 60.0:
			return false
	return true

## Rots what lies on the middens, and the colony's dead (see "Corpses");
## the Simulation calls it once a tick.
func update_refuse(sim: Simulation, dt: float) -> void:
	for m in middens:
		m.update(sim.time(), sim.registry)
	if corpses_on:
		update_corpses(sim, dt)

# --- Corpses ----------------------------------------------------------------------------
# Opt-in (colony params worker_lifespan > 0 or brood_corpses): workers die of
# old age and larvae that starve are left where they died as corpse items;
# nestmates nearby in an idle state (the species' pool_states) take them
# out to a midden (carry_corpse). Off, nothing here runs, draws random
# numbers or changes a hash.

## True if the colony leaves corpses (set by the Simulation from params).
var corpses_on: bool = false
## Seconds a worker lives (0 = for ever); each lives 0.7..1.3 times it.
var worker_lifespan: float = 0.0
## Corpses (item ids) lying where they fell, not yet taken.
var corpses: PackedInt32Array = []
## Workers and brood that died.
var worker_deaths: int = 0
var corpses_taken: int = 0
var _corpse_timer: float = 0.0
## How far an idle nestmate notices a corpse, and the most taken per second.
const CORPSE_SEE := 90.0
const CORPSES_PER_SECOND := 8

## A dead ant or larva as an item on the ground at `at` on layer `on_layer`
## (to be carried out).
func leave_corpse(sim: Simulation, type_id: String, mass: float, at: Vector2, on_layer: int, caste: int = -1) -> Item:
	var item := sim.create_item(type_id, mass)
	if item is Corpse:
		(item as Corpse).colony_id = colony_id
		(item as Corpse).caste_id = caste
	var def := sim.colonies[colony_id].species.castes[caste] if caste >= 0 else null
	item.radius = def.size * 0.3 if def != null else 1.6
	item.color = def.color.darkened(0.3) if def != null else Color(0.85, 0.82, 0.7)
	sim.place_on_ground(item, at, float(item.id % 628) * 0.01, on_layer)
	corpses.append(item.id)
	return item

## Once a second: workers past their lifespan die; idle nestmates near a
## corpse are sent to take it out.
func update_corpses(sim: Simulation, dt: float) -> void:
	_corpse_timer += dt
	if _corpse_timer < 1.0 - 1e-6:
		return
	_corpse_timer = 0.0
	if worker_lifespan > 0.0:
		_age_workers(sim)
	var sent := 0
	var k := 0
	while k < corpses.size() and sent < CORPSES_PER_SECOND:
		var item: Item = sim.items.get(corpses[k])
		if item == null or item.carrier >= 0:
			corpses.remove_at(k)
			continue
		k += 1
		if item.reserved_by >= 0 and sim.alive[item.reserved_by] != 0 and sim.state_id(item.reserved_by) == "carry_corpse":
			continue
		item.reserved_by = -1
		var ant := _corpse_taker(sim, item)
		if ant >= 0:
			item.reserved_by = ant
			var was := sim.state[ant]
			sim.change_state(ant, "carry_corpse")
			sim.scratch_i[ant] = item.id
			sim.scratch_f1[ant] = was
			sent += 1

func _age_workers(sim: Simulation) -> void:
	var colony := sim.colonies[colony_id]
	var now := sim.time()
	for i in sim.high_water:
		if sim.alive[i] == 0 or sim.colony_id[i] != colony_id or sim.transit_until[i] != 0:
			continue
		var caste := colony.species.castes[sim.caste_id[i]]
		if caste.carry_capacity <= 0.0:
			continue
		# Each ant's own span, from a hash of its slot and birth (no RNG).
		var h := float(hash(Vector2i(i, int(sim.born_at[i] * 30.0))) % 1000) / 1000.0
		if now - sim.born_at[i] < worker_lifespan * (0.7 + 0.6 * h):
			continue
		var at := sim.pos[i]
		var l := sim.layer[i]
		var c := sim.caste_id[i]
		sim.remove_ant(i)
		worker_deaths += 1
		leave_corpse(sim, "corpse", 0.05 * caste.size / 5.0, at, l, c)

## The nearest idle nestmate (in one of the pool_states, carrying nothing)
## on the corpse's layer within CORPSE_SEE, or -1.
func _corpse_taker(sim: Simulation, item: Item) -> int:
	var colony := sim.colonies[colony_id]
	var state: int = sim.behaviour_index.get("carry_corpse", -1)
	var best := -1
	var best_d := CORPSE_SEE * CORPSE_SEE
	for i in sim.high_water:
		if sim.alive[i] == 0 or sim.colony_id[i] != colony_id or sim.layer[i] != item.layer:
			continue
		if sim.carried[i] >= 0 or sim.riding[i] >= 0 or sim.transit_until[i] != 0:
			continue
		if colony.pool_state_mask[sim.state[i]] == 0 or not colony.allows(sim.caste_id[i], state):
			continue
		var d := sim.pos[i].distance_squared_to(item.position)
		if d < best_d:
			best_d = d
			best = i
	return best

## One tick of ant i walking to `goal` on layer `goal_layer`; true once
## within `reach`. Nests with an underground steer by their nav fields.
func walk_to(sim: Simulation, i: int, goal_layer: int, goal: Vector2, move_speed: float, dt: float, reach: float = 3.0) -> bool:
	return Travel.go(sim, i, goal_layer, goal, -1, move_speed, dt, reach)

# --- Underground ---------------------------------------------------------------------
# A nest may dig its own underground (nest_params "underground"): a layer of
# soil below the surface, linked to the entrance by a portal (the shaft).
# Its excavation plan says what to dig; diggers ("dig") bite soil at the
# digging face and carry the spoil up ("carry_spoil") to spoil_position() on
# the surface. Nest types extend the plan (e.g. new chambers as they grow)
# through excavation_plan().
#
#   "underground": {"size": [1280, 1280], "cell_size": 4, "hardness": 1.0,
#       "shaft": [640, 640], "shaft_radius": 10, "open": true, "bite": 0.5,
#       "spoil": [-70, 40],
#       "carve": [{"from": [x, y], "to": [x, y], "radius": r}, ...],
#       "plan": [{"name": "tunnel", "origin": [x, y], "from": [x, y], "to": [x, y],
#                 "radius": 7, "priority": 0, "diggers": 4},
#                {"name": "gallery", "path": [[x, y], ...], "radii": [9, 7, ...]},
#                {"name": "cave", "origin": [x, y], "lobes": [cx, cy, rx, ry, angle, ...],
#                 "face": [x, y]}, ...],
#       "texture": {"clay": 0.16, "roots": 0.05, "stones": 5, ...}, "overdig": 4.5,
#       "ragged": 6, "highways": {"threshold": 0.6, "max_radius": 14, "lanes": 0.8, ...}}
#
# "shaft" is where the entrance comes down (default: the layer's centre);
# "carve" shapes are dug out from the start (default: the shaft bottom, if
# open), "plan" jobs are dug by the colony: capsules (from/to/radius), paths
# (points with a radius each) or blobs of ellipses (see ExcavationPlan and
# DigShape). "texture" gives the soil clay, roots and stones (World.
# add_soil_texture, kept clear of the shaft and the carved shapes);
# "overdig" makes dug outlines rough and "ragged" the digging face uneven;
# "highways" widens busy tunnels and counts traffic (Highways, TrafficMap)
# and sets the layer's lanes.
# A sealed nest ("open": false) has no entrance until the job named
# "entrance" (if any) is finished.

## Layer index of the nest's underground, or -1 if it has none.
var underground_layer: int = -1
## The entrance shaft (surface <-> underground), or null.
var portal: Portal
var plan: ExcavationPlan
## Busy tunnels widened into highways (underground "highways"), or null.
var highways: Highways
## Where spoil is dropped on the surface, relative to the entrance.
var spoil_offset: Vector2 = Vector2(-70, 40)
## Soil carried out and dropped on the spoil heap so far.
var spoil_mass: float = 0.0
var spoil_items: int = 0
## Soil bitten out while the entrance was closed (pressed into the walls).
var packed_spoil: float = 0.0
## Weight of spoil per unit of digging work (see make_spoil()).
const SPOIL_WEIGHT := 0.3
## An ant a view should point out, e.g. a worker that has just come out of
## the nest onto the surface (-1 = none); see SplitLayout.
var highlight_ant: int = -1

func setup_underground(sim: Simulation, params: Dictionary) -> void:
	var size := Vector2i(ScenarioEvents.vec2(params.get("size", [1280, 1280])))
	var l := sim.add_layer(StringName("nest%d" % colony_id), size, int(params.get("cell_size", 4)))
	# Work per cell and cells per bite scale with the cell area, so a nest digs
	# the same volume whatever its cell size (4 is the reference).
	var area := pow(l.world.cell_size / 4.0, 2.0)
	l.world.fill_soil(float(params.get("hardness", 1.0)) * area)
	underground_layer = l.index
	var shaft := ScenarioEvents.vec2(params["shaft"]) if params.has("shaft") else Vector2(size) * 0.5
	var shaft_r := float(params.get("shaft_radius", 10.0))
	var open := bool(params.get("open", true))
	if params.has("spoil"):
		spoil_offset = ScenarioEvents.vec2(params["spoil"])
	if params.has("texture"):
		# Clay, roots and stones, kept clear of the shaft and anything carved.
		var clear := PackedVector3Array([Vector3(shaft.x, shaft.y, shaft_r + 12.0)])
		for c: Dictionary in params.get("carve", []):
			if c.has("lobes"):
				var lobes: Array = c["lobes"]
				for k in range(0, lobes.size() - 4, 5):
					clear.append(Vector3(lobes[k], lobes[k + 1], maxf(lobes[k + 2], lobes[k + 3]) + 8.0))
				continue
			var a := ScenarioEvents.vec2(c.get("from", c.get("center", [0, 0])))
			var b := ScenarioEvents.vec2(c.get("to", [a.x, a.y]))
			var r := float(c.get("radius", 10.0)) + 8.0
			for k in 5:
				var p := a.lerp(b, k / 4.0)
				clear.append(Vector3(p.x, p.y, r))
		for p: Variant in params.get("keep_clear", []):
			clear.append(Vector3(p[0], p[1], p[2]))
		l.world.add_soil_texture(sim.rng.seed * 31 + colony_id, params["texture"], clear)
	if params.has("carve"):
		for c: Dictionary in params["carve"]:
			if c.has("lobes"):
				l.world.carve_ellipses(PackedFloat32Array(c["lobes"]), float(c.get("rough", 0.0)), int(c.get("seed", 0)))
				continue
			var a := ScenarioEvents.vec2(c.get("from", c.get("center", [0, 0])))
			l.world.carve_segment(a, ScenarioEvents.vec2(c.get("to", [a.x, a.y])), float(c.get("radius", 10.0)))
	elif open:
		l.world.carve_segment(shaft, shaft, shaft_r)
	portal = sim.add_portal(0, entrance_position(), l.index, shaft, maxf(radius, shaft_r))
	portal.open = open
	plan = ExcavationPlan.new(l)
	plan.bite = float(params.get("bite", plan.bite)) * area
	plan.cells_per_bite = maxi(1, roundi(plan.cells_per_bite / area))
	plan.overdig = float(params.get("overdig", plan.overdig))
	plan.ragged = float(params.get("ragged", plan.ragged))
	plan.rough_seed = sim.rng.seed * 13 + colony_id
	# Jobs open once reachable from the nest's first open space (the first carved
	# shape, else the shaft bottom).
	var hub := shaft
	var carves: Array = params.get("carve", [])
	if not carves.is_empty():
		var c0: Dictionary = carves[0]
		hub = Vector2(c0["lobes"][0], c0["lobes"][1]) if c0.has("lobes") else ScenarioEvents.vec2(c0.get("from", c0.get("center", [shaft.x, shaft.y])))
	plan.reach_field = l.nav().set_target_point(&"hub", hub)
	for j: Dictionary in params.get("plan", []):
		var job: ExcavationPlan.Job
		var name := str(j.get("name", ""))
		var prio := float(j.get("priority", 0.0))
		var diggers := int(j.get("diggers", 4))
		if j.has("path"):
			var pts := PackedVector2Array()
			for p: Array in j["path"]:
				pts.append(Vector2(p[0], p[1]))
			var radii := PackedFloat32Array(j.get("radii", []))
			while radii.size() < pts.size():
				radii.append(float(j.get("radius", 7.0)))
			job = plan.add_path_job(name, ScenarioEvents.vec2(j.get("origin", j["path"][0])), pts, radii, prio, diggers)
		elif j.has("lobes"):
			var lobes := PackedFloat32Array(j["lobes"])
			var into := ScenarioEvents.vec2(j.get("origin", [lobes[0], lobes[1]]))
			job = plan.add_blob_job(name, into, lobes, ScenarioEvents.vec2(j.get("face", [into.x, into.y])), prio, diggers)
		else:
			var a := ScenarioEvents.vec2(j["from"])
			job = plan.add_job(name, ScenarioEvents.vec2(j.get("origin", j["from"])), a,
					ScenarioEvents.vec2(j.get("to", j["from"])), float(j.get("radius", 7.0)), prio, diggers)
		if job.name == "entrance":
			plan.open_portal_when_done(job, portal)
	if params.get("highways", false) is Dictionary:
		highways = Highways.new()
		highways.setup(sim, plan, params["highways"])

## What the nest wants dug (null without an underground).
func excavation_plan() -> ExcavationPlan:
	return plan

## Where diggers drop spoil on the surface.
func spoil_position() -> Vector2:
	return entrance_position() + spoil_offset

## Where spoil carried up through portal `portal_id` is dropped: the main
## heap for the main entrance, a heap beside each extra one.
func spoil_position_for(portal_id: int) -> Vector2:
	for k in extra_portals.size():
		if extra_portals[k].id == portal_id:
			return spoil_position_of(k + 1)
	return spoil_position()

## The spoil heap of entrance e (0 = the main one, k = extra_portals[k - 1]):
## an extra entrance's heap lies on its outer side, away from the main one.
func spoil_position_of(e: int) -> Vector2:
	if e <= 0 or e > extra_portals.size():
		return spoil_position()
	var at := extra_portals[e - 1].pos_a
	var out := (at - entrance_position()).normalized()
	return at + out.rotated(0.7) * spoil_offset.length() * 0.8

## A load of spoil dropped on a heap (that of the entrance it came up
## through: portal id, -1 = the main one). The Simulation destroys the item.
func receive_spoil(_sim: Simulation, item: Item, portal_id: int = -1) -> void:
	spoil_mass += item.mass
	spoil_items += 1
	var e := 0
	for k in extra_portals.size():
		if extra_portals[k].id == portal_id:
			e = k + 1
	while spoil_by_entrance.size() <= e:
		spoil_by_entrance.append(0)
	spoil_by_entrance[e] += 1

## Pellets dropped on each entrance's heap (0 = the main one).
var spoil_by_entrance: PackedInt32Array = [0]

## Adds a closed entrance: a portal from `surface` down to `under` on the
## nest's layer. Open it by finishing a job (ExcavationPlan
## .open_portal_when_done), e.g. a shaft dug up from a tunnel.
func add_entrance(sim: Simulation, surface: Vector2, under: Vector2, r: float) -> Portal:
	var p := sim.add_portal(0, surface, underground_layer, under, r)
	p.open = false
	extra_portals.append(p)
	return p

## Spoil pellets on entrance e's heap.
func spoil_count(e: int) -> int:
	if e == 0:
		return spoil_items - _extra_spoil()
	return spoil_by_entrance[e] if e < spoil_by_entrance.size() else 0

func _extra_spoil() -> int:
	var n := 0
	for k in range(1, spoil_by_entrance.size()):
		n += spoil_by_entrance[k]
	return n

## A new spoil pellet for `dug` work of soil (the digger picks it up). A
## pellet weighs SPOIL_WEIGHT per unit of work, so carrying it slows a
## digger down about like any other load.
func make_spoil(sim: Simulation, dug: float) -> Item:
	var item := sim.create_item("spoil", dug * SPOIL_WEIGHT)
	item.radius = 1.7
	item.color = Color(0.42, 0.3, 0.2)
	return item

## Underground state for Simulation.state_hash() (nest types that override
## hash_state() call this).
func hash_underground(ctx: HashingContext) -> void:
	if plan != null:
		plan.hash_into(ctx)
		if highways != null:
			highways.hash_into(ctx)
		ctx.update(PackedFloat64Array([spoil_mass, spoil_items, packed_spoil]).to_byte_array())

## Places one of the colony's starting ants (scenario population) and
## returns its index: at the entrance by default; nests with an underground
## may put them inside instead.
func spawn_initial(sim: Simulation, caste: int) -> int:
	return sim.spawn_ant(sim.colonies[colony_id], caste, entrance_position(), sim.rng.randf_range(-PI, PI))

## Called when ant i comes up onto the surface from the underground (the
## core "go_up" behaviour), e.g. to point out a new worker.
func ant_surfaced(_sim: Simulation, _i: int) -> void:
	pass

## The caste of abstract ant to bring back as an agent onto layer l: the
## one whose agents are furthest below its share of the whole colony (-1 if
## the colony has none abstract).
func pool_caste(sim: Simulation, _l: int) -> int:
	var colony := sim.colonies[colony_id]
	var best := -1
	var best_gap := -INF
	var total := maxf(1.0, colony.total_population())
	var agents := maxf(1.0, colony.population)
	for c in colony.abstract_by_caste.size():
		if colony.abstract_by_caste[c] <= 0:
			continue
		var gap := colony.total_of_caste(c) / total - colony.population_by_caste[c] / agents
		if gap > best_gap:
			best_gap = gap
			best = c
	return best

## Places an ant of caste c coming back from the abstract population onto
## layer l and returns it (-1 if it couldn't be placed): at the entrance by
## default.
func spawn_from_pool(sim: Simulation, caste: int, l: int) -> int:
	if l != 0:
		return -1
	return sim.spawn_ant(sim.colonies[colony_id], caste, entrance_position() + Vector2.from_angle(sim.rng.randf() * TAU) * 4.0,
			sim.rng.randf_range(-PI, PI))

## Lines of text about the colony a nest view may show (e.g. its size),
## the first one larger. None by default.
func stats_lines(_sim: Simulation) -> PackedStringArray:
	return PackedStringArray()

## Underground upkeep, once a tick after update() (the Simulation calls it):
## highways.
func update_underground(sim: Simulation, dt: float) -> void:
	if highways != null:
		highways.update(sim, dt)
