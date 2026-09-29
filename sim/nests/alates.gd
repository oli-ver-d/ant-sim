class_name Alates
extends RefCounted
## Winged reproductives and their nuptial flight (ColonyNest, opt-in
## nest_params "alates": {...}; needs an underground). Once the colony has
## `from_population` ants, the queen's next `count` eggs become alates: ants
## of the species' alate castes (CasteDef.alate, e.g. "gyne" and "male"),
## shared out by `castes` weights in a fixed order (no random numbers). They
## take no part in the colony's work; each alate ("alate" state)
##   1. waits in the nest (WAIT), wandering slowly round a chamber near the
##      main shaft, until a nuptial flight is called (scenario event
##      "nuptial_flight", start_flight());
##   2. walks up and out (UP), one setting off every `stagger` seconds;
##   3. gathers on the mound round the entrance (GATHER), milling and now and
##      then spreading its wings, while up to `escort` workers from the
##      surface (the biggest first, "escort" state) mill round them;
##   4. takes off (TAKE_OFF): from `gather` seconds after the call, one every
##      ~`every` seconds (those that came out first go first), each beats its
##      wings on the ground a moment, then climbs to `altitude` over `climb`
##      seconds while drifting `distance` units off toward `drift` (views
##      draw it larger and its shadow further off as it climbs), and leaves
##      the world.
## Alates that emerge after a flight was called wait for the next one. The
## escorts go back to their caste's first state when the last alate is gone.
## Alates don't age, eat or join the abstract population; scenario
## "population" may include them (they start waiting, e.g. a scenario that
## begins at the flight).
##
## params: from_population (400), count (12), castes ({"gyne": 1, "male": 2};
##   default: every alate caste, weight 1), stagger (s, 0.8), gather (s, 12),
##   every (s, 1.2), settle (s on the mound before taking off, 3), warm_up
##   (s beating on the ground, 0.8), climb (s, 7), altitude (420), distance
##   (260), drift ([x, y], default up and to the right: [0.5, -1]), spread
##   (radians the directions fan over, 0.9), gather_radius (45; they keep
##   off its inner fifth, the hole), escort (10),
##   escort_reach (160)

enum Phase { WAIT, UP, GATHER, TAKE_OFF }

var from_population: int = 400
var count: int = 12
var stagger: float = 0.8
var gather: float = 12.0
var every: float = 1.2
var settle: float = 3.0
var warm_up: float = 0.8
var climb: float = 7.0
var altitude: float = 420.0
var distance: float = 260.0
var drift: Vector2 = Vector2(0.5, -1.0).normalized()
var spread: float = 0.9
var gather_radius: float = 45.0
var escort: int = 10
var escort_reach: float = 160.0
## Alate caste indices and their weights.
var castes: PackedInt32Array = []
var weights: PackedFloat32Array = []
## Alates chosen for brood so far, per entry of `castes`.
var raised_by: PackedInt32Array = []
var raised: int = 0
## Alates that have flown, per entry of `castes`.
var flown_by: PackedInt32Array = []
var flown: int = 0

## Living alates (ant indices) and, per entry: phase, when it started (sim
## s), where the ant is heading (or, taking off, where it left the ground),
## when it sets off up (INF: not called), and a pause while waiting.
var ants: PackedInt32Array = []
var phase: PackedByteArray = []
var phase_at: PackedFloat64Array = []
var goal: PackedVector2Array = []
var depart: PackedFloat64Array = []
var rest_until: PackedFloat64Array = []
## Take-offs so far in this flight (fans their directions out).
var launched: int = 0
## True from start_flight() until every alate called has gone.
var flying: bool = false
var flight_at: float = 0.0
var next_take_off: float = 0.0
## Alates that came out onto the mound in this flight (spaces them out).
var gathered: int = 0
## Workers escorting the flight.
var escorts: PackedInt32Array = []
var _escort_timer: float = 0.0

