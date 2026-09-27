class_name Scatter
extends RefCounted
## Scatters scenery props over an area from a preset, instead of placing each
## one by hand (a scenario "scenery" entry with "scatter"):
##   {"scatter": {"preset": "meadow", "density": 1.0, "keep_clear": 30,
##                "avoid": ["nests", "food", "portals"], "rect": [x, y, w, h],
##                "clear": [obstacle shapes], "reserve": 1.0, "seed": n}}
## Presets (PRESETS): meadow, forest_floor, rocky, sandy ("entries" and
## "per_mu" in the scatter replace a preset's own). Each lists prop
## entries with a weight, a size range and the ground materials they like
## (from the scenario's GroundMap), so moss grows ferns and sand gets few plants.
##
## Placement is dart throwing with a minimum spacing per pair (Poisson-disc
## like), from its own RandomNumberGenerator (never the Simulation's), so the
## same scenario seed always gives the same scatter and runs without scatter
## are untouched. "blocking": false keeps only the plant and grass entries,
## cut to their canopy (stem 0), so nothing reaches the simulation and a
## scenario keeps its state hashes. Loaded after the colonies and food, since it keeps clear of:
##   - hard zones (no prop at all): each nest's drawn entrances (+ keep_clear),
##     its cleared disc, spoil heaps, planned entrances, a fixed dump, food,
##     surface portals, "clear" shapes (polylines = paths) and the world edge;
##   - reserve zones (nothing blocking; a plant there keeps only its canopy):
##     room round each nest for the middens it will site (midden_distance)
##     and the extra entrances it will dig (entrance_spacing), scaled by
##     "reserve".
## Then connectivity: the surface is flood-filled from each nest; while a food
## source the colony uses (or the world edge) that was reachable before the
## scatter no longer is, the newest blocking scattered prop bordering the
## nest's reachable area is dropped (a plant keeps its canopy, stem 0).

