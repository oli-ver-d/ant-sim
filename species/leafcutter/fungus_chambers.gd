class_name FungusChambers
extends RefCounted
## The chambers and tunnels of a leafcutter nest that digs its own
## underground (see FungusNest, nest_params "underground"): the royal chamber
## in the middle, where the queen lives in a niche and the founding garden
## grows, and garden chambers the colony digs as it grows.
##
## Architecture (all placed from the scenario seed with this object's own
## RNG, so the simulation's random stream is untouched):
##   - galleries (Gallery), a hierarchy of tunnels: main galleries (wide)
##     running out from the royal chamber, secondary tunnels branching off
##     galleries, narrow capillaries from a gallery to a single chamber,
##     short dead-end stubs (some later become chamber sites), and
##     cross-links between chambers that are near each other but far apart
##     along the tunnels, so the nest has loops and several routes. Widths
##     taper along each tunnel. Every tunnel is routed through the soil
##     (SimLayer.route: around stones, clear of other cavities, winding).
##   - chambers hang off the galleries like grapes on a stem: each sits at a
##     junction along a gallery (slots spaced along it, on either side), or
##     at the end of a stub, joined to it by a capillary. A chamber is a
##     slightly flattened blob of 2-5 overlapping lobes (DigShape.ellipses),
##     some with a side alcove (a niche where brood is kept). Later chambers
##     skew larger. The royal chamber is larger and bean-shaped, with a niche
##     for the queen and her retinue and an alcove for pupae.
##   - digging follows need (FungusNest plans a chamber when the gardens
##     fill up): plan_chamber() first plans a gallery when few free sites are
##     left, so galleries are dug ahead of the chambers that will hang off
##     them, and the nest spreads outward into a web.
##
## A chamber is a shape, so everything that needs a place in one asks here:
## chamber_at() (a cell -> chamber map), contains(), and the sampling helpers
## random_point(), floor_point() (away from the walls), rim_point() and
## point_in() (along a ray from the centre), which work for any shape.
## Stones inside a chamber's outline are dug out with it (World.soften), so
## chamber floors are clear; tunnels go around them.

enum Kind { ROYAL, GARDEN }
enum Level { MAIN, SECONDARY, CAPILLARY, STUB, LINK }

class Chamber:
	var index: int
	var kind: int
	## A point well inside (the main lobe's centre): nav target and ray origin.
	var centre: Vector2
	## Radius of a circle of the same area.
	var radius: float
	## The chamber it was planned from (the royal chamber for all but links).
	var parent: int = -1
	## Plan jobs (-1: carved from the start).
	var tunnel_job: int = -1
	var job: int = -1
	var dug: bool = false
	## Nav field toward the centre (on the nest's layer).
	var nav_field: int = -1
	## Where the capillary from its gallery enters.
	var door: Vector2
	## The shape: lobes (DigShape.ellipses, 5 floats each).
	var lobes: PackedFloat32Array = []
	## The shape's cells on the nest layer (dug or still to dig).
	var cells: PackedInt32Array = []
	## The capillary leading to it (points).
	var tunnel: PackedVector2Array = []
	## Steps from the edge to its deepest cell.
	var depth_max: int = 0
	## Distance from the centre to its furthest cell.
	var reach_max: float = 0.0
	## Centres and radii of its alcoves (niches); the royal chamber's first is
	## the queen's, its second the pupae's.
	var alcoves: PackedVector2Array = []
	var alcove_radii: PackedFloat32Array = []
	## The gallery its capillary leaves from (-1: none), and how far along it.
	var gallery: int = -1
	var attach_s: float = 0.0

class Gallery:
	var index: int
	var level: int
	var points: PackedVector2Array = []
	var radii: PackedFloat32Array = []
	## Arc length at each point.
	var along: PackedFloat32Array = []
	## The gallery it branches off (-1: the royal chamber) and where along it.
	var parent: int = -1
	var attach_s: float = 0.0
	var job: int = -1
	## Junction slots taken (slot * 2 + side).
	var used: Dictionary[int, bool] = {}

	func length() -> float:
		return along[along.size() - 1]

	## Point at arc length s.
	func at(s: float) -> Vector2:
		for k in range(1, along.size()):
			if s <= along[k] or k == along.size() - 1:
				var t := clampf((s - along[k - 1]) / maxf(along[k] - along[k - 1], 1e-6), 0.0, 1.0)
				return points[k - 1].lerp(points[k], t)
		return points[0]

	## Unit direction of travel at arc length s.
	func tangent(s: float) -> Vector2:
		var a := at(maxf(0.0, s - 4.0))
		var b := at(minf(length(), s + 4.0))
		return (b - a).normalized() if a != b else Vector2.RIGHT

