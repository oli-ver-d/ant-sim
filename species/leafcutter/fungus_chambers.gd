class_name FungusChambers
extends RefCounted
## The chambers of a leafcutter nest that digs its own underground (see
## FungusNest, nest_params "underground"): the royal chamber in the middle,
## where the queen lives and the founding garden grows, and garden chambers
## the colony digs as it grows, each at the end of a tunnel branching off an
## existing chamber.
##
## New chambers are placed procedurally from the scenario seed (their own
## RNG, so the simulation's random stream is untouched): a parent is picked
## (more often a recent one, so the nest sprawls outward), then a direction
## away from the nest's middle and a tunnel length; candidates that would
## crowd another chamber or leave the layer are rejected. Each chamber is two
## ExcavationPlan jobs: the tunnel from the parent's rim, routed through the
## soil (SimLayer.route: around stones, clear of other cavities, winding a
## little), then the chamber, dug outward from where the tunnel comes in.
##
## A chamber is a shape (lobes, see DigShape.ellipses), so everything that
## needs a place in one asks here: chamber_at() (a cell -> chamber map),
## contains(), and the sampling helpers random_point(), floor_point() (away
## from the walls), rim_point() and point_in() (along a ray from the centre),
## which work for any shape. Stones inside a chamber's outline are dug out
## with it (World.soften), so chamber floors are clear; tunnels go around them.

enum Kind { ROYAL, GARDEN }

class Chamber:
	var index: int
	var kind: int
	## A point well inside (the main lobe's centre): nav target and ray origin.
	var centre: Vector2
	## Radius of a circle of the same area.
	var radius: float
	var parent: int = -1
	## Plan jobs (-1: carved from the start).
	var tunnel_job: int = -1
	var job: int = -1
	var dug: bool = false
	## Nav field toward the centre (on the nest's layer).
	var nav_field: int = -1
	## Where the tunnel from the parent enters.
	var door: Vector2
	## The shape: lobes (DigShape.ellipses, 5 floats each).
	var lobes: PackedFloat32Array = []
	## The shape's cells on the nest layer (dug or still to dig).
	var cells: PackedInt32Array = []
	## The tunnel leading to it (points), if routed.
	var tunnel: PackedVector2Array = []
	## Steps from the edge to its deepest cell.
	var depth_max: int = 0

var list: Array[Chamber] = []
## Bottom of the entrance shaft (the portal's underground end).
var shaft: Vector2
var layer_size: Vector2
## Chamber radius range for new garden chambers, and the tunnel between.
var min_radius: float = 38.0
var max_radius: float = 62.0
var tunnel_radius: float = 7.0
var min_gap: float = 26.0
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
	royal.radius = float(params.get("royal_radius", 36.0))
	royal.lobes = PackedFloat32Array([royal.centre.x, royal.centre.y, royal.radius, royal.radius, 0.0])
	royal.dug = true
	royal.door = royal.centre
	list.append(royal)
	# The shaft comes down a little way from the royal chamber, up and to one side.
	var a := _rng.randf_range(-2.4, -0.7)
	shaft = ScenarioEvents.vec2(params["shaft"]) if params.has("shaft") else \
			royal.centre + Vector2.from_angle(a) * (royal.radius + float(params.get("shaft_distance", 46.0)))

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
	for cell in c.cells:
		c.depth_max = maxi(c.depth_max, _depth[cell])

## True if all four neighbours of `cell` belong to chamber k.
func _inner(cell: int, k: int) -> bool:
	var w := world.width
	var cx := cell % w
	return cx > 0 and cx < w - 1 and cell >= w and cell < _owner.size() - w \
			and _owner[cell - 1] == k and _owner[cell + 1] == k and _owner[cell - w] == k and _owner[cell + w] == k

# --- Planning ----------------------------------------------------------------------