## A preset: "per_mu" darts per million square units at density 1 (each is
## thinned by the ground, keep-clear zones and spacing), and its
## entries. An entry's "type" is a scenery type (plus "kind" for plants);
## "w" its weight; "size" the radius range (a log's length); "spacing" how
## close its reach may come to others' (1 = not overlapping); "prefer" a
## weight factor per ground material (1 if absent); "params" extra prop
## params, where [a, b] is a random value in that range.
const PRESETS := {
	"meadow": {"per_mu": 360.0, "entries": [
		{"type": "grass", "w": 5.0, "size": [30, 65], "spacing": 0.45,
			"prefer": {"moss": 1.4, "sand": 0.3, "dry": 0.4, "gravel": 0.5}},
		{"type": "plant", "kind": "rosette", "w": 2.0, "size": [35, 70], "spacing": 0.6,
			"prefer": {"sand": 0.2, "dry": 0.5, "gravel": 0.4}},
		{"type": "plant", "kind": "clover", "w": 2.0, "size": [35, 50], "spacing": 0.6,
			"prefer": {"moss": 1.3, "sand": 0.1, "dry": 0.3}},
		{"type": "plant", "kind": "seedling", "w": 1.5, "size": [10, 18], "spacing": 0.8,
			"prefer": {"litter": 1.5, "sand": 0.3}},
		{"type": "plant", "kind": "fern", "w": 0.3, "size": [60, 90], "spacing": 0.6,
			"prefer": {"moss": 4.0, "litter": 2.0, "sand": 0.0, "dry": 0.0, "gravel": 0.2}},
		{"type": "rock", "w": 0.4, "size": [12, 24], "spacing": 1.0,
			"prefer": {"gravel": 4.0, "moss": 0.5}, "params": {"flat": [0.6, 0.95]}},
	]},
	"forest_floor": {"per_mu": 150.0, "entries": [
		{"type": "plant", "kind": "fern", "w": 3.0, "size": [60, 100], "spacing": 0.6,
			"prefer": {"moss": 2.0, "litter": 1.5, "sand": 0.1, "dry": 0.2}},
		{"type": "log", "w": 0.6, "size": [110, 240], "spacing": 1.0,
			"prefer": {"litter": 1.5, "moss": 1.3, "sand": 0.2},
			"params": {"width": [16, 32], "taper": [0.5, 0.8]}},
		{"type": "rock", "w": 0.6, "size": [18, 40], "spacing": 1.0,
			"prefer": {"moss": 1.5, "gravel": 2.0}, "params": {"flat": [0.6, 0.9]}},
		{"type": "plant", "kind": "seedling", "w": 2.0, "size": [10, 18], "spacing": 0.8,
			"prefer": {"litter": 1.5, "moss": 1.2}},
		{"type": "grass", "w": 0.8, "size": [25, 45], "spacing": 0.5,
			"prefer": {"litter": 0.5, "moss": 0.8}},
		{"type": "plant", "kind": "rosette", "w": 0.5, "size": [30, 50], "spacing": 0.6,
			"prefer": {"litter": 0.6}},
	]},
	"rocky": {"per_mu": 110.0, "entries": [
		{"type": "rock", "w": 4.0, "size": [12, 55], "spacing": 1.0,
			"prefer": {"gravel": 2.0, "sand": 0.7, "moss": 0.6},
			"params": {"flat": [0.55, 0.95], "lumpy": [0.15, 0.35]}},
		{"type": "grass", "w": 1.5, "size": [25, 50], "spacing": 0.45,
			"prefer": {"gravel": 0.5, "moss": 1.5}},
		{"type": "plant", "kind": "seedling", "w": 1.0, "size": [10, 16], "spacing": 0.8},
		{"type": "plant", "kind": "rosette", "w": 0.4, "size": [30, 50], "spacing": 0.6,
			"prefer": {"gravel": 0.4}},
	]},
	"sandy": {"per_mu": 90.0, "entries": [
		{"type": "rock", "w": 1.0, "size": [10, 30], "spacing": 1.0,
			"params": {"stone": "sandstone", "flat": [0.6, 0.95]}},
		{"type": "grass", "w": 1.0, "size": [25, 45], "spacing": 0.5,
			"prefer": {"sand": 0.6, "soil": 1.5}},
		{"type": "plant", "kind": "seedling", "w": 0.5, "size": [10, 14], "spacing": 0.8,
			"prefer": {"sand": 0.5}},
	]},
}

## Default margin round nests and food, and round blocking props' footprints.
const KEEP_CLEAR := 30.0
const BLOCK_GAP := 12.0
## Room kept round a spoil heap and a fixed dump.
const SPOIL_ROOM := 55.0
const DUMP_ROOM := 50.0
## Room a full midden needs beyond its site (see Midden.radius()).
const MIDDEN_ROOM := 40.0
const BUCKET := 128.0

## A keep-clear zone: a shape and whether it keeps out every prop (hard) or
## only blocking ones (reserve).
class Zone:
	var shape: String
	var center: Vector2
	var radius: float
	var rect: Rect2
	var points: PackedVector2Array
	var width: float
	var hard: bool = true

	## Distance from `at` to the zone (negative inside a circle).
	func distance(at: Vector2) -> float:
		match shape:
			"circle":
				return at.distance_to(center) - radius
			"rect":
				var q := Vector2(clampf(at.x, rect.position.x, rect.end.x), clampf(at.y, rect.position.y, rect.end.y))
				return at.distance_to(q)
			"polygon":
				if Geometry2D.is_point_in_polygon(at, points):
					return -1.0
				return _to_segments(at, true)
			"polyline":
				return _to_segments(at, false) - width * 0.5
		return INF

	func _to_segments(at: Vector2, closed: bool) -> float:
		var best := INF
		var n := points.size()
		if n == 1:
			return at.distance_to(points[0])
		for i in (n if closed else n - 1):
			var q := Geometry2D.get_closest_point_to_segment(at, points[i], points[(i + 1) % n])
			best = minf(best, at.distance_to(q))
		return best