var list: Array[Chamber] = []
var galleries: Array[Gallery] = []
## Cross-links planned so far, as chamber index pairs.
var links: Array[Vector2i] = []
## Bottom of the entrance shaft (the portal's underground end).
var shaft: Vector2
var layer_size: Vector2
## Chamber radius range for new garden chambers.
var min_radius: float = 38.0
var max_radius: float = 62.0
## The secondary tunnel radius; mains are MAIN_WIDTH times it, capillaries
## CAPILLARY_WIDTH times.
var tunnel_radius: float = 7.0
const MAIN_WIDTH := 1.35
const CAPILLARY_WIDTH := 0.72
## Soil kept between a new chamber and any other cavity.
var min_gap: float = 16.0
## Spacing of junction slots along a gallery.
var slot_spacing: float = 44.0
## Main galleries out of the royal chamber, at most.
var max_mains: int = 3
## Chambers before cross-links are planned.
var links_after: int = 5
## Roughness of chamber outlines (DigShape), world units.
var rough: float = 0.0
var rough_seed: int = 0
var _rng := RandomNumberGenerator.new()
## The nest's layer (set by attach()).
var world: World
var layer: SimLayer
## Per cell of the nest layer: the chamber it belongs to, or -1.
var _owner: PackedInt32Array = []
## Per cell: steps (cells) to the chamber's edge, 1 at the edge (0 outside).
var _depth: PackedByteArray = []

func setup(size: Vector2, seed_value: int, params: Dictionary) -> void:
	layer_size = size
	_rng.seed = seed_value * 7919 + 101
	rough_seed = seed_value * 13 + 5
	min_radius = float(params.get("chamber_min_radius", min_radius))
	max_radius = float(params.get("chamber_max_radius", max_radius))
	tunnel_radius = float(params.get("tunnel_radius", tunnel_radius))
	rough = float(params.get("overdig", rough))
	var royal := Chamber.new()
	royal.index = 0
	royal.kind = Kind.ROYAL
	royal.centre = ScenarioEvents.vec2(params["royal"]) if params.has("royal") else size * 0.5
	var r := float(params.get("royal_radius", 36.0))
	royal.radius = r
	royal.dug = true
	# The shaft comes down a little way from the royal chamber, up and to one side.
	var a := _rng.randf_range(-2.4, -0.7)
	shaft = ScenarioEvents.vec2(params["shaft"]) if params.has("shaft") else \
			royal.centre + Vector2.from_angle(a) * (r * 1.2 + float(params.get("shaft_distance", 46.0)))
	# Bean-shaped, flattened across the shaft's direction: a broad main lobe,
	# two side lobes, the queen's niche and an alcove for pupae.
	var across := (shaft - royal.centre).angle() + PI * 0.5
	var ax := Vector2.from_angle(across)
	var c := royal.centre
	royal.lobes = PackedFloat32Array([c.x, c.y, r * 1.1, r * 0.78, across])
	for side: float in [-1.0, 1.0]:
		var p := c + ax * side * r * 0.62 - ax.orthogonal() * r * 0.1
		royal.lobes.append_array([p.x, p.y, r * 0.62, r * 0.55, across + side * 0.5])
	# The queen's niche off the far side (away from the shaft), pupae to one end.
	var away := (c - shaft).normalized()
	var niche := c + away.rotated(0.45) * r * 0.8
	var pupae := c + ax * r * 1.22 + away * r * 0.12
	for n: Vector3 in [Vector3(niche.x, niche.y, r * 0.52), Vector3(pupae.x, pupae.y, r * 0.36)]:
		royal.lobes.append_array([n.x, n.y, n.z, n.z * 0.85, across])
		royal.alcoves.append(Vector2(n.x, n.y))
		royal.alcove_radii.append(n.z * 0.85)
	royal.door = royal.centre
	list.append(royal)

## The carve entry (NestType "carve") that digs the royal chamber out.
func royal_carve() -> Dictionary:
	return {"lobes": Array(royal().lobes), "rough": rough, "seed": rough_seed}

