class_name DigShape
extends RefCounted
## A shape to dig out of a layer's soil, as the cells it covers plus, for
## each cell, a rank: diggers bite the higher ranked cells of the face first
## (see ExcavationPlan.bite_cell), which is how the shape is dug out in order.
##
##   path     a polyline with a radius per point: a curving, tapering tunnel.
##            A cell's rank is its progress along the path (arc length of its
##            nearest point), so digging advances along it.
##   ellipses a union of ellipses ("lobes"): an irregular chamber. Rank is
##            minus the distance to `face_target` (usually where the way in
##            arrives), so the chamber opens up outward from there.
##   polar    a radius per angle around a centre (r(theta), sampled evenly
##            and interpolated): any star-shaped outline. Ranked as ellipses.
##   cells    any cell set, ranked as ellipses.
##
## Roughness: with `rough` > 0 the outline wanders by up to `rough` world
## units outward (and a third of that inward) with a smooth seeded noise over
## the cells, so walls come out scalloped rather than exact (an overdig). A
## cell is in the shape when its signed distance to the exact outline is at
## most rough * noise, noise in [-1/3, 1]. The noise is a function of the cell
## and `rough_seed` only, so the same shape is always the same cells.
##
## Shapes are plain cell lists; they don't look at what is soil (the plan and
## World.carve_cells() do).

enum Kind { PATH, ELLIPSES, POLAR, CELLS }

var kind: int = Kind.CELLS
var cells: PackedInt32Array = []
## Per cell (same order as cells): higher is dug first.
var rank: PackedFloat32Array = []
## A path's points and radii (world units).
var points: PackedVector2Array = []
var radii: PackedFloat32Array = []
## Where a blob's digging starts from (ranks fall off with distance to it).
var face_target: Vector2
## Bounding box of the cells (cell coordinates, end exclusive).
var box: Rect2i

## Inward share of the roughness (see the class notes).
const INWARD := 1.0 / 3.0
## Noise feature size, in cells.
const ROUGH_SCALE := 2.3

## A tunnel along `pts` with radius `r[k]` at pts[k] (interpolated between).
static func path(world: World, pts: PackedVector2Array, r: PackedFloat32Array, rough: float = 0.0,
		rough_seed: int = 0) -> DigShape:
	var s := DigShape.new()
	s.kind = Kind.PATH
	s.points = pts
	s.radii = r
	if pts.size() == 1:
		s.face_target = pts[0]
		return _fill_blob(s, world, func(p: Vector2) -> float: return p.distance_to(pts[0]) - r[0],
				Rect2(pts[0], Vector2.ZERO).grow(r[0]), rough, rough_seed)
	var cs := world.cell_size
	var inv := 1.0 / cs
	# Per cell: best signed distance so far and its progress (arc length).
	var best: Dictionary[int, Vector2] = {}
	var along := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var seg := b - a
		var seg_len := seg.length()
		var ra := r[k]
		var rb := r[k + 1]
		var reach := maxf(ra, rb) + rough + cs
		var x0 := maxi(0, int((minf(a.x, b.x) - reach) * inv))
		var x1 := mini(world.width - 1, int((maxf(a.x, b.x) + reach) * inv))
		var y0 := maxi(0, int((minf(a.y, b.y) - reach) * inv))
		var y1 := mini(world.height - 1, int((maxf(a.y, b.y) + reach) * inv))
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				var c := Vector2((cx + 0.5) * cs, (cy + 0.5) * cs)
				var t := 0.0
				if seg_len > 1e-6:
					t = clampf((c - a).dot(seg) / (seg_len * seg_len), 0.0, 1.0)
				var d := c.distance_to(a + seg * t) - lerpf(ra, rb, t)
				var cell := cy * world.width + cx
				var prev: Vector2 = best.get(cell, Vector2(INF, 0.0))
				if d < prev.x:
					best[cell] = Vector2(d, along + seg_len * t)
		along += seg_len
	s.face_target = pts[pts.size() - 1]
	for cell: int in best:
		var e: Vector2 = best[cell]
		if e.x <= rough * rough_at(world, cell, rough_seed):
			s.cells.append(cell)
			s.rank.append(e.y)
	_sort(s, world)
	return s

## A union of ellipses: `lobes` holds 5 floats per lobe (centre x, centre y,
## radius x, radius y, rotation in radians).
static func ellipses(world: World, lobes: PackedFloat32Array, target: Vector2, rough: float = 0.0,
		rough_seed: int = 0) -> DigShape:
	var s := DigShape.new()
	s.kind = Kind.ELLIPSES
	s.face_target = target
	@warning_ignore("integer_division")
	var n := lobes.size() / 5
	var bounds := Rect2()
	for k in n:
		var o := k * 5
		var rr := maxf(lobes[o + 2], lobes[o + 3])
		var lb := Rect2(Vector2(lobes[o], lobes[o + 1]), Vector2.ZERO).grow(rr)
		bounds = lb if k == 0 else bounds.merge(lb)
	return _fill_blob(s, world, func(p: Vector2) -> float: return ellipses_distance(lobes, p), bounds, rough, rough_seed)

