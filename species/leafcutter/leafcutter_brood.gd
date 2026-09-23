class_name LeafcutterBrood
extends RefCounted
## Opt-in brood model for FungusNest (nest_params "brood"): instead of new
## workers appearing at once, the queen lays eggs that develop
##
##   egg -> larva -> pupa -> callow -> worker (spawned at the entrance)
##
## Stage durations are simulated seconds, tuned for video (real development
## takes weeks). The queen lays at most one egg every lay_interval seconds,
## paced by the nest's brood budget (brood_rate * fungus), while fungus is
## above brood_reserve and population + brood stays under max_population
## (and brood under max_brood). Eggs cost nothing; each larva eats ant_cost
## fungus spread over its stage, and only grows while it's fed: with fungus
## at or below the reserve larvae stop growing and the queen stops laying.
## A callow ends as a real ant of the caste chosen when the egg was laid.
##
## Records are parallel packed arrays, one entry per brood item in laying
## order. Chamber and slot say where it lies (the cutaway view places it
## from those); chambers are chosen by stage: eggs stay in the royal chamber
## (0), larvae go to the garden chamber 1 and pupae to 2, each spilling over
## into 3 and 4 when it holds PER_CHAMBER, falling back to the chambers that
## exist.
##
## Laying and emergence are logged with their tick (ring buffers of the last
## EVENT_LOG events, indexed by the running totals), so a view can play each
## event at the right moment.
##
## params: lay_interval, egg, larva, pupa, callow, max_brood,
##         initial: {"egg": n, "larva": n, "pupa": n}

enum Stage { EGG, LARVA, PUPA, CALLOW }
const STAGE_KEYS: PackedStringArray = ["egg", "larva", "pupa", "callow"]
const EVENT_LOG := 32
## Larvae or pupae a brood chamber holds before the next one is used.
const PER_CHAMBER := 18

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

## True while fungus is at or below the reserve (no laying, no larval growth).
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

func setup(sim: Simulation, nest: FungusNest, species: SpeciesDef, params: Dictionary) -> void:
	lay_interval = float(params.get("lay_interval", lay_interval))
	for s in STAGE_KEYS.size():
		stage_time[s] = float(params.get(STAGE_KEYS[s], stage_time[s]))
	max_brood = int(params.get("max_brood", max_brood))
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
			var i := _add(s, nest.pick_caste(sim, species), nest)
			age[i] = stage_time[s] * (k + 0.5) / n
			if s == Stage.LARVA:
				growth[i] = age[i] / stage_time[s]

func count() -> int:
	return stage.size()

func count_stage(s: int) -> int:
	return stage.count(s)

func update(sim: Simulation, nest: FungusNest, dt: float) -> void:
	var colony := sim.colonies[nest.colony_id]
	starving = nest.fungus <= nest.brood_reserve
	var larva_bite := nest.ant_cost * dt / stage_time[Stage.LARVA]
	var i := 0
	while i < stage.size():
		var s := stage[i]
		if s == Stage.LARVA:
			if nest.fungus <= nest.brood_reserve:
				i += 1
				continue
			nest.fungus -= larva_bite
			growth[i] = minf(1.0, growth[i] + dt / stage_time[Stage.LARVA])
		age[i] += dt
		if age[i] < stage_time[s] - 1e-4:
			i += 1
		elif s == Stage.CALLOW:
			_emerge(sim, nest, i)
		else:
			_advance(i, nest)
			i += 1
	# The queen lays, paced by the garden.
	_since_lay += dt
	_budget = minf(_budget + nest.brood_rate * nest.fungus * dt, 1.0)
	if (_budget >= 1.0 and _since_lay >= lay_interval - 1e-6 and not starving and count() < max_brood
			and colony.population + count() < nest.max_population):
		_budget -= 1.0
		_since_lay = 0.0
		var n := _add(Stage.EGG, nest.pick_caste(sim), nest)
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
	ctx.update(id.to_byte_array())
	ctx.update(stage)
	ctx.update(age.to_byte_array())
	ctx.update(chamber)
	ctx.update(slot.to_byte_array())
	ctx.update(growth.to_byte_array())
	ctx.update(caste)

func _add(s: int, caste_index: int, nest: FungusNest) -> int:
	id.append(_next_id)
	_next_id += 1
	stage.append(s)
	age.append(0.0)
	growth.append(1.0 if s >= Stage.PUPA else 0.0)
	caste.append(caste_index)
	chamber.append(0)
	slot.append(0)
	var i := stage.size() - 1
	_place(i, nest)
	return i

## Next stage; eggs and larvae move to the chamber for their new stage.
func _advance(i: int, nest: FungusNest) -> void:
	var s := stage[i] + 1
	stage[i] = s
	age[i] = 0.0
	if s == Stage.PUPA:
		growth[i] = 1.0
	# Callows stay where they pupated until they walk out.
	if s != Stage.CALLOW:
		_place(i, nest)

func _emerge(sim: Simulation, nest: FungusNest, i: int) -> void:
	var colony := sim.colonies[nest.colony_id]
	var ant := sim.spawn_ant(colony, caste[i], nest.entrance_position(), sim.rng.randf_range(-PI, PI))
	nest.ants_raised += 1
	var e := emerged % EVENT_LOG
	emerge_ticks[e] = sim.tick_count
	emerge_ids[e] = id[i]
	emerge_ants[e] = ant
	emerged += 1
	id.remove_at(i)
	stage.remove_at(i)
	age.remove_at(i)
	chamber.remove_at(i)
	slot.remove_at(i)
	growth.remove_at(i)
	caste.remove_at(i)

## Chooses the chamber and the lowest free slot there for record i's stage.
func _place(i: int, nest: FungusNest) -> void:
	var group := _group(stage[i])
	var best := 0
	if group > 0:
		var wanted: PackedInt32Array = [1, 3] if group == 1 else [2, 4]
		var options: PackedInt32Array = []
		for k in wanted:
			if k < nest.chambers:
				options.append(k)
		if options.is_empty():
			options.append(mini(group, nest.chambers) - 1 if nest.chambers > 1 else 0)
		# The first chamber with room, or else the least crowded.
		var fewest := 1 << 30
		for k in options:
			var n := _in_chamber(k, group, i)
			if n < PER_CHAMBER:
				best = k
				break
			if n < fewest:
				fewest = n
				best = k
	chamber[i] = best
	var used := {}
	for j in stage.size():
		if j != i and chamber[j] == best and _group(stage[j]) == group:
			used[slot[j]] = true
	var free := 0
	while used.has(free):
		free += 1
	slot[i] = free

## Slot groups: eggs, larvae, and pupae with callows (who keep their pupa's slot).
static func _group(s: int) -> int:
	return mini(s, Stage.PUPA)

func _in_chamber(k: int, group: int, skip: int) -> int:
	var n := 0
	for j in stage.size():
		if j != skip and chamber[j] == k and _group(stage[j]) == group:
			n += 1
	return n