## Binds the nest's layer (once it exists) and maps the chambers so far.
func attach(on_layer: SimLayer) -> void:
	layer = on_layer
	world = on_layer.world
	_owner.resize(world.width * world.height)
	_owner.fill(-1)
	_depth.resize(world.width * world.height)
	for c in list:
		_map(c)

func royal() -> Chamber:
	return list[0]

func count() -> int:
	return list.size()

## Chambers dug out so far.
func dug_count() -> int:
	var n := 0
	for c in list:
		if c.dug:
			n += 1
	return n

## True if `at` is in one of chamber k's alcoves.
func in_alcove(k: int, at: Vector2) -> bool:
	var c := list[k]
	for a in c.alcoves.size():
		if at.distance_to(c.alcoves[a]) <= c.alcove_radii[a]:
			return true
	return false

# --- Where things are ------------------------------------------------------------------

## The chamber whose shape contains `at` (by its cell), or -1.
func chamber_at(at: Vector2) -> int:
	var cell := world.cell_at(at)
	return _owner[cell] if cell >= 0 else -1

func contains(k: int, at: Vector2) -> bool:
	return chamber_at(at) == k

## Steps (cells) from `at` to the edge of its chamber (1 at the edge), 0
## outside chambers.
func depth_at(at: Vector2) -> int:
	var cell := world.cell_at(at)
	return _depth[cell] if cell >= 0 else 0

## A random point on an open cell of chamber k, at least `min_depth` cells in
## from its edge if possible (the centre if nothing fits).
func random_point(k: int, rng: RandomNumberGenerator, min_depth: int = 1) -> Vector2:
	var c := list[k]
	if c.cells.is_empty():
		return c.centre
	for t in 24:
		var cell := c.cells[rng.randi() % c.cells.size()]
		if _depth[cell] >= min_depth and world.obstacles[cell] == World.Cell.FREE:
			return world.cell_center(cell) + Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * world.cell_size * 0.8
	return c.centre

## A point on the floor of chamber k away from the walls (the deepest part).
func floor_point(k: int, rng: RandomNumberGenerator) -> Vector2:
	@warning_ignore("integer_division")
	return random_point(k, rng, maxi(1, (max_depth(k) + 1) / 2))

## A point by the wall of chamber k (its outer cells).
func rim_point(k: int, rng: RandomNumberGenerator) -> Vector2:
	var c := list[k]
	for t in 24:
		var cell := c.cells[rng.randi() % c.cells.size()]
		if _depth[cell] >= 1 and _depth[cell] <= 2 and world.obstacles[cell] == World.Cell.FREE:
			return world.cell_center(cell)
	return c.centre

## A point in chamber `k`, `u` (0-1) of the way out from its centre to its
## edge along `angle`.
func point_in(k: int, angle: float, u: float) -> Vector2:
	var c := list[k]
	return c.centre + Vector2.from_angle(angle) * reach(k, angle) * u

## Distance from chamber k's centre to its edge along `angle` (marching over
## its cells in half-cell steps).
func reach(k: int, angle: float) -> float:
	var c := list[k]
	var dir := Vector2.from_angle(angle)
	var step := world.cell_size * 0.5
	var d := 0.0
	while d < 400.0:
		var cell := world.cell_at(c.centre + dir * (d + step))
		if cell < 0 or _owner[cell] != k:
			break
		d += step
	return d

## Deepest cell of chamber k (steps from its edge).
func max_depth(k: int) -> int:
	return list[k].depth_max

## A chamber's shape (its lobes with the rough outline).
func shape_of(ch: Chamber) -> DigShape:
	return DigShape.ellipses(world, ch.lobes, ch.door, rough, rough_seed)

