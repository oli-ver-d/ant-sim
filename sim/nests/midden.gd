class_name Midden
extends RefCounted
## A refuse dump on the surface and what lies on it. A nest's middens
## (NestType.middens) are sited as the colony needs them (see NestType
## "Refuse"); workers carrying refuse out ask it for a drop point
## (drop_point()) and leave their load there as a deposit (add()).
##
## Deposits are small records in packed arrays (not Items, so a midden can
## hold thousands): where, what kind (an index into `kinds`, ids of
## RefuseKind), the mass dropped and when. A deposit rots with its kind's
## half-life; once little is left of it (MERGE_BELOW) what remains is merged
## into the `stain`, a low-res grid of accumulated matter round the site,
## and the rest counts as `decayed`. The oldest deposits are merged the same
## way when there are more than MAX_DEPOSITS, so a midden stays cheap however
## long the run. None of this is simulation state (it is never hashed and
## draws no random numbers); where the middens are and where loads land is.
##
## Styles (where loads land):
##   "pile"    a heap that spreads outward, away from the nest: loads land on
##             the side facing the nest of a pile whose middle moves outward
##             as it grows;
##   "ring"    an arc of a band round the nest (at the edge of a cleared
##             disc), widening along the band as it fills;
##   "scatter" loose deposits along a stretch across the way out.

const STYLES: PackedStringArray = ["pile", "ring", "scatter"]
## A pile's radius: BASE_RADIUS + GROWTH * sqrt(mass lying on it).
const BASE_RADIUS := 7.0
const GROWTH := 2.2
## Deposits merged into the stain once this share of their mass is left.
const MERGE_BELOW := 0.2
const MAX_DEPOSITS := 1500
## Stain grid: cells of STAIN_CELL world units, STAIN_SIZE a side, centred
## on the site.
const STAIN_CELL := 4.0
const STAIN_SIZE := 64
## Simulated seconds between rot sweeps.
const SWEEP_EVERY := 5.0

var index: int = 0
var style: String = "pile"
## The site: the pile's first middle, the middle of the ring's arc, the
## middle of the scattered stretch.
var position: Vector2
## The entrance it serves, and the unit direction from it to the site.
var anchor: Vector2
var outward: Vector2 = Vector2.RIGHT
## Distance of a ring's band from the anchor.
var ring_radius: float = 0.0
## Mass that makes it full (the nest then sites another, if it may).
var capacity: float = 30.0

## Mass and loads ever dropped here.
var received: float = 0.0
var loads: int = 0
## Mass lying here (deposits and stain; as of the last sweep, plus loads
## dropped since): what the pile's size follows.
var present: float = 0.0
## Kinds of refuse (RefuseKind ids) the deposits refer to by index.
var kinds: PackedStringArray = []
var dep_pos: PackedVector2Array = []
var dep_kind: PackedInt32Array = []
## Mass when dropped, and the simulated time it was dropped.
var dep_mass: PackedFloat32Array = []
var dep_time: PackedFloat32Array = []
## Matter merged from old deposits, per cell, and its total.
var stain: PackedFloat32Array = []
var stain_mass: float = 0.0
## Mass rotted away from deposits merged so far.
var decayed: float = 0.0
## Each deposit's id: its number in drop order (never reused, so a renderer
## can tell new deposits from old ones; the arrays stay in drop order).
var dep_id: PackedInt32Array = []
## Extra per-deposit detail for drawing it: the caste of a dead worker
## (-1 for anything else).
var dep_extra: PackedInt32Array = []
## Bumped whenever deposits or the stain change (for renderers).
var version: int = 0
var _swept_at: float = 0.0

func _init(site: Vector2, from: Vector2, midden_style: String, full_at: float) -> void:
	position = site
	anchor = from
	style = midden_style
	capacity = full_at
	outward = (site - from).normalized() if site != from else Vector2.RIGHT
	ring_radius = site.distance_to(from)
	stain.resize(STAIN_SIZE * STAIN_SIZE)

func is_full() -> bool:
	return received >= capacity

## How far the refuse reaches from its middle (a pile's radius; half the
## extent of a ring's arc or a scattered stretch).
func radius() -> float:
	return BASE_RADIUS + GROWTH * sqrt(present)

## Middle of what lies here now: a pile's middle moves outward as it grows.
func centre() -> Vector2:
	if style == "pile":
		return position + outward * (radius() - BASE_RADIUS) * 0.5
	return position