## Picks a place for a new garden chamber and returns it (not yet planned),
## or null if nothing fits.
func propose() -> Chamber:
	for attempt in 40:
		# Recent chambers are likelier parents, so the nest grows outward.
		var n := list.size()
		var parent := list[mini(n - 1, int(pow(_rng.randf(), 0.6) * n))]
		# The first chambers are small (a young colony digs little); later ones
		# span the whole range.
		var grown := clampf((n - 1) / 8.0, 0.0, 1.0)
		var r := _rng.randf_range(min_radius * (0.7 + 0.3 * grown), lerpf(min_radius, max_radius, grown))
		var away := (parent.centre - list[0].centre)
		var base := away.angle() if away.length() > 1.0 else _rng.randf_range(-PI, PI)
		var dir := Vector2.from_angle(base + _rng.randf_range(-1.3, 1.3))
		var dist := parent.radius + r + _rng.randf_range(35.0, 90.0)
		var centre := parent.centre + dir * dist
		if not Rect2(Vector2.ZERO, layer_size).grow(-r - 50.0).has_point(centre):
			continue
		var ok := centre.distance_to(shaft) > r + 30.0
		for c in list:
			if ok and centre.distance_to(c.centre) < c.radius + r + min_gap:
				ok = false
		# The tunnel mustn't run through another chamber.
		for c in list:
			if ok and c != parent and Geometry2D.get_closest_point_to_segment(c.centre, parent.centre, centre).distance_to(c.centre) < c.radius + tunnel_radius + 6.0:
				ok = false
		if not ok:
			continue
		var ch := Chamber.new()
		ch.index = n
		ch.kind = Kind.GARDEN
		ch.centre = centre
		ch.radius = r
		ch.lobes = PackedFloat32Array([centre.x, centre.y, r, r, 0.0])
		ch.parent = parent.index
		ch.door = centre - dir * r * 0.9
		return ch
	return null

## Plans a proposed chamber: its tunnel and itself as plan jobs, and a nav
## field toward its centre. `priority` orders it among other digging.
func add(ch: Chamber, plan: ExcavationPlan, priority: float) -> void:
	var parent := list[ch.parent]
	var dir := (ch.centre - parent.centre).normalized()
	var start := parent.centre + dir * reach(parent.index, dir.angle()) * 0.8
	var tunnel_end := ch.centre - dir * ch.radius * 0.6
	var pts := route_tunnel(start, tunnel_end, plan)
	var radii := PackedFloat32Array()
	for p in pts:
		radii.append(tunnel_radius)
	var tunnel := plan.add_path_job("tunnel%d" % ch.index, start, pts, radii, priority, 6)
	ch.tunnel = pts
	ch.door = tunnel_end
	list.append(ch)
	_map(ch)
	# Room for more diggers in a bigger chamber.
	var chamber := plan.add_shape_job("chamber%d" % ch.index, tunnel_end, DigShape.from_cells(world, ch.cells, ch.door), priority + 0.5,
			clampi(int(ch.radius / 3.0), 8, 20))
	ch.tunnel_job = tunnel.id
	ch.job = chamber.id
	ch.nav_field = plan.nav.set_target_point(StringName("chamber:%d" % ch.index), ch.centre)

## A winding route for a tunnel from `from` to `to` (SimLayer.route, clear of
## planned digging), or the straight line if there is none.
func route_tunnel(from: Vector2, to: Vector2, plan: ExcavationPlan) -> PackedVector2Array:
	var pts := layer.route(from, to, {"avoid": plan.planned_cells(), "seed": rough_seed + list.size(),
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

## Adds a proposed chamber already dug out (a nest that starts established):
## its tunnel and itself are carved into the layer's soil at once.
func add_dug(ch: Chamber, nav: NavGrid) -> void:
	var parent := list[ch.parent]
	var dir := (ch.centre - parent.centre).normalized()
	var start := parent.centre + dir * reach(parent.index, dir.angle()) * 0.8
	var tunnel_end := ch.centre - dir * ch.radius * 0.6
	var radii := PackedFloat32Array([tunnel_radius, tunnel_radius])
	ch.tunnel = PackedVector2Array([start, tunnel_end])
	world.carve_path(ch.tunnel, radii, rough, rough_seed)
	ch.door = tunnel_end
	list.append(ch)
	_map(ch)
	world.carve_cells(ch.cells)
	ch.dug = true
	ch.nav_field = nav.set_target_point(StringName("chamber:%d" % ch.index), ch.centre)