## Records chamber c's cells in the cell map and their depths.
func _map(c: Chamber) -> void:
	var shape := shape_of(c)
	c.cells = PackedInt32Array()
	for cell in shape.cells:
		if _owner[cell] < 0:
			# Chambers get a clear floor: stones in the way are dug out too.
			if world.obstacles[cell] == World.Cell.WALL:
				world.soften(cell, 2.5)
			_owner[cell] = c.index
			c.cells.append(cell)
	c.radius = sqrt(c.cells.size() / PI) * world.cell_size
	# Depth: a breadth-first walk in from the edge cells.
	var queue: PackedInt32Array = []
	for cell in c.cells:
		_depth[cell] = 0
	for cell in c.cells:
		if not _inner(cell, c.index):
			_depth[cell] = 1
			queue.append(cell)
	var head := 0
	var w := world.width
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for nb: int in [cell - 1, cell + 1, cell - w, cell + w]:
			if nb >= 0 and nb < _owner.size() and _owner[nb] == c.index and _depth[nb] == 0:
				_depth[nb] = mini(255, _depth[cell] + 1)
				queue.append(nb)
	c.depth_max = 0
	c.reach_max = 0.0
	for cell in c.cells:
		c.depth_max = maxi(c.depth_max, _depth[cell])
		c.reach_max = maxf(c.reach_max, world.cell_center(cell).distance_to(c.centre))

## True if all four neighbours of `cell` belong to chamber k.
func _inner(cell: int, k: int) -> bool:
	var w := world.width
	var cx := cell % w
	return cx > 0 and cx < w - 1 and cell >= w and cell < _owner.size() - w \
			and _owner[cell - 1] == k and _owner[cell + 1] == k and _owner[cell - w] == k and _owner[cell + w] == k


# --- Planning ----------------------------------------------------------------------

## Plans the next garden chamber and returns it, or null if nothing fits:
## first a gallery if few free sites are left along the galleries, then the
## chamber at a free junction (a capillary from the gallery, then the
## chamber), and now and then a dead-end stub or a cross-link. `priority`
## orders it among other digging (galleries before the chamber, stubs and
## links after). With `carve` everything is dug out at once (a nest that
## starts established).
func plan_chamber(plan: ExcavationPlan, priority: float, carve: bool = false) -> Chamber:
	if galleries.is_empty() or _free_sites() < 3:
		_plan_gallery(plan, priority - 0.6, carve)
	var ch := _site(plan)
	if ch == null:
		_plan_gallery(plan, priority - 0.6, carve)
		ch = _site(plan)
	if ch == null:
		return null
	_add_chamber(ch, plan, priority, carve)
	if _rng.randf() < 0.3:
		_plan_stub(plan, priority + 4.0, carve)
	if list.size() > links_after and _rng.randf() < 0.5:
		_plan_link(plan, priority + 1.0, carve)
	return ch

## Junction slot positions (arc lengths) along gallery g.
func _slots(g: Gallery) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var s := 26.0
	while s < g.length() - 10.0:
		out.append(s)
		s += slot_spacing
	return out

## Free junctions (slot sides, stub ends) left on the galleries.
func _free_sites() -> int:
	var n := 0
	for g in galleries:
		if g.level == Level.MAIN or g.level == Level.SECONDARY:
			n += _slots(g).size() * 2 - g.used.size()
		elif g.level == Level.STUB and not g.used.has(-1):
			n += 1
	return n

## A garden chamber at a free junction that fits, or null. Candidates are
## tried in a seeded order: stub ends first, then slots on the galleries
## further out; ones that don't fit are marked used.
func _site(plan: ExcavationPlan) -> Chamber:
	var cands: Array[Vector4] = []  # (gallery, slot key, s, side), sorted by score in keys
	var keys: PackedFloat32Array = []
	var centre := royal().centre
	for g in galleries:
		if g.level == Level.STUB:
			if not g.used.has(-1):
				cands.append(Vector4(g.index, -1, g.length(), 0))
				keys.append(_rng.randf() + 1.0)
			continue
		if g.level != Level.MAIN and g.level != Level.SECONDARY:
			continue
		var slots := _slots(g)
		for k in slots.size():
			for side: int in [-1, 1]:
				var key := k * 2 + (1 if side > 0 else 0)
				if g.used.has(key):
					continue
				var out := g.at(slots[k]).distance_to(centre) / 400.0
				cands.append(Vector4(g.index, key, slots[k], side))
				keys.append(_rng.randf() - out * 0.8)
	var order: Array[int] = []
	for k in cands.size():
		order.append(k)
	order.sort_custom(func(a: int, b: int) -> bool: return keys[a] > keys[b])
	var tries := 0
	for k in order:
		if tries >= 24:
			break
		tries += 1
		var cand := cands[k]
		var g := galleries[int(cand.x)]
		var ch := _chamber_at_junction(g, cand.z, int(cand.w), plan)
		g.used[int(cand.y)] = true
		if ch != null:
			return ch
	return null

