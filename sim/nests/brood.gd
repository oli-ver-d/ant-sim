class_name Brood
extends RefCounted
## Opt-in brood model for a ColonyNest (nest_params "brood"): instead of new
## workers appearing at once, the queen lays eggs that develop
##
##   egg -> larva -> pupa -> callow -> worker (spawned at the entrance)
##
## Stage durations are simulated seconds, tuned for video (real development
## takes weeks). The queen lays at most one egg every lay_interval seconds,
## paced by the nest's brood budget (brood_rate * its food stock), while food is
## above brood_reserve and population + brood stays under max_population
## (and brood under max_brood). Eggs cost nothing; each larva eats ant_cost
## food spread over its stage, and only grows while it's fed: with food
## at or below the reserve larvae stop growing and the queen stops laying.
## A callow ends as a real ant of the caste chosen when the egg was laid.
##
## Records are parallel packed arrays, one entry per brood item in laying
## order. With care on, chamber and slot say where it lies (see the care
## notes below); without care brood has no place in the nest.
##
## Laying and emergence are logged with their tick (ring buffers of the last
## EVENT_LOG events, indexed by the running totals), so views can react to
## each event (e.g. ring a new worker on the surface).
##
## params: lay_interval, egg, larva, pupa, callow, max_brood,
##         initial: {"egg": n, "larva": n, "pupa": n}

enum Stage { EGG, LARVA, PUPA, CALLOW }
const STAGE_KEYS: PackedStringArray = ["egg", "larva", "pupa", "callow"]
const EVENT_LOG := 32

var lay_interval: float = 4.0
## Seconds per stage, indexed by Stage.
var stage_time: PackedFloat32Array = [40.0, 90.0, 60.0, 8.0]
var max_brood: int = 80

# Records.
var id: PackedInt32Array = []
var stage: PackedByteArray = []
## Seconds spent in the current stage (larvae only age while fed).
var age: PackedFloat32Array = []
var chamber: PackedByteArray = []
var slot: PackedInt32Array = []
## Share of ant_cost eaten as a larva, 0-1 (1 from pupa on).
var growth: PackedFloat32Array = []
var caste: PackedByteArray = []

## True while food is at or below the reserve (no laying, no larval growth).
var starving: bool = false

# Event log: event n is at index n % EVENT_LOG.
var eggs_laid: int = 0
var lay_ticks: PackedInt64Array = []
var lay_ids: PackedInt32Array = []
var emerged: int = 0
var emerge_ticks: PackedInt64Array = []
var emerge_ids: PackedInt32Array = []
## Ant index spawned by each emergence.
var emerge_ants: PackedInt32Array = []

var _next_id: int = 0
var _since_lay: float = 0.0
var _budget: float = 0.0

func setup(sim: Simulation, nest: ColonyNest, species: SpeciesDef, params: Dictionary) -> void:
	lay_interval = float(params.get("lay_interval", lay_interval))
	for s in STAGE_KEYS.size():
		stage_time[s] = float(params.get(STAGE_KEYS[s], stage_time[s]))
	max_brood = int(params.get("max_brood", max_brood))
	care = bool(params.get("care", false))
	if care:
		_setup_care(params)
	lay_ticks.resize(EVENT_LOG)
	lay_ids.resize(EVENT_LOG)
	emerge_ticks.resize(EVENT_LOG)
	emerge_ids.resize(EVENT_LOG)
	emerge_ants.resize(EVENT_LOG)
	# Initial brood, spread evenly through each stage so every stage is
	# visible from the first frame and development is staggered.
	var initial: Dictionary = params.get("initial", {})
	for s: int in [Stage.EGG, Stage.LARVA, Stage.PUPA]:
		var n := int(initial.get(STAGE_KEYS[s], 0))
		for k in n:
			if count() >= max_brood:
				break
			var i := _add(s, _brood_caste(sim, nest, species), nest)
			age[i] = stage_time[s] * (k + 0.5) / n
			if s == Stage.LARVA:
				growth[i] = age[i] / stage_time[s]
			if care:
				_drop_in_pile(i, home_pile(s), nest)

func count() -> int:
	return stage.size()

func count_stage(s: int) -> int:
	return stage.count(s)