## One candidate or placed prop. Distances are measured from its core, the
## segment a-b (a point for all but logs): `reach` is how far its body or
## canopy extends round the core, `block` how far its blocking footprint does.
class Placed:
	var prop: Prop
	var data: Dictionary
	var at: Vector2
	var a: Vector2
	var b: Vector2
	var reach: float
	var spacing: float
	var block: float
	## Dart number, to keep the placing order stable.
	var order: int

	## Furthest the prop extends from `at`, for bucket searches.
	func extent() -> float:
		return reach * spacing + at.distance_to(a) + BLOCK_GAP

	## Distance between the two cores.
	func core_distance(q: Placed) -> float:
		if a == b and q.a == q.b:
			return at.distance_to(q.at)
		if q.a == q.b:
			return q.at.distance_to(Geometry2D.get_closest_point_to_segment(q.at, a, b))
		if a == b:
			return at.distance_to(Geometry2D.get_closest_point_to_segment(at, q.a, q.b))
		var pts := Geometry2D.get_closest_points_between_segments(a, b, q.a, q.b)
		return pts[0].distance_to(pts[1])

	## Nearest distance from the core to a zone.
	func zone_distance(z: Zone) -> float:
		if a == b:
			return z.distance(at)
		var n := maxi(2, ceili(a.distance_to(b) / 16.0))
		var best := INF
		for i in n + 1:
			best = minf(best, z.distance(a.lerp(b, float(i) / n)))
		return best

## What apply() did, for tests and logs.
class Result:
	var placed: Array[Prop] = []
	## Blocking props dropped (or plants cut to canopy) to keep food reachable.
	var dropped: int = 0
	var zones: Array[Zone] = []

## Scatters props from a scenario entry's "scatter" dictionary. `index` (the
## entry's place in the scenario) seeds its RNG with the scenario seed.
static func apply(sim: Simulation, s: Dictionary, index: int = 0) -> Result:
	var result := Result.new()
	var preset_name := str(s.get("preset", "meadow"))
	if not PRESETS.has(preset_name) and not s.has("entries"):
		push_error("Unknown scatter preset '%s' (use %s)" % [preset_name, ", ".join(PRESETS.keys())])
		return result
	# "entries" and "per_mu" replace the preset's own.
	var preset: Dictionary = PRESETS.get(preset_name, {}).duplicate()
	for key: String in ["entries", "per_mu"]:
		if s.has(key):
			preset[key] = s[key]
	if not bool(s.get("blocking", true)):
		preset["entries"] = canopy_only(preset["entries"])
		if preset["entries"].is_empty():
			return result
	var world := sim.world
	var world_rect := Rect2(Vector2.ZERO, Vector2(world.size))
	var area := world_rect
	if s.has("rect"):
		area = ScenarioEvents.rect2(s["rect"]).intersection(world_rect)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["seed"]) if s.has("seed") else Scenery.prop_seed_for(sim.scenery.seed_value, 1000000 + index)
	var margin := float(s.get("keep_clear", KEEP_CLEAR))
	result.zones = keep_clear_zones(sim, s, margin)
	var baseline := _reachability(sim, [])
	var entries: Array = preset["entries"]
	var total_w := 0.0
	for e: Dictionary in entries:
		total_w += float(e["w"])
	# Darts thrown: each one is thinned by the ground, keep-clear zones and
	# spacing, so what lands follows the ground and never piles up elsewhere.
	var darts := int(round(float(preset["per_mu"]) * float(s.get("density", 1.0)) * area.get_area() / 1.0e6))
	var candidates: Array[Placed] = []
	for dart in darts:
		var at := area.position + Vector2(rng.randf(), rng.randf()) * area.size
		# Which entry, weighted by how much each likes the ground here; the
		# ground's total liking thins everything out (sand gets few plants).
		var weights: PackedFloat32Array = []
		var sum := 0.0
		var mats: Dictionary = {"soil": 1.0}
		if sim.ground != null:
			mats = sim.ground.weights_at(at)
		for e: Dictionary in entries:
			var like := 0.0
			var prefer: Dictionary = e.get("prefer", {})
			for m: String in mats:
				like += mats[m] * float(prefer.get(m, 1.0))
			weights.append(float(e["w"]) * like)
			sum += weights[-1]
		var u := rng.randf()
		var pick := rng.randf() * sum
		var size_u := rng.randf()
		var spin := rng.randf()
		if sum <= 0.0 or u > sum / total_w:
			continue
		var k := 0
		while k < weights.size() - 1 and pick > weights[k]:
			pick -= weights[k]
			k += 1
		var c := _candidate(entries[k], at, size_u, spin, rng)
		c.order = dart
		candidates.append(c)
	# The biggest first, so logs and boulders find room before the small stuff.
	candidates.sort_custom(func(x: Placed, y: Placed) -> bool:
		var ex := x.extent()
		var ey := y.extent()
		return ex > ey or (ex == ey and x.order < y.order))
	var placed: Array[Placed] = []
	var buckets: Dictionary[Vector2i, Array] = {}
	var max_extent := 0.0
	for p in candidates:
		if not _fits(world, world_rect, result.zones, p):
			continue
		if not _spaced(buckets, p, max_extent):
			continue
		p.prop = sim.scenery.add(p.data)
		if p.prop == null:
			continue
		placed.append(p)
		result.placed.append(p.prop)
		max_extent = maxf(max_extent, p.extent())
		var b := Vector2i((p.at / BUCKET).floor())
		if not buckets.has(b):
			buckets[b] = []
		buckets[b].append(p)
	result.dropped = _keep_connected(sim, placed, baseline, result)
	return result

