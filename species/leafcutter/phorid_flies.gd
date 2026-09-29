class_name PhoridFlies
extends RefCounted
## Phorid flies over the leaf line (nest_params "phorids"): tiny parasitoid
## flies that hover over ants carrying leaf fragments and dive at their
## heads. A carrier with a minim riding its fragment is guarded: a fly
## diving at it veers off before it gets there. One without is hit, and the
## fly comes round again a few times before looking for another.
##
## Render-only flavour: moved from sim state (carried fragments, carriers,
## riders) after each frame, with its own RandomNumberGenerator. It never
## writes the simulation or draws from sim.rng, so it can't change a hash.
## Drawn by PhoridRenderer ("surface_top:fungus_nest").
##
## params: count (5), reach (170: how far a fly looks for a carrier), dives
## (3 at one carrier), speed (70 world units/s; dives are 3x), altitude (9),
## arrive (2: seconds between flies turning up), clear (90: carriers this
## near the nest entrance are left alone), item ("leaf_fragment"), seed (0).

enum Mode { AWAY, TRAIL, DIVE, VEER }

## A diving fly this close to a carrier's head hits it; one diving at a
## guarded carrier veers off this far out.
const HIT := 2.5
const GUARD := 13.0
## Longest step the flies move in; longest gap they catch up on (seconds).
const MAX_STEP := 1.0 / 30.0
const CATCH_UP := 8.0
## Picking a carrier, each fly already after it counts as this much further.
const TAKEN := 80.0

var count: int = 5
var reach: float = 170.0
var dives: int = 3
var speed: float = 70.0
var altitude: float = 9.0
var arrive: float = 2.0
var item_type: String = "leaf_fragment"
var clear: float = 90.0
var home: Vector2 = Vector2.INF

var pos: PackedVector2Array = []
var alt: PackedFloat32Array = []
var heading: PackedFloat32Array = []
var mode: PackedByteArray = []
## Item id of the fragment whose carrier the fly is after, or -1.
var target: PackedInt32Array = []
var timer: PackedFloat32Array = []
## Dives left at the current carrier.
var left: PackedInt32Array = []
## Where the fly hangs round its carrier (offset from its head).
var offset: PackedVector2Array = []
## Veer-off velocity.
var vel: PackedVector2Array = []
## 0..1: faded in while about, out while away.
var shown: PackedFloat32Array = []
## Hits on unguarded carriers, dives broken off at guarded ones, and hits on
## guarded ones (never: tests check it).
var hits: int = 0
var veered: int = 0
var hits_guarded: int = 0

var rng := RandomNumberGenerator.new()
var _last_time: float = -1.0
## Carriers this frame: item id -> [carrier index, head position, guarded].
var _carriers: Dictionary[int, Array] = {}

## `nest_at`: the nest entrance (carriers within `clear` of it are left alone).
func setup(params: Dictionary, seed_value: int, nest_at: Vector2) -> void:
	home = nest_at
	clear = float(params.get("clear", clear))
	count = int(params.get("count", count))
	reach = float(params.get("reach", reach))
	dives = int(params.get("dives", dives))
	speed = float(params.get("speed", speed))
	altitude = float(params.get("altitude", altitude))
	arrive = float(params.get("arrive", arrive))
	item_type = str(params.get("item", item_type))
	rng.seed = hash([seed_value, int(params.get("seed", 0)), "phorids"])
	for f in count:
		pos.append(Vector2.ZERO)
		alt.append(altitude)
		heading.append(0.0)
		mode.append(Mode.AWAY)
		target.append(-1)
		timer.append(arrive * (f + rng.randf()))
		left.append(0)
		offset.append(Vector2.ZERO)
		vel.append(Vector2.ZERO)
		shown.append(0.0)

## Moves the flies to sim time `now` (seconds; `alpha` interpolates ant
## positions between the last two ticks, as the renderers do).
## After a jump (the first frame, or a fast-forward to a still), the flies
## catch up over up to CATCH_UP seconds with the ants where they are now.
func update(sim: Simulation, now: float, alpha: float = 1.0) -> void:
	var gap := now - _last_time if _last_time >= 0.0 else CATCH_UP
	_last_time = now
	if gap <= 0.0:
		return
	_find_carriers(sim, alpha)
	var steps := ceili(minf(gap, CATCH_UP) / MAX_STEP)
	for s in steps:
		for f in count:
			_update_fly(f, minf(gap, CATCH_UP) / steps)

func active_count() -> int:
	var n := 0
	for f in count:
		n += 1 if mode[f] != Mode.AWAY else 0
	return n