func update(sim: Simulation, nest: ColonyNest, dt: float) -> void:
	if care:
		_update_care(sim, nest, dt)
		return
	var colony := sim.colonies[nest.colony_id]
	starving = nest.food_stock() <= nest.brood_reserve
	var larva_bite := nest.ant_cost * dt / stage_time[Stage.LARVA]
	var i := 0
	while i < stage.size():
		var s := stage[i]
		if s == Stage.LARVA:
			if nest.food_stock() <= nest.brood_reserve:
				i += 1
				continue
			nest.eat_stock(larva_bite)
			growth[i] = minf(1.0, growth[i] + dt / stage_time[Stage.LARVA])
		age[i] += dt
		if age[i] < stage_time[s] - 1e-4:
			i += 1
		elif s == Stage.CALLOW:
			_emerge(sim, nest, i)
		else:
			_advance(i)
			i += 1
	# The queen lays, paced by the food stock.
	_since_lay += dt
	_budget = minf(_budget + nest.brood_rate * nest.food_stock() * dt, 1.0)
	if (_budget >= 1.0 and _since_lay >= lay_interval - 1e-6 and not starving and count() < max_brood
			and colony.population + count() < nest.max_population):
		_budget -= 1.0
		_since_lay = 0.0
		var n := _add(Stage.EGG, _brood_caste(sim, nest, null), nest)
		var e := eggs_laid % EVENT_LOG
		lay_ticks[e] = sim.tick_count
		lay_ids[e] = id[n]
		eggs_laid += 1

## Tick of lay event n (n < eggs_laid, and within the last EVENT_LOG).
func lay_tick(n: int) -> int:
	return lay_ticks[n % EVENT_LOG]

func emerge_tick(n: int) -> int:
	return emerge_ticks[n % EVENT_LOG]

## Record index of brood item `brood_id`, or -1.
func index_of(brood_id: int) -> int:
	return id.find(brood_id)

## Fingerprint of the brood, for Simulation.state_hash().
func hash_into(ctx: HashingContext) -> void:
	ctx.update(PackedInt64Array([_next_id, eggs_laid, emerged]).to_byte_array())
	ctx.update(PackedFloat64Array([_since_lay, _budget]).to_byte_array())
	# (Hashing an empty array is an engine error; with no brood there is nothing to add.)
	if count() > 0:
		ctx.update(id.to_byte_array())
		ctx.update(stage)
		ctx.update(age.to_byte_array())
		ctx.update(chamber)
		ctx.update(slot.to_byte_array())
		ctx.update(growth.to_byte_array())
		ctx.update(caste)
	if care:
		_hash_care(ctx)

func _add(s: int, caste_index: int, nest: ColonyNest) -> int:
	id.append(_next_id)
	_next_id += 1
	stage.append(s)
	age.append(0.0)
	growth.append(1.0 if s >= Stage.PUPA else 0.0)
	caste.append(caste_index)
	chamber.append(0)
	slot.append(0)
	if care:
		_add_care(nest)
	return stage.size() - 1

## Next stage (without care).
func _advance(i: int) -> void:
	var s := stage[i] + 1
	stage[i] = s
	age[i] = 0.0
	if s == Stage.PUPA:
		growth[i] = 1.0

func _emerge(sim: Simulation, nest: ColonyNest, i: int) -> void:
	var colony := sim.colonies[nest.colony_id]
	var ant := sim.spawn_ant(colony, caste[i], nest.entrance_position(), sim.rng.randf_range(-PI, PI))
	nest.ants_raised += 1
	var e := emerged % EVENT_LOG
	emerge_ticks[e] = sim.tick_count
	emerge_ids[e] = id[i]
	emerge_ants[e] = ant
	emerged += 1
	_remove(i)

## Removes record i.
func _remove(i: int) -> void:
	id.remove_at(i)
	stage.remove_at(i)
	age.remove_at(i)
	chamber.remove_at(i)
	slot.remove_at(i)
	growth.remove_at(i)
	caste.remove_at(i)
	if care:
		_remove_care(i)

## Caste of new brood: nest.pick_caste(), or with care on, `first_caste`
## until the nest has raised `first_workers` (a founding colony's first
## workers are all small).
func _brood_caste(sim: Simulation, nest: ColonyNest, species: SpeciesDef) -> int:
	if care and first_caste >= 0 and nest.ants_raised + count() < first_workers:
		return first_caste
	return nest.pick_caste(sim, species)

# --- Care (nests with an underground) ------------------------------------------------
# With "care": true (ColonyNest turns it on for nests that dig their own
# underground) brood are things lying in the nest that workers look after:
#
#   - each record has a position on the nest's layer and a pile it lies in:
#     just laid by the queen (QUEEN), or the egg, larva or pupa pile
#     (ColonyNest.pile_centre()), carried by an ant (CARRIED), or put down
#     somewhere else (LOOSE). Brood away from its stage's pile is moved there
#     by nurses (eggs from the queen to the egg pile, larvae to theirs,
#     pupae to a drier spot);
#   - dirt rises by dirt_rate per second and grooming clears it; brood at
#     dirt 1 (neglected) stops developing;
#   - larvae get hungry (hunger_rate per second) and only grow while hunger
#     is below 1; a nurse feeding one brings food from the nest's stores
#     (feed_mass() each, so a larva eats ant_cost over its stage).
#     A larva hungry for starve_time seconds dies (deaths);
#   - a callow at the end of its stage waits for a nurse to free it from the
#     casing (free_callow()), then becomes a real ant where it lies.
# With nobody to care for them brood stalls: eggs and pupae get dirty,
# larvae starve. Tasks are claimed by one ant at a time (claimed).
#
# params: care, dirt_rate, hunger_rate, starve_time, first_caste, first_workers,
#         brood_per_worker (the queen lays up to this per worker)