func setup(species: SpeciesDef, params: Dictionary) -> void:
	from_population = int(params.get("from_population", from_population))
	count = int(params.get("count", count))
	stagger = float(params.get("stagger", stagger))
	gather = float(params.get("gather", gather))
	every = maxf(0.05, float(params.get("every", every)))
	settle = float(params.get("settle", settle))
	warm_up = float(params.get("warm_up", warm_up))
	climb = maxf(0.1, float(params.get("climb", climb)))
	altitude = float(params.get("altitude", altitude))
	distance = float(params.get("distance", distance))
	if params.has("drift"):
		drift = ScenarioEvents.vec2(params["drift"]).normalized()
	spread = float(params.get("spread", spread))
	gather_radius = float(params.get("gather_radius", gather_radius))
	escort = int(params.get("escort", escort))
	escort_reach = float(params.get("escort_reach", escort_reach))
	var w: Dictionary = params.get("castes", {})
	for c in species.castes.size():
		var def := species.castes[c]
		if not def.alate:
			continue
		var weight := float(w.get(str(def.id), 0.0 if not w.is_empty() else 1.0))
		if weight > 0.0:
			castes.append(c)
			weights.append(weight)
	for k: Variant in w:
		var c := species.caste_index(StringName(str(k)))
		if c < 0 or not species.castes[c].alate:
			push_warning("alates: \"%s\" is not an alate caste of %s" % [k, species.id])
	raised_by.resize(castes.size())
	flown_by.resize(castes.size())

## The caste of the next egg if it is to be an alate, else -1 (Brood asks for
## every egg): the caste furthest below its share of those raised so far.
func next_caste(sim: Simulation, nest: ColonyNest) -> int:
	if raised >= count or castes.is_empty() or sim.colonies[nest.colony_id].total_population() < from_population:
		return -1
	var total := 0.0
	for w in weights:
		total += w
	var best := 0
	var best_short := -INF
	for k in castes.size():
		var short := weights[k] / total * (raised + 1) - raised_by[k]
		if short > best_short + 1e-6:
			best_short = short
			best = k
	raised_by[best] += 1
	raised += 1
	return castes[best]

## States the nest adds for a caste (see NestType.extra_states).
func extra_states(caste: CasteDef) -> PackedStringArray:
	if caste.alate:
		return PackedStringArray(["alate"])
	if caste.carry_capacity > 0.0 and not caste.states.is_empty():
		return PackedStringArray(["escort"])
	return PackedStringArray()

func _index(i: int) -> int:
	return ants.find(i)

## Ant i became an alate (AlateBehaviour.enter).
func join(sim: Simulation, i: int) -> void:
	if _index(i) >= 0:
		return
	ants.append(i)
	phase.append(Phase.WAIT)
	phase_at.append(sim.time())
	goal.append(sim.pos[i])
	depart.append(INF)
	rest_until.append(sim.time())

## Ant i is no longer an alate (AlateBehaviour.exit).
func leave(i: int) -> void:
	var k := _index(i)
	if k < 0:
		return
	ants.remove_at(k)
	phase.remove_at(k)
	phase_at.remove_at(k)
	goal.remove_at(k)
	depart.remove_at(k)
	rest_until.remove_at(k)

## Alates now (views, tests), in the nest or out on the mound.
func alive_count() -> int:
	return ants.size()

## Calls a nuptial flight: every alate waiting sets off up in turn. Returns
## false if there was none to call (or a flight is under way).
func start_flight(sim: Simulation) -> bool:
	if flying:
		return false
	var n := 0
	for k in ants.size():
		if phase[k] == Phase.WAIT:
			depart[k] = sim.time() + n * stagger
			n += 1
	if n == 0:
		return false
	flying = true
	flight_at = sim.time()
	next_take_off = flight_at + gather
	gathered = 0
	launched = 0
	_escort_timer = 0.0
	return true

func _set_phase(sim: Simulation, k: int, p: int) -> void:
	phase[k] = p
	phase_at[k] = sim.time()