## The plant and grass entries of `entries`, with their stems cut to 0.
static func canopy_only(entries: Array) -> Array:
	var out: Array = []
	for e: Dictionary in entries:
		if str(e["type"]) != "plant" and str(e["type"]) != "grass":
			continue
		var c := e.duplicate()
		var params: Dictionary = c.get("params", {}).duplicate()
		params["stem"] = 0.0
		c["params"] = params
		out.append(c)
	return out

## Builds a candidate's prop data at `at`.
static func _candidate(e: Dictionary, at: Vector2, size_u: float, spin: float, rng: RandomNumberGenerator) -> Placed:
	var p := Placed.new()
	p.at = at
	p.a = at
	p.b = at
	p.spacing = float(e.get("spacing", 1.0))
	var size_range: Array = e["size"]
	var size := lerpf(float(size_range[0]), float(size_range[1]), size_u)
	var data := {"type": str(e["type"])}
	var extra: Dictionary = e.get("params", {})
	for key: String in extra:
		var v: Variant = extra[key]
		data[key] = lerpf(float(v[0]), float(v[1]), rng.randf()) if v is Array else v
	match data["type"]:
		"rock":
			data["center"] = [at.x, at.y]
			data["radius"] = size
			# A blob's lumps reach out to (1 + lumpy) times its radius.
			p.reach = size * (1.0 + float(data.get("lumpy", 0.25)))
			p.block = p.reach
		"log":
			var dir := Vector2.from_angle(spin * TAU)
			var bend := dir.orthogonal() * size * rng.randf_range(-0.12, 0.12)
			var a := at - dir * size * 0.5
			var m := at + bend
			var b := at + dir * size * 0.5
			data["points"] = [[a.x, a.y], [m.x, m.y], [b.x, b.y]]
			var w := float(data.get("width", 24.0))
			# Round the straight line end to end: the bend, and side stubs
			# reaching up to 1.7 widths from the axis.
			p.a = a
			p.b = b
			p.reach = w * 1.7 + bend.length()
			p.block = p.reach
		_:
			if e.has("kind"):
				data["kind"] = e["kind"]
			data["center"] = [at.x, at.y]
			data["radius"] = size
			var kind := str(e.get("kind", "grass"))
			var def: Dictionary = PlantProp.DEFAULTS.get(kind, PlantProp.DEFAULTS["rosette"])
			var stem := float(data.get("stem", def["stem"]))
			data["stem"] = stem
			p.reach = size
			p.block = stem
	p.data = data
	return p