enum Pile { QUEEN, EGGS, LARVAE, PUPAE, CARRIED, LOOSE }
## Distance within which brood counts as lying in its pile (grows with the slot).
const PILE_REACH := 14.0

var care: bool = false
var dirt_rate: float = 1.0 / 90.0
var hunger_rate: float = 1.0 / 40.0
var starve_time: float = 120.0
## Brood the queen keeps up to per worker (see care_limit()).
var brood_per_worker: float = 2.5
## Caste index of the first workers (-1 = any), until first_workers are raised.
var first_caste: int = -1
var first_workers: int = 0
## Larvae that starved.
var deaths: int = 0

var pos: PackedVector2Array = []
var pile: PackedByteArray = []
## Ant carrying it, or -1.
var carrier: PackedInt32Array = []
## Ant that has taken a task on it, or -1.
var claimed: PackedInt32Array = []
var dirt: PackedFloat32Array = []
var hunger: PackedFloat32Array = []
## Seconds a larva has been at hunger 1.
var hungry_for: PackedFloat32Array = []

func _setup_care(params: Dictionary) -> void:
	dirt_rate = float(params.get("dirt_rate", dirt_rate))
	hunger_rate = float(params.get("hunger_rate", hunger_rate))
	starve_time = float(params.get("starve_time", starve_time))
	brood_per_worker = float(params.get("brood_per_worker", brood_per_worker))
	first_caste = int(params.get("first_caste", first_caste))
	first_workers = int(params.get("first_workers", first_workers))

## Food one feeding brings a larva.
func feed_mass(nest: ColonyNest) -> float:
	return nest.ant_cost / maxf(1.0, stage_time[Stage.LARVA] * hunger_rate)

## The pile a record at stage s belongs in.
static func home_pile(s: int) -> int:
	return Pile.EGGS if s == Stage.EGG else (Pile.LARVAE if s == Stage.LARVA else Pile.PUPAE)

## True if record k lies in its stage's pile (so nobody needs to move it).
func is_home(k: int, nest: ColonyNest) -> bool:
	var want := home_pile(stage[k])
	if pile[k] != want:
		return false
	var reach := PILE_REACH * (1.0 + sqrt(float(slot[k])))
	return pos[k].distance_squared_to(nest.pile_centre(want)) <= reach * reach

## True if callow k has finished its stage and waits to be freed.
func callow_ready(k: int) -> bool:
	return stage[k] == Stage.CALLOW and age[k] >= stage_time[Stage.CALLOW] - 1e-4

func _add_care(nest: ColonyNest) -> void:
	pos.append(nest.pile_centre(Pile.EGGS))
	pile.append(Pile.LOOSE)
	carrier.append(-1)
	claimed.append(-1)
	dirt.append(0.0)
	hunger.append(0.3)
	hungry_for.append(0.0)

func _remove_care(i: int) -> void:
	pos.remove_at(i)
	pile.remove_at(i)
	carrier.remove_at(i)
	claimed.remove_at(i)
	dirt.remove_at(i)
	hunger.remove_at(i)
	hungry_for.remove_at(i)

## Puts record k down in pile p, in that pile's lowest free slot.
func _drop_in_pile(k: int, p: int, nest: ColonyNest) -> void:
	var used := {}
	for j in stage.size():
		if j != k and pile[j] == p:
			used[slot[j]] = true
	var free := 0
	while used.has(free):
		free += 1
	pile[k] = p
	slot[k] = free
	carrier[k] = -1
	pos[k] = nest.pile_slot(p, free)
	chamber[k] = maxi(0, nest.chambers_layout.chamber_at(pos[k]))

## Ant `ant` picks record k up.
func pick_up(k: int, ant: int) -> void:
	carrier[k] = ant
	pile[k] = Pile.CARRIED

## The carrier puts record k down at `at`: into its stage's pile if that's
## where it is, otherwise loose on the floor.
func put_down(k: int, at: Vector2, nest: ColonyNest) -> void:
	var want := home_pile(stage[k])
	if at.distance_to(nest.pile_centre(want)) <= PILE_REACH * 3.0:
		_drop_in_pile(k, want, nest)
		return
	carrier[k] = -1
	pile[k] = Pile.LOOSE
	pos[k] = at
	slot[k] = 0

## A nurse feeds larva k `share` of a full feed (feed_mass(); the food
## was taken from the stores already).
func feed(k: int, share: float = 1.0) -> void:
	hunger[k] = maxf(0.0, hunger[k] - share)
	hungry_for[k] = 0.0