## A chamber off gallery g at arc length s on `side` (0: at the end, a
## stub's), if it fits.
func _chamber_at_junction(g: Gallery, s: float, side: int, plan: ExcavationPlan) -> Chamber:
	var n := list.size()
	var grown := clampf((n - 1) / 8.0, 0.0, 1.0)
	var r := _rng.randf_range(min_radius * (0.7 + 0.3 * grown), lerpf(min_radius, max_radius, grown))
	var junction := g.at(s)
	var t := g.tangent(s)
	var normal := t if side == 0 else t.orthogonal() * side
	var reach_out := _rng.randf_range(4.0, 9.0) if side == 0 else _rng.randf_range(g.radii[0] + 8.0, g.radii[0] + 26.0)
	var door := junction + normal * reach_out
	var dir := normal.rotated(_rng.randf_range(-0.35, 0.35))
	var ch := Chamber.new()
	ch.index = n
	ch.kind = Kind.GARDEN
	ch.parent = 0
	ch.centre = door + dir * r * 0.9
	_garden_lobes(ch, r, dir.angle())
	# Move it so the door sits just outside its outline.
	for attempt in 2:
		var d := DigShape.ellipses_distance(ch.lobes, door)
		_shift(ch, dir * (3.0 - d))
	ch.door = door
	ch.gallery = g.index
	ch.attach_s = s
	ch.radius = r
	if not _fits(ch, junction, plan):
		return null
	return ch

## Gives chamber ch (at ch.centre, entered from direction `facing`) its
## lobes: a flattened main lobe across the way in, 1-4 overlapping lobes,
## and sometimes an alcove on the far side.
func _garden_lobes(ch: Chamber, r: float, facing: float) -> void:
	var c := ch.centre
	var aspect := _rng.randf_range(1.1, 1.5)
	var turn := facing + PI * 0.5 + _rng.randf_range(-0.5, 0.5)
	ch.lobes = PackedFloat32Array([c.x, c.y, r * aspect * 0.8, r / aspect * 0.95, turn])
	for e in _rng.randi_range(1, 4):
		var phi := turn + (PI if e % 2 == 1 else 0.0) + _rng.randf_range(-0.9, 0.9)
		var p := c + Vector2.from_angle(phi) * r * _rng.randf_range(0.35, 0.62)
		var rr := r * _rng.randf_range(0.38, 0.6)
		ch.lobes.append_array([p.x, p.y, rr, rr * _rng.randf_range(0.65, 1.0), phi + _rng.randf_range(-0.6, 0.6)])
	if _rng.randf() < 0.55:
		var phi := facing + _rng.randf_range(-1.4, 1.4)
		var ar := _rng.randf_range(9.0, 12.5)
		# Out to the edge along phi, then half the alcove beyond it.
		var edge := 0.0
		while DigShape.ellipses_distance(ch.lobes, c + Vector2.from_angle(phi) * edge) < 0.0 and edge < r * 2.0:
			edge += 2.0
		var p := c + Vector2.from_angle(phi) * (edge + ar * 0.35)
		ch.lobes.append_array([p.x, p.y, ar, ar * 0.85, phi])
		ch.alcoves.append(p)
		ch.alcove_radii.append(ar * 0.85)

func _shift(ch: Chamber, by: Vector2) -> void:
	ch.centre += by
	for k in range(0, ch.lobes.size(), 5):
		ch.lobes[k] += by.x
		ch.lobes[k + 1] += by.y
	for a in ch.alcoves.size():
		ch.alcoves[a] += by