## Approximate signed distance (world units) from p to the union of `lobes`
## (see ellipses()): negative inside.
static func ellipses_distance(lobes: PackedFloat32Array, p: Vector2) -> float:
	var best := INF
	@warning_ignore("integer_division")
	for k in lobes.size() / 5:
		var o := k * 5
		var local := (p - Vector2(lobes[o], lobes[o + 1])).rotated(-lobes[o + 4])
		var rx := lobes[o + 2]
		var ry := lobes[o + 3]
		var q := sqrt((local.x * local.x) / (rx * rx) + (local.y * local.y) / (ry * ry))
		# Scaled by the radius in the point's direction: exact on the axes.
		var dir_r := local.length() / maxf(q, 1e-6) if local.length() > 1e-6 else minf(rx, ry)
		best = minf(best, (q - 1.0) * dir_r)
	return best

## A star-shaped outline around `centre`: radius `r[k]` at angle k * TAU / n.
static func polar(world: World, centre: Vector2, r: PackedFloat32Array, target: Vector2, rough: float = 0.0,
		rough_seed: int = 0) -> DigShape:
	var s := DigShape.new()
	s.kind = Kind.POLAR
	s.face_target = target
	var rmax := 0.0
	for v in r:
		rmax = maxf(rmax, v)
	return _fill_blob(s, world, func(p: Vector2) -> float: return p.distance_to(centre) - polar_radius(r, (p - centre).angle()),
			Rect2(centre, Vector2.ZERO).grow(rmax), rough, rough_seed)

## r(theta) of a polar outline (linear between samples).
static func polar_radius(r: PackedFloat32Array, theta: float) -> float:
	var n := r.size()
	var u := fposmod(theta, TAU) / TAU * n
	var k := int(u) % n
	return lerpf(r[k], r[(k + 1) % n], u - floorf(u))

## Any set of cells, ranked by closeness to `target`.
static func from_cells(world: World, set_cells: PackedInt32Array, target: Vector2) -> DigShape:
	var s := DigShape.new()
	s.kind = Kind.CELLS
	s.face_target = target
	s.cells = set_cells.duplicate()
	for c in s.cells:
		s.rank.append(-world.cell_center(c).distance_to(target))
	_sort(s, world)
	return s

## Cells within `bounds` (grown by the roughness) whose signed distance
## `dist` is inside the rough outline, ranked by closeness to face_target.
static func _fill_blob(s: DigShape, world: World, dist: Callable, bounds: Rect2, rough: float,
		rough_seed: int) -> DigShape:
	var cs := world.cell_size
	var inv := 1.0 / cs
	var b := bounds.grow(rough + cs)
	var x0 := maxi(0, int(b.position.x * inv))
	var x1 := mini(world.width - 1, int(b.end.x * inv))
	var y0 := maxi(0, int(b.position.y * inv))
	var y1 := mini(world.height - 1, int(b.end.y * inv))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var cell := cy * world.width + cx
			var c := Vector2((cx + 0.5) * cs, (cy + 0.5) * cs)
			var d: float = dist.call(c)
			if d <= rough * rough_at(world, cell, rough_seed):
				s.cells.append(cell)
				s.rank.append(-c.distance_to(s.face_target))
	_sort(s, world)
	return s

## Orders the cells row-major (so every shape lists its cells the same way)
## and sets the bounding box.
static func _sort(s: DigShape, world: World) -> void:
	var order: Array[int] = []
	for k in s.cells.size():
		order.append(k)
	order.sort_custom(func(a: int, b: int) -> bool: return s.cells[a] < s.cells[b])
	var cells: PackedInt32Array = []
	var rank: PackedFloat32Array = []
	var lo := Vector2i(world.width, world.height)
	var hi := Vector2i(-1, -1)
	for k in order:
		var c := s.cells[k]
		cells.append(c)
		rank.append(s.rank[k])
		@warning_ignore("integer_division")
		var p := Vector2i(c % world.width, c / world.width)
		lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
		hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
	s.cells = cells
	s.rank = rank
	s.box = Rect2i(lo, hi - lo + Vector2i.ONE) if not cells.is_empty() else Rect2i()

## Smooth seeded noise over cells, in [-INWARD, 1]: how far out (as a share
## of the roughness) the outline reaches at this cell.
static func rough_at(world: World, cell: int, rough_seed: int) -> float:
	var x := float(cell % world.width) / ROUGH_SCALE
	@warning_ignore("integer_division")
	var y := float(cell / world.width) / ROUGH_SCALE
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var v := lerpf(lerpf(_lattice(ix, iy, rough_seed), _lattice(ix + 1, iy, rough_seed), fx),
			lerpf(_lattice(ix, iy + 1, rough_seed), _lattice(ix + 1, iy + 1, rough_seed), fx), fy)
	return lerpf(-INWARD, 1.0, v)

## Stable value in [0, 1) for a lattice point.
static func _lattice(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 1274126177) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1103515245) & 0x7FFFFFFF
	return float((h ^ (h >> 16)) & 0xFFFF) / 65536.0