func groom(k: int) -> void:
	dirt[k] = 0.0

func _update_care(sim: Simulation, nest: ColonyNest, dt: float) -> void:
	var colony := sim.colonies[nest.colony_id]
	starving = nest.food_stock() <= nest.reserve()
	var k := 0
	while k < stage.size():
		var s := stage[k]
		# Carried brood rides in its carrier's jaws.
		if carrier[k] >= 0:
			var a := carrier[k]
			if sim.alive[a] == 0:
				carrier[k] = -1
				pile[k] = Pile.LOOSE
			else:
				pos[k] = sim.pos[a] + Vector2.from_angle(sim.heading[a]) * sim.caste_of(a).size * 0.5
		dirt[k] = minf(1.0, dirt[k] + dirt_rate * dt)
		var grows := dirt[k] < 1.0
		if s == Stage.LARVA:
			hunger[k] = minf(1.0, hunger[k] + hunger_rate * dt)
			if hunger[k] >= 1.0:
				grows = false
				hungry_for[k] += dt
				if hungry_for[k] >= starve_time:
					deaths += 1
					_remove(k)
					continue
		if s == Stage.CALLOW and age[k] >= stage_time[s] - 1e-4:
			grows = false
		if grows:
			age[k] += dt
			if s == Stage.LARVA:
				growth[k] = minf(1.0, age[k] / stage_time[s])
			if age[k] >= stage_time[s] - 1e-4 and s != Stage.CALLOW:
				stage[k] = s + 1
				age[k] = 0.0
				if s + 1 == Stage.PUPA:
					growth[k] = 1.0
				hunger[k] = 0.3
		k += 1
	# The queen lays, paced by the food stock, at the tip of her abdomen.
	_since_lay += dt
	_budget = minf(_budget + nest.brood_rate * nest.food_stock() * dt, 1.0)
	var queen := nest.queen_ant
	if (queen >= 0 and sim.alive[queen] != 0 and _budget >= 1.0
			and _since_lay >= nest.lay_interval_now(sim, lay_interval) - 1e-6
			and not starving and count() < mini(max_brood, care_limit(sim, nest))
			and colony.total_population() + count() < nest.max_population):
		_budget -= 1.0
		_since_lay = 0.0
		var n := _add(Stage.EGG, _brood_caste(sim, nest, null), nest)
		pile[n] = Pile.QUEEN
		var tip := sim.pos[queen] - Vector2.from_angle(sim.heading[queen]) * sim.caste_of(queen).size * 0.62
		pos[n] = tip + Vector2(sim.rng.randf_range(-1.5, 1.5), sim.rng.randf_range(-1.5, 1.5))
		var w := sim.layers[nest.underground_layer].world
		if w.is_blocked(pos[n]):
			pos[n] = w.nearest_free(pos[n], 4)
		chamber[n] = 0
		var e := eggs_laid % EVENT_LOG
		lay_ticks[e] = sim.tick_count
		lay_ids[e] = id[n]
		eggs_laid += 1

## A nurse frees callow k from its casing: it becomes a real ant of its
## caste where it lies, in `state_id` (e.g. taking a nest role). Logged as
## an emergence, as without care. Returns the ant (-1 if the sim is full).
func free_callow(sim: Simulation, nest: ColonyNest, k: int, state_id: String) -> int:
	var colony := sim.colonies[nest.colony_id]
	var ant := -1
	# Into a full nest the new worker joins the abstract population.
	if sim.layer_full(nest.underground_layer):
		sim.add_abstract(colony, caste[k])
	else:
		ant = sim.spawn_ant(colony, caste[k], pos[k], sim.rng.randf_range(-PI, PI), nest.underground_layer)
	if ant >= 0 and state_id != "" and sim.state_id(ant) != state_id:
		sim.change_state(ant, state_id)
	nest.ants_raised += 1
	var e := emerged % EVENT_LOG
	emerge_ticks[e] = sim.tick_count
	emerge_ids[e] = id[k]
	emerge_ants[e] = ant
	emerged += 1
	_remove(k)
	return ant

func _hash_care(ctx: HashingContext) -> void:
	ctx.update(PackedInt64Array([deaths]).to_byte_array())
	if count() > 0:
		ctx.update(pos.to_byte_array())
		ctx.update(pile)
		ctx.update(carrier.to_byte_array())
		ctx.update(claimed.to_byte_array())
		ctx.update(dirt.to_byte_array())
		ctx.update(hunger.to_byte_array())

## Brood the colony can look after: brood_per_worker per worker (at least
## 10, so a founding queen can start). The queen lays no more than this, so
## brood isn't laid only to starve.
func care_limit(sim: Simulation, nest: ColonyNest) -> int:
	return maxi(10, int(nest.workers_alive(sim) * brood_per_worker))