## Where the next load lands, from two uniform random numbers in [0, 1).
func drop_point(u1: float, u2: float) -> Vector2:
	var r := radius()
	match style:
		"ring":
			# Along the band: the arc widens as it fills (up to half the ring).
			var half := minf(PI * 0.5, (r * 1.6) / maxf(ring_radius, 1.0))
			var a := outward.angle() + (u1 - 0.5) * 2.0 * half
			var band := 8.0 + 0.8 * sqrt(present)
			return anchor + Vector2.from_angle(a) * (ring_radius + (u2 - 0.5) * band)
		"scatter":
			var across := outward.orthogonal()
			return position + across * (u1 - 0.5) * 2.4 * r + outward * (u2 - 0.5) * 16.0
		_:
			# On the side facing the nest (within about 110 degrees of it).
			var c := centre()
			var toward := (anchor - c).angle()
			return c + Vector2.from_angle(toward + (u1 - 0.5) * 3.8) * r * sqrt(u2)

## Adds a deposit of `mass` of refuse kind `kind` at `at`, dropped at `time`
## (`extra`: see dep_extra).
func add(kind: String, at: Vector2, mass: float, time: float, registry: Registry, extra: int = -1) -> void:
	var k := kinds.find(kind)
	if k < 0:
		k = kinds.size()
		kinds.append(kind)
	dep_pos.append(at)
	dep_kind.append(k)
	dep_mass.append(mass)
	dep_time.append(time)
	dep_id.append(loads)
	dep_extra.append(extra)
	received += mass
	present += mass
	loads += 1
	version += 1
	if dep_pos.size() > MAX_DEPOSITS:
		_merge(time, dep_pos.size() - MAX_DEPOSITS, registry)

func count() -> int:
	return dep_pos.size()

## Mass deposit d has left at `time`.
func mass_left(d: int, time: float, registry: Registry) -> float:
	return dep_mass[d] * _kind(d, registry).left_after(time - dep_time[d])

## Mass in the deposits at `time`.
func deposit_mass(time: float, registry: Registry) -> float:
	var m := 0.0
	for d in dep_pos.size():
		m += mass_left(d, time, registry)
	return m

## Mass rotted away by `time` (merged deposits and the ones still here).
func decayed_mass(time: float, registry: Registry) -> float:
	var m := decayed
	for d in dep_pos.size():
		m += dep_mass[d] - mass_left(d, time, registry)
	return m

## Rots the deposits: merges the ones that have mostly gone into the stain.
## Cheap to call every tick (sweeps every SWEEP_EVERY seconds).
func update(time: float, registry: Registry) -> void:
	if time - _swept_at < SWEEP_EVERY:
		return
	_swept_at = time
	_merge(time, 0, registry)
	present = deposit_mass(time, registry) + stain_mass

## Merges the first `oldest` deposits, and every one with less than
## MERGE_BELOW of its mass left, into the stain.
func _merge(time: float, oldest: int, registry: Registry) -> void:
	var n := dep_pos.size()
	var keep := 0
	for d in n:
		var left := _kind(d, registry).left_after(time - dep_time[d])
		if d < oldest or left < MERGE_BELOW:
			var m := dep_mass[d] * left
			_stain_add(dep_pos[d], m)
			decayed += dep_mass[d] - m
			continue
		if keep != d:
			dep_pos[keep] = dep_pos[d]
			dep_kind[keep] = dep_kind[d]
			dep_mass[keep] = dep_mass[d]
			dep_time[keep] = dep_time[d]
			dep_id[keep] = dep_id[d]
			dep_extra[keep] = dep_extra[d]
		keep += 1
	if keep == n:
		return
	dep_pos.resize(keep)
	dep_kind.resize(keep)
	dep_mass.resize(keep)
	dep_time.resize(keep)
	dep_id.resize(keep)
	dep_extra.resize(keep)
	version += 1

## World position of stain cell (x, y)'s corner.
func stain_origin() -> Vector2:
	return position - Vector2.ONE * STAIN_CELL * STAIN_SIZE * 0.5

func _stain_add(at: Vector2, m: float) -> void:
	var c := ((at - stain_origin()) / STAIN_CELL).floor()
	var x := clampi(int(c.x), 0, STAIN_SIZE - 1)
	var y := clampi(int(c.y), 0, STAIN_SIZE - 1)
	stain[y * STAIN_SIZE + x] += m
	stain_mass += m

func _kind(d: int, registry: Registry) -> RefuseKind:
	var k: RefuseKind = registry.refuse_kinds.get(kinds[dep_kind[d]])
	return k if k != null else _NEVER

## Unregistered kinds never rot.
static var _NEVER := RefuseKind.new("", 0.0)