## True if a candidate stays inside the world and out of every zone: a plant
## whose stem would block in a reserve zone is cut to its canopy there.
static func _fits(world: World, world_rect: Rect2, zones: Array[Zone], p: Placed) -> bool:
	var blocks := p.block > 0.0
	for end: Vector2 in [p.a, p.b]:
		if blocks and not world_rect.grow(-BLOCK_GAP - p.block).has_point(end):
			return false
		if not world_rect.has_point(end) or world.is_blocked(end):
			return false
	for z in zones:
		var d := p.zone_distance(z)
		if z.hard and d < p.reach:
			return false
		if not z.hard and blocks and d < p.block:
			if p.data["type"] != "plant" and p.data["type"] != "grass":
				return false
			p.data["stem"] = 0.0
			p.block = 0.0
			blocks = false
	if blocks:
		# Not on or against walls, water or other props' footprints.
		var cells := world.cells_in_circle(p.at, p.block + BLOCK_GAP) if p.a == p.b \
				else world.cells_in_polyline(PackedVector2Array([p.a, p.b]), (p.block + BLOCK_GAP) * 2.0)
		for c in cells:
			if world.obstacles[c] != World.Cell.FREE:
				return false
	return true

static func _spaced(buckets: Dictionary[Vector2i, Array], p: Placed, max_extent: float) -> bool:
	var look := int(ceil((p.extent() + max_extent) / BUCKET))
	var home := Vector2i((p.at / BUCKET).floor())
	for by in range(home.y - look, home.y + look + 1):
		for bx in range(home.x - look, home.x + look + 1):
			for q: Placed in buckets.get(Vector2i(bx, by), []):
				var d := p.core_distance(q)
				if d < p.reach * p.spacing + q.reach * q.spacing:
					return false
				if p.block > 0.0 and q.block > 0.0 and d < p.block + q.block + BLOCK_GAP:
					return false
	return true

# --- Keep-clear ---------------------------------------------------------------------------

## The zones a scatter keeps clear (see the class comment). "avoid" picks
## which of "nests", "food" and "portals" are kept clear (all by default).
static func keep_clear_zones(sim: Simulation, s: Dictionary, margin: float) -> Array[Zone]:
	var zones: Array[Zone] = []
	var avoid: Array = s.get("avoid", ["nests", "food", "portals"])
	var reserve := float(s.get("reserve", 1.0))
	if avoid.has("nests"):
		for colony in sim.colonies:
			_nest_zones(sim, colony.nest, margin, reserve, zones)
	if avoid.has("food"):
		for src in sim.food_sources:
			var bound := src.sense_bound()
			var r := bound - src.sense_radius - 1.0 if is_finite(bound) else 20.0
			zones.append(_circle(src.position, maxf(r, 8.0) + margin, true))
	if avoid.has("portals"):
		for portal in sim.portals:
			if portal.layer_a == 0:
				zones.append(_circle(portal.pos_a, portal.radius * 3.0 + margin, true))
			if portal.layer_b == 0:
				zones.append(_circle(portal.pos_b, portal.radius * 3.0 + margin, true))
	for ob: Dictionary in s.get("clear", []):
		zones.append(_shape_zone(ob))
	return zones