## One tick of alate i ("alate" state). Returns the next state ("" to stay).
func tick_alate(sim: Simulation, nest: ColonyNest, i: int, dt: float) -> String:
	var k := _index(i)
	if k < 0:
		join(sim, i)
		k = ants.size() - 1
	var ul := nest.underground_layer
	match phase[k]:
		Phase.WAIT:
			if sim.time() >= depart[k]:
				_set_phase(sim, k, Phase.UP)
			elif sim.layer[i] != ul:
				# Outside a flight, back down.
				Travel.to_portal(sim, i, nest.portal, sim.speed[i] * 0.5, dt)
			elif sim.time() >= rest_until[k]:
				if nest.walk_to(sim, i, ul, goal[k], sim.speed[i] * 0.35, dt, 3.0):
					goal[k] = nest.chambers_layout.random_point(_wait_chamber(nest), sim.rng, 2)
					rest_until[k] = sim.time() + sim.rng.randf_range(2.0, 7.0)
		Phase.UP:
			if sim.layer[i] == 0:
				_on_the_mound(sim, nest, k)
			else:
				var exit := Travel.best_portal(sim, i, 0, Vector2.ZERO, 0.0)
				Travel.to_portal(sim, i, exit if exit != null else nest.portal, sim.speed[i], dt)
		Phase.GATHER:
			# Milling on the mound: to a spot, a pause, another spot near it.
			if sim.time() >= rest_until[k]:
				var at := sim.pos[i]
				if at.distance_to(goal[k]) <= 2.0:
					var e := nest.nearest_entrance(at)
					goal[k] = e + Vector2.from_angle(sim.rng.randf() * TAU) * gather_radius * sqrt(sim.rng.randf_range(0.2, 1.0))
					rest_until[k] = sim.time() + sim.rng.randf_range(1.0, 4.0)
				else:
					Steering.move_to(sim, i, goal[k], sim.speed[i] * 0.3, dt)
					_step_legs(sim, i, 0.3, dt)
		Phase.TAKE_OFF:
			var t := sim.time() - phase_at[k]
			var dir := _drift_of(k)
			if t < warm_up:
				# Beating on the ground, turning into the wind.
				sim.heading[i] = lerp_angle(sim.heading[i], dir.angle(), minf(1.0, 3.0 * dt))
			else:
				var u := clampf((t - warm_up) / climb, 0.0, 1.0)
				var bounds := Rect2(Vector2.ZERO, Vector2(sim.world.size)).grow(-2.0)
				var at := goal[k] + dir * distance * u * u
				sim.pos[i] = Vector2(clampf(at.x, bounds.position.x, bounds.end.x), clampf(at.y, bounds.position.y, bounds.end.y))
				sim.heading[i] = lerp_angle(sim.heading[i], dir.angle(), minf(1.0, 2.0 * dt))
	return ""

func _step_legs(sim: Simulation, i: int, pace: float, dt: float) -> void:
	sim.anim_phase[i] += sim.speed[i] * pace * dt * sim.colonies[sim.colony_id[i]].caste_phase_per_unit[sim.caste_id[i]]

## Out on the surface: a spot on the mound round the entrance it came out of.
func _on_the_mound(sim: Simulation, nest: ColonyNest, k: int) -> void:
	var e := nest.nearest_entrance(sim.pos[ants[k]])
	# Spread out in a sunflower round the entrance.
	var n := gathered % 16
	goal[k] = e + Vector2.from_angle(gathered * 2.39996) * gather_radius * sqrt(0.2 + 0.8 * (n + 0.5) / 16.0)
	gathered += 1
	rest_until[k] = sim.time()
	_set_phase(sim, k, Phase.GATHER)

## Direction take-off k flies off in: `drift`, fanned out over `spread`.
func _drift_of(k: int) -> Vector2:
	var n := int(goal[k].x * 7.0 + goal[k].y * 13.0) % 97
	return drift.rotated((fposmod(n * 0.618034, 1.0) - 0.5) * spread)

## The chamber alates wait in: the dug chamber nearest the bottom of the main
## shaft (not a nursery; the royal chamber if there is no other).
func _wait_chamber(nest: ColonyNest) -> int:
	var best := 0
	var best_d := INF
	var shaft := nest.portal.pos_b
	for c in nest.chambers_layout.list:
		if c.index == 0 or not c.dug or c.kind != NestChambers.Kind.CHAMBER or nest.is_nursery(c.index):
			continue
		var d := c.centre.distance_to(shaft)
		if d < best_d:
			best_d = d
			best = c.index
	return best