## True if chamber ch fits: inside the layer, away from the shaft, and
## min_gap of soil between it and every other cavity, planned digging or
## chamber (except along the way in from `junction`), few stones.
func _fits(ch: Chamber, junction: Vector2, plan: ExcavationPlan) -> bool:
	var grown := ch.lobes.duplicate()
	for k in range(0, grown.size(), 5):
		grown[k + 2] += min_gap
		grown[k + 3] += min_gap
	var shape := DigShape.ellipses(world, grown, ch.door)
	var bounds := Rect2(Vector2(shape.box.position) * world.cell_size, Vector2(shape.box.size) * world.cell_size)
	if not Rect2(Vector2.ZERO, layer_size).grow(-30.0).encloses(bounds):
		return false
	if ch.centre.distance_to(shaft) < ch.radius + 50.0:
		return false
	var planned := plan.planned_cells()
	var own := galleries[ch.gallery] if ch.gallery >= 0 else null
	var stones := 0
	for cell in shape.cells:
		var at := world.cell_center(cell)
		if Geometry2D.get_closest_point_to_segment(at, junction, ch.door).distance_to(at) < min_gap:
			continue
		if _owner[cell] >= 0 or world.obstacles[cell] == World.Cell.FREE or planned.has(cell):
			# Its own gallery may run closer: a thin wall of soil will do.
			if own == null or _polyline_distance(own.points, at) > own.radii[0] + rough + 3.0 \
					or DigShape.ellipses_distance(ch.lobes, at) < 5.0 + rough:
				return false
		if world.obstacles[cell] == World.Cell.WALL:
			stones += 1
	return stones <= shape.cells.size() * 0.06

static func _polyline_distance(pts: PackedVector2Array, at: Vector2) -> float:
	var best := INF
	for k in pts.size() - 1:
		best = minf(best, Geometry2D.get_closest_point_to_segment(at, pts[k], pts[k + 1]).distance_to(at))
	return best

## Plans (or carves) chamber ch and its capillary from its gallery.
func _add_chamber(ch: Chamber, plan: ExcavationPlan, priority: float, carve: bool) -> void:
	var g := galleries[ch.gallery]
	var from := g.at(ch.attach_s)
	var into := ch.door + (ch.centre - ch.door).normalized() * 6.0
	var pts := route_tunnel(from, into, plan)
	var w := tunnel_radius * CAPILLARY_WIDTH
	var radii := _taper(pts, w, w * 0.9)
	ch.tunnel = pts
	list.append(ch)
	_map(ch)
	if carve:
		world.carve_path(pts, radii, rough, rough_seed)
		world.carve_cells(ch.cells)
		ch.dug = true
	else:
		ch.tunnel_job = plan.add_path_job("tunnel%d" % ch.index, from, pts, radii, priority, 6).id
		# Room for more diggers in a bigger chamber.
		ch.job = plan.add_shape_job("chamber%d" % ch.index, into, DigShape.from_cells(world, ch.cells, ch.door),
				priority + 0.5, clampi(int(ch.radius / 3.0), 8, 20)).id
	ch.nav_field = plan.nav.set_target_point(StringName("chamber:%d" % ch.index), ch.centre)

## Radii along a path, tapering from w0 to w1 by arc length.
static func _taper(pts: PackedVector2Array, w0: float, w1: float) -> PackedFloat32Array:
	var total := maxf(Router.length_of(pts), 1e-6)
	var out := PackedFloat32Array()
	var s := 0.0
	for k in pts.size():
		if k > 0:
			s += pts[k - 1].distance_to(pts[k])
		out.append(lerpf(w0, w1, s / total))
	return out

## Adds a gallery along `pts` (branching off gallery `parent` at `s`, or the
## royal chamber) and plans or carves it.
func _add_gallery(level: int, pts: PackedVector2Array, radii: PackedFloat32Array, parent: int, s: float,
		plan: ExcavationPlan, priority: float, carve: bool) -> Gallery:
	var g := Gallery.new()
	g.index = galleries.size()
	g.level = level
	g.points = pts
	g.radii = radii
	g.parent = parent
	g.attach_s = s
	var total := 0.0
	for k in pts.size():
		if k > 0:
			total += pts[k - 1].distance_to(pts[k])
		g.along.append(total)
	galleries.append(g)
	if carve:
		world.carve_path(pts, radii, rough, rough_seed)
	else:
		g.job = plan.add_path_job("gallery%d" % g.index, pts[0], pts, radii, priority, 6).id
	return g