static func _nest_zones(sim: Simulation, nest: NestType, margin: float, reserve: float, zones: Array[Zone]) -> void:
	var style := nest.entrance_style
	var main := nest.entrance_position()
	# Drawn entrances at full size (the main one widens to 120% of the radius).
	zones.append(_circle(main, nest.radius * 1.2 * NestType.ENTRANCE_REACH.get(style, 2.4) + margin, true))
	for s in nest.entrance_sites():
		zones.append(_circle(s.position, s.reach(style) + margin, true))
	for p in nest.extra_portals:
		zones.append(_circle(p.pos_a, nest.radius * NestType.ENTRANCE_REACH.get(style, 2.4) + margin, true))
	if nest.clear_radius > 0.0:
		# The cleared disc keeps plants out; blocking props out of it too.
		zones.append(_circle(main, nest.clear_radius + margin, true))
	if nest.underground_layer >= 0:
		for e in nest.extra_portals.size() + 1:
			zones.append(_circle(nest.spoil_position_of(e), SPOIL_ROOM, true))
	if nest.fixed_dump:
		zones.append(_circle(nest.position + nest.dump_offset, DUMP_ROOM + margin, true))
	# Room for what the nest will add later: middens and extra entrances.
	var room := 0.0
	if not nest.fixed_dump:
		var far := nest.midden_distance.y
		if nest.midden_style == "ring" and nest.clear_radius > 0.0:
			far = nest.clear_radius + 6.0
		room = far + MIDDEN_ROOM
	if nest is ColonyNest and not (nest as ColonyNest).entrance_steps.is_empty():
		var cn := nest as ColonyNest
		room = maxf(room, cn.entrance_spacing * 2.2 + nest.radius * NestType.ENTRANCE_REACH.get(style, 2.4))
	if room > 0.0 and reserve > 0.0:
		zones.append(_circle(main, room * reserve, false))

static func _circle(at: Vector2, r: float, hard: bool) -> Zone:
	var z := Zone.new()
	z.shape = "circle"
	z.center = at
	z.radius = r
	z.hard = hard
	return z

## A zone from an obstacle-style shape (polyline = a path of "width").
static func _shape_zone(ob: Dictionary) -> Zone:
	var z := Zone.new()
	z.shape = str(ob.get("shape", "polyline"))
	match z.shape:
		"circle":
			z.center = ScenarioEvents.vec2(ob["center"])
			z.radius = float(ob["radius"])
		"rect":
			z.rect = ScenarioEvents.rect2(ob["rect"])
		_:
			z.points = PropType.params_points(ob["points"])
			z.width = float(ob.get("width", 40.0))
	z.hard = not bool(ob.get("reserve", false))
	return z

# --- Connectivity -------------------------------------------------------------------------

## Drops the newest blocking prop bordering a nest's reachable area while one
## of its targets (reachable before the scatter) is cut off. Returns how many.
static func _keep_connected(sim: Simulation, placed: Array[Placed], baseline: Array[Dictionary], result: Result) -> int:
	var dropped := 0
	var any_blocking := false
	for p in placed:
		any_blocking = any_blocking or p.block > 0.0
	if not any_blocking:
		return 0
	while true:
		var now := _reachability(sim, placed)
		var culprit: Placed = null
		for n in now.size():
			if _all_reached(baseline[n], now[n]):
				continue
			var seen: PackedByteArray = now[n]["seen"]
			for i in range(placed.size() - 1, -1, -1):
				var p := placed[i]
				if p.block > 0.0 and _borders(sim.world, p.prop.cells, seen):
					culprit = p
					break
			if culprit != null:
				break
		if culprit == null:
			return dropped
		dropped += 1
		sim.scenery.remove(culprit.prop)
		result.placed.erase(culprit.prop)
		culprit.block = 0.0
		if culprit.data["type"] == "plant" or culprit.data["type"] == "grass":
			culprit.data["stem"] = 0.0
			culprit.prop = sim.scenery.add(culprit.data)
			result.placed.append(culprit.prop)
		else:
			placed.erase(culprit)
	return dropped