func _find_carriers(sim: Simulation, alpha: float) -> void:
	_carriers.clear()
	for id: int in sim.carried_items:
		var item: Item = sim.items.get(id)
		if item == null or item.type_id != item_type or item.layer != 0 or item.carrier < 0:
			continue
		var i := item.carrier
		if sim.alive[i] == 0 or sim.layer[i] != 0 or sim.shown_pos[i].distance_to(home) < clear:
			continue
		var h := lerp_angle(sim.prev_heading[i], sim.shown_heading[i], alpha)
		var at := sim.prev_pos[i].lerp(sim.shown_pos[i], alpha)
		var head := at + Vector2.from_angle(h) * sim.caste_of(i).size * 0.45
		_carriers[id] = [i, head, item.riders.size() > 0]

func _update_fly(f: int, dt: float) -> void:
	timer[f] -= dt
	var m := mode[f]
	if m == Mode.AWAY:
		shown[f] = maxf(0.0, shown[f] - dt * 1.5)
		if timer[f] <= 0.0 and not _carriers.is_empty():
			# Turn up near a carrier.
			var id := _pick(Vector2.INF)
			var head: Vector2 = _carriers[id][1]
			pos[f] = head + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.5, 0.8) * reach
			alt[f] = altitude * 2.0
			_trail(f, id)
		return
	shown[f] = minf(1.0, shown[f] + dt * 2.0)
	var carrier: Array = _carriers.get(target[f], [])
	if carrier.is_empty() and m != Mode.VEER:
		# Delivered, dropped or gone underground: look for another.
		_retarget(f)
		return
	match m:
		Mode.TRAIL:
			var goal: Vector2 = carrier[1] + offset[f]
			_fly_to(f, goal, speed, dt)
			alt[f] = move_toward(alt[f], altitude, dt * 20.0)
			if timer[f] <= 0.0:
				mode[f] = Mode.DIVE
		Mode.DIVE:
			var head: Vector2 = carrier[1]
			_fly_to(f, head, speed * 3.0, dt)
			var d := pos[f].distance_to(head)
			alt[f] = altitude * clampf(d / 25.0, 0.1, 1.0)
			if carrier[2] and d < GUARD:
				# The rider rears up at it: break off.
				veered += 1
				_veer(f, head)
			elif d < HIT:
				if carrier[2]:
					hits_guarded += 1
				hits += 1
				left[f] -= 1
				_veer(f, head)
		Mode.VEER:
			pos[f] += vel[f] * dt
			vel[f] *= exp(-3.0 * dt)
			heading[f] = vel[f].angle()
			alt[f] = move_toward(alt[f], altitude * 1.4, dt * 30.0)
			if timer[f] <= 0.0:
				if carrier.is_empty() or left[f] <= 0 or carrier[2]:
					_retarget(f)
				else:
					_trail(f, target[f])

## Follow carrier `id`, hanging round its head a moment before diving.
func _trail(f: int, id: int) -> void:
	if target[f] != id:
		left[f] = dives
	target[f] = id
	mode[f] = Mode.TRAIL
	offset[f] = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(12.0, 22.0)
	timer[f] = rng.randf_range(0.8, 2.2)

func _veer(f: int, from: Vector2) -> void:
	mode[f] = Mode.VEER
	var away := (pos[f] - from).normalized() if pos[f] != from else Vector2.from_angle(rng.randf() * TAU)
	vel[f] = away.rotated(rng.randf_range(-0.8, 0.8)) * speed * 1.6
	timer[f] = rng.randf_range(0.35, 0.7)

## Another carrier within reach, or off.
func _retarget(f: int) -> void:
	var id := _pick(pos[f], target[f])
	if id < 0:
		mode[f] = Mode.AWAY
		target[f] = -1
		timer[f] = arrive * rng.randf_range(1.0, 2.0)
		return
	target[f] = -1
	_trail(f, id)

## A carrier to go after: the nearest to `near` within reach, or any one at
## random (near = INF), preferring those no other fly is after. A fly can't
## tell a guarded carrier until it dives. Never `skip` (the carrier just
## left). -1 if there are none.
func _pick(near: Vector2, skip: int = -1) -> int:
	var best := -1
	var best_score := INF
	for id: int in _carriers:
		if id == skip:
			continue
		var score: float
		if near == Vector2.INF:
			score = rng.randf() * reach
		else:
			score = near.distance_to(_carriers[id][1])
			if score > reach:
				continue
		score += TAKEN * target.count(id)
		if score < best_score:
			best_score = score
			best = id
	return best

## Buzz toward `goal`: straight at up to `v`, with a jitter.
func _fly_to(f: int, goal: Vector2, v: float, dt: float) -> void:
	var step := (goal - pos[f]).limit_length(v * dt)
	var jitter := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * speed * 0.35 * dt
	pos[f] += step + jitter
	if step.length_squared() > 0.0001:
		heading[f] = lerp_angle(heading[f], step.angle(), minf(1.0, dt * 12.0))