## Plans a gallery: a main one out of the royal chamber (up to max_mains,
## spread around it), else a secondary tunnel branching off a gallery,
## heading outward, or a gallery extended from its end. Null if none fits.
func _plan_gallery(plan: ExcavationPlan, priority: float, carve: bool) -> Gallery:
	var centre := royal().centre
	var mains := 0
	for g in galleries:
		if g.level == Level.MAIN and g.parent < 0:
			mains += 1
	for attempt in 16:
		var level := Level.SECONDARY
		var parent := -1
		var s := 0.0
		var start: Vector2
		var dir: Vector2
		var length := 0.0
		if mains < max_mains and (mains == 0 or _rng.randf() < 0.5 or galleries.size() < 2):
			# A main gallery, in the direction furthest from the others and the shaft.
			level = Level.MAIN
			var best := 0.0
			var best_gap := -1.0
			for k in 10:
				var a := _rng.randf() * TAU
				var gap := absf(angle_difference(a, (shaft - centre).angle()))
				for g in galleries:
					if g.level == Level.MAIN and g.parent < 0:
						gap = minf(gap, absf(angle_difference(a, (g.points[g.points.size() - 1] - centre).angle())))
				if gap > best_gap:
					best_gap = gap
					best = a
			start = point_in(0, best, 0.9)
			dir = Vector2.from_angle(best)
			length = _rng.randf_range(150.0, 230.0)
		else:
			var g := _pick_parent_gallery()
			if g == null:
				continue
			parent = g.index
			var out := (g.at(g.length()) - centre).normalized()
			if _rng.randf() < 0.3:
				# Extend it from its end.
				level = g.level
				s = g.length()
				start = g.at(s)
				dir = (g.tangent(s) + out * 0.3).normalized().rotated(_rng.randf_range(-0.45, 0.45))
				length = _rng.randf_range(90.0, 150.0)
			else:
				s = _rng.randf_range(30.0, maxf(31.0, g.length() - 15.0))
				start = g.at(s)
				var t := g.tangent(s)
				var side := 1.0 if t.orthogonal().dot(start - centre) > 0.0 else -1.0
				if _rng.randf() < 0.25:
					side = -side
				dir = (t.rotated(side * _rng.randf_range(0.6, 1.25)) + (start - centre).normalized() * 0.35).normalized()
				length = _rng.randf_range(90.0, 160.0)
		var end := start + dir * length
		var bounds := Rect2(Vector2.ZERO, layer_size).grow(-70.0)
		while not bounds.has_point(end) and length > 50.0:
			length -= 10.0
			end = start + dir * length
		if length <= 50.0 or not _soil_around(end, 16.0, plan):
			continue
		var pts := route_tunnel(start, end, plan)
		if pts.size() < 2 or Router.length_of(pts) > length * 1.8:
			continue
		var w := tunnel_radius * (MAIN_WIDTH if level == Level.MAIN else 1.0)
		if parent >= 0:
			w = minf(w, galleries[parent].radii[galleries[parent].radii.size() - 1] * (1.0 if s >= galleries[parent].length() else 0.95))
		return _add_gallery(level, pts, _taper(pts, w, w * 0.82), parent, s, plan, priority, carve)
	return null

## A gallery to branch off: mains and secondaries, the ones reaching further
## out and more recent likelier.
func _pick_parent_gallery() -> Gallery:
	var best: Gallery = null
	var best_key := -INF
	for g in galleries:
		if g.level != Level.MAIN and g.level != Level.SECONDARY:
			continue
		# Spread the branching: galleries with fewer branches yet are likelier.
		var branches := 0
		for h in galleries:
			if h.parent == g.index:
				branches += 1
		var key := _rng.randf() - g.at(g.length() * 0.5).distance_to(royal().centre) / 600.0 - branches * 0.25
		if key > best_key:
			best_key = key
			best = g
	return best

## True if everything within `r` of `at` is soil nobody plans to dig.
func _soil_around(at: Vector2, r: float, plan: ExcavationPlan) -> bool:
	var planned := plan.planned_cells()
	for cell in world.cells_in_segment(at, at, r):
		if world.obstacles[cell] == World.Cell.FREE or planned.has(cell) or _owner[cell] >= 0:
			return false
	return true

## A short dead-end stub off a gallery (a later chamber site, maybe).
func _plan_stub(plan: ExcavationPlan, priority: float, carve: bool) -> void:
	var g := _pick_parent_gallery()
	if g == null:
		return
	for attempt in 6:
		var s := _rng.randf_range(20.0, maxf(21.0, g.length() - 10.0))
		var start := g.at(s)
		var dir := g.tangent(s).orthogonal() * (1.0 if _rng.randf() < 0.5 else -1.0)
		var end := start + dir.rotated(_rng.randf_range(-0.4, 0.4)) * _rng.randf_range(24.0, 42.0)
		if not _soil_around(end, 10.0, plan):
			continue
		var pts := route_tunnel(start, end, plan)
		if pts.size() < 2:
			continue
		var w := tunnel_radius * CAPILLARY_WIDTH
		_add_gallery(Level.STUB, pts, _taper(pts, w, w * 0.7), g.index, s, plan, priority, carve)
		return