## Once a tick (ColonyNest._update_colony): take-offs, alates that have flown
## leave the world, escorts are called, and the flight ends.
func update(sim: Simulation, nest: ColonyNest, dt: float) -> void:
	if not flying:
		return
	var now := sim.time()
	# Gone: those that have climbed out of sight.
	var k := 0
	while k < ants.size():
		if phase[k] == Phase.TAKE_OFF and now - phase_at[k] >= warm_up + climb:
			var i := ants[k]
			var c := castes.find(sim.caste_id[i])
			if c >= 0:
				flown_by[c] += 1
			flown += 1
			sim.remove_ant(i)
			if _index(i) >= 0:
				leave(i)
			continue
		k += 1
	# The next take-off: the one that came out first and has settled.
	if now >= next_take_off:
		var first := -1
		for j in ants.size():
			if phase[j] == Phase.GATHER and now - phase_at[j] >= settle and (first < 0 or phase_at[j] < phase_at[first]):
				first = j
		if first >= 0:
			goal[first] = sim.pos[ants[first]]
			_set_phase(sim, first, Phase.TAKE_OFF)
			launched += 1
			# Not quite regular.
			next_take_off = now + every * (0.6 + 0.8 * fposmod(launched * 0.618034, 1.0))
	_escort_timer -= dt
	if _escort_timer <= 0.0:
		_escort_timer = 1.0
		_call_escorts(sim, nest)
	# Over once every alate called has gone.
	var called := false
	for j in ants.size():
		if depart[j] < INF:
			called = true
			break
	if not called:
		flying = false

## While alates are on the mound, idle-ish surface workers near the entrance
## (not carrying, not riding; the biggest first, then the nearest) come to
## mill round them, up to `escort`.
func _call_escorts(sim: Simulation, nest: ColonyNest) -> void:
	var k := 0
	while k < escorts.size():
		var a := escorts[k]
		if sim.alive[a] == 0 or sim.state_id(a) != "escort":
			escorts.remove_at(k)
		else:
			k += 1
	var out := false
	for j in ants.size():
		if phase[j] == Phase.GATHER or phase[j] == Phase.TAKE_OFF:
			out = true
	if not out or escorts.size() >= escort:
		return
	var colony := sim.colonies[nest.colony_id]
	var s: int = sim.behaviour_index.get("escort", -1)
	var e := nest.entrance_position()
	var found: Array[Vector2] = []
	for i in sim.high_water:
		if sim.alive[i] == 0 or sim.colony_id[i] != nest.colony_id or sim.layer[i] != 0 or sim.transit_until[i] != 0:
			continue
		if sim.carried[i] >= 0 or sim.riding[i] >= 0 or sim.state[i] == s or not colony.allows(sim.caste_id[i], s):
			continue
		var d := sim.pos[i].distance_to(e)
		if d <= escort_reach:
			found.append(Vector2(d - sim.caste_of(i).size * 10.0, i))
	found.sort()
	for f in found:
		if escorts.size() >= escort:
			break
		var i := int(f.y)
		sim.change_state(i, "escort")
		escorts.append(i)

## One tick of an escorting worker: milling round the mound, just outside the
## alates, until the flight is over; then its caste's first state.
func tick_escort(sim: Simulation, nest: ColonyNest, i: int, dt: float) -> String:
	if not flying or sim.layer[i] != 0:
		return sim.caste_of(i).initial_state
	var e := nest.entrance_position()
	if sim.pos[i].distance_to(sim.target[i]) <= 3.0 or sim.target[i].distance_to(e) > gather_radius * 2.0:
		sim.target[i] = e + Vector2.from_angle(sim.rng.randf() * TAU) * gather_radius * sim.rng.randf_range(1.0, 1.6)
	Steering.move_to(sim, i, sim.target[i], sim.speed[i] * 0.45, dt)
	return ""

## Alate i's wings for views (NestType.winged_ants): two pairs; folded in
## the nest and on the way up; on the mound spread now and then; beating
## while it takes off, with its altitude.
func wings_of(sim: Simulation, i: int) -> Vector3:
	var k := _index(i)
	if k < 0:
		return Vector3(2, 0, 0)
	match phase[k]:
		Phase.GATHER:
			var t := sim.time() * 0.35 + i * 0.37
			return Vector3(2, 0, 0.05 if fposmod(t, 1.0) < 0.18 else 0.0)
		Phase.TAKE_OFF:
			var t := sim.time() - phase_at[k]
			var u := clampf((t - warm_up) / climb, 0.0, 1.0)
			return Vector3(2, altitude * pow(u, 1.6), 1.0)
	return Vector3(2, 0, 0)

func hash_into(ctx: HashingContext) -> void:
	ctx.update(PackedFloat64Array([raised, flown, launched, 1 if flying else 0, flight_at, next_take_off, gathered]).to_byte_array())
	ctx.update(ants.to_byte_array())
	ctx.update(phase)
	ctx.update(phase_at.to_byte_array())
	ctx.update(goal.to_byte_array())
	ctx.update(escorts.to_byte_array())