static func _all_reached(before: Dictionary, now: Dictionary) -> bool:
	var had: PackedByteArray = before["targets"]
	var has: PackedByteArray = now["targets"]
	for t in had.size():
		if had[t] == 1 and has[t] == 0:
			return false
	return true

## Per colony: the cells reachable from its main entrance ("seen") and which
## targets were reached ("targets": each usable food source, then the world
## edge). Cells next to a scattered prop's footprint count as blocked, so a
## gap between two props must be wide enough for an ant.
static func _reachability(sim: Simulation, placed: Array[Placed]) -> Array[Dictionary]:
	var world := sim.world
	var w := world.width
	var h := world.height
	var blocked := PackedByteArray()
	blocked.resize(w * h)
	for c in w * h:
		blocked[c] = 1 if world.obstacles[c] != World.Cell.FREE else 0
	for p in placed:
		if p.block <= 0.0 or p.prop == null:
			continue
		for c in p.prop.cells:
			var cx := c % w
			@warning_ignore("integer_division")
			var cy := c / w
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var x := cx + dx
					var y := cy + dy
					if x >= 0 and y >= 0 and x < w and y < h:
						blocked[y * w + x] = 1
	var out: Array[Dictionary] = []
	for colony in sim.colonies:
		var seen := _flood(world, blocked, _free_cell_near(world, blocked, colony.nest.entrance_position()))
		var targets := PackedByteArray()
		for src in sim.food_sources:
			if not colony.food_types.has(src.type_id):
				continue
			var c := _free_cell_near(world, blocked, src.nearest_access_point(colony.nest.entrance_position()))
			targets.append(1 if c >= 0 and seen[c] == 1 else 0)
		var edge := 0
		for x in w:
			if seen[x] == 1 or seen[(h - 1) * w + x] == 1:
				edge = 1
				break
		if edge == 0:
			for y in h:
				if seen[y * w] == 1 or seen[y * w + w - 1] == 1:
					edge = 1
					break
		targets.append(edge)
		out.append({"seen": seen, "targets": targets})
	return out

## The cell at `at`, or the nearest passable one within 3 cells (-1 if none).
static func _free_cell_near(world: World, blocked: PackedByteArray, at: Vector2) -> int:
	var c := world.cell_at(at)
	if c >= 0 and blocked[c] == 0:
		return c
	var best := -1
	var best_d := INF
	for n in world.cells_in_circle(at, world.cell_size * 3.0):
		if blocked[n] == 0:
			@warning_ignore("integer_division")
			var cp := Vector2((n % world.width + 0.5) * world.cell_size, (n / world.width + 0.5) * world.cell_size)
			var d := cp.distance_squared_to(at)
			if d < best_d:
				best_d = d
				best = n
	return best

## 4-connected flood fill of unblocked cells from `start`.
static func _flood(world: World, blocked: PackedByteArray, start: int) -> PackedByteArray:
	var w := world.width
	var seen := PackedByteArray()
	seen.resize(w * world.height)
	if start < 0:
		return seen
	var queue := PackedInt32Array([start])
	seen[start] = 1
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var x := c % w
		for n: int in [c - w, c + w, c - 1 if x > 0 else -1, c + 1 if x < w - 1 else -1]:
			if n >= 0 and n < seen.size() and seen[n] == 0 and blocked[n] == 0:
				seen[n] = 1
				queue.append(n)
	return seen

## True if any of `cells` has a neighbour within two cells in `seen`.
static func _borders(world: World, cells: PackedInt32Array, seen: PackedByteArray) -> bool:
	var w := world.width
	var h := world.height
	for c in cells:
		var cx := c % w
		@warning_ignore("integer_division")
		var cy := c / w
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x := cx + dx
				var y := cy + dy
				if x >= 0 and y >= 0 and x < w and y < h and seen[y * w + x] == 1:
					return true
	return false