## A cross-link between two chambers near each other but far apart along the
## tunnels (at least 2.5 times), so the nest gets a loop.
func _plan_link(plan: ExcavationPlan, priority: float, carve: bool) -> void:
	var best := Vector2i(-1, -1)
	var best_score := 0.0
	for a in range(1, list.size()):
		for b in range(a + 1, list.size()):
			var ca := list[a]
			var cb := list[b]
			if ca.gallery < 0 or cb.gallery < 0 or links.has(Vector2i(a, b)):
				continue
			var d := ca.centre.distance_to(cb.centre)
			var gap := d - ca.radius - cb.radius
			if gap < 12.0 or gap > 120.0:
				continue
			var tree := _tree_distance(ca.gallery, ca.attach_s, cb.gallery, cb.attach_s) + ca.radius + cb.radius
			var score := tree / d
			if score > 2.5 and score > best_score:
				best_score = score
				best = Vector2i(a, b)
	if best.x < 0:
		return
	var ca := list[best.x]
	var cb := list[best.y]
	var from := point_in(best.x, (cb.centre - ca.centre).angle(), 0.8)
	var to := point_in(best.y, (ca.centre - cb.centre).angle(), 0.8)
	var pts := route_tunnel(from, to, plan)
	links.append(best)
	if pts.size() < 2 or Router.length_of(pts) > from.distance_to(to) * 1.7:
		return
	var w := tunnel_radius * 0.85
	_add_gallery(Level.LINK, pts, _taper(pts, w, w), -1, 0.0, plan, priority, carve)

## Walking distance along the tunnel tree between (gallery a at sa) and
## (gallery b at sb), through the royal chamber at worst.
func _tree_distance(a: int, sa: float, b: int, sb: float) -> float:
	var ca := _chain(a, sa)
	var cb := _chain(b, sb)
	for x in ca:
		for y in cb:
			if int(x.x) == int(y.x):
				return x.z + y.z + absf(x.y - y.y)
	return INF

## From (gallery g at s) up to the royal chamber: (gallery, s, distance so far).
func _chain(g: int, s: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var acc := 0.0
	while g >= 0:
		out.append(Vector3(g, s, acc))
		acc += s
		s = galleries[g].attach_s
		g = galleries[g].parent
	out.append(Vector3(-1, 0.0, acc))
	return out

## A winding route for a tunnel from `from` to `to` (SimLayer.route, clear of
## planned digging), or the straight line if there is none.
func route_tunnel(from: Vector2, to: Vector2, plan: ExcavationPlan) -> PackedVector2Array:
	var pts := layer.route(from, to, {"avoid": plan.planned_cells(), "seed": rough_seed + list.size() * 7 + galleries.size(),
			"clearance": tunnel_radius * 3.0, "margin": 90.0})
	if pts.size() < 2:
		pts = PackedVector2Array([from, to])
	return pts

## Marks chambers whose digging is finished. Returns how many became dug.
func update_dug(plan: ExcavationPlan) -> int:
	var n := 0
	for c in list:
		if not c.dug and c.job >= 0 and plan.job_by_id(c.job).done:
			c.dug = true
			n += 1
	return n

## True if the tunnels and chambers form at least one loop (a cross-link
## between two chambers, both hanging off galleries).
func has_loop() -> bool:
	for g in galleries:
		if g.level == Level.LINK:
			return true
	return false

## The layout's own RNG (for the nest's other placement decisions, so the
## simulation's random stream is untouched).
func layout_rng() -> RandomNumberGenerator:
	return _rng

## The point on a gallery (or the royal chamber's centre) nearest `at`, for a
## new tunnel to leave from.
func nearest_tunnel_point(at: Vector2) -> Vector2:
	var best := royal().centre
	var best_d := at.distance_to(best)
	for g in galleries:
		if g.level == Level.STUB:
			continue
		for k in g.points.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(at, g.points[k], g.points[k + 1])
			var d := q.distance_to(at)
			if d < best_d:
				best_d = d
				best = q
	return best
