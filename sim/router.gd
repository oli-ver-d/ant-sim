class_name Router
extends RefCounted
## Routes for new tunnels through a layer's soil (SimLayer.route): A* over
## the cells of a box around the two ends, where a cell costs more the harder
## its soil is (clay, roots; stones and walls can't be crossed), the closer
## it is to open space or to cells other digging already claims (so a new
## tunnel doesn't break into another chamber by accident), plus a gentle
## seeded meander noise so tunnels wind instead of running dead straight.
## Near the two ends open space costs nothing extra (a tunnel starts from a
## cavity and may end in one).
##
## params (all optional):
##   hardness_weight  extra cost per unit of hardness above plain soil (1.5)
##   clearance        distance (world units) from cavities within which cells
##                    cost more (24)
##   cavity_weight    extra cost right next to a cavity, fading out over the
##                    clearance, and of crossing open space (6)
##   end_radius       around each end, no cavity cost (default: clearance)
##   meander          noise amplitude, as a share of a cell's cost (0.8)
##   meander_scale    noise feature size in world units (40)
##   seed             meander noise seed (0)
##   avoid            Dictionary of cells (cell -> anything) counted as
##                    cavities, e.g. ExcavationPlan.planned_cells()
##   margin           the search box around the two ends, world units (120)
## Returns the route as points from `from` to `to` (smoothed, about every
## other cell), or an empty array if there is none.

const SQRT2 := 1.41421356

static func route(world: World, from: Vector2, to: Vector2, params: Dictionary = {}) -> PackedVector2Array:
	var cs := float(world.cell_size)
	var hardness_w := float(params.get("hardness_weight", 1.5))
	var clearance := float(params.get("clearance", 24.0))
	var cavity_w := float(params.get("cavity_weight", 6.0))
	var end_r := float(params.get("end_radius", clearance))
	var meander := float(params.get("meander", 0.8))
	var meander_scale := float(params.get("meander_scale", 40.0)) / cs
	var noise_seed := int(params.get("seed", 0))
	var avoid: Dictionary = params.get("avoid", {})
	var margin := float(params.get("margin", 120.0))
	var start := world.cell_at(from)
	var goal := world.cell_at(to)
	if start < 0 or goal < 0:
		return PackedVector2Array()
	# The search box (cell coordinates).
	var box := Rect2(from, Vector2.ZERO).expand(to).grow(margin)
	var bx0 := maxi(0, int(box.position.x / cs))
	var by0 := maxi(0, int(box.position.y / cs))
	var bx1 := mini(world.width, int(box.end.x / cs) + 1)
	var by1 := mini(world.height, int(box.end.y / cs) + 1)
	var bw := bx1 - bx0
	var bh := by1 - by0
	var n := bw * bh
	# Distance (cells) to the nearest cavity or avoided cell, by a two-pass
	# chamfer transform over the box, capped at the clearance.
	var cap := clearance / cs + 1.0
	var near := PackedFloat32Array()
	near.resize(n)
	for ly in bh:
		for lx in bw:
			var c := (ly + by0) * world.width + lx + bx0
			near[ly * bw + lx] = 0.0 if (world.obstacles[c] == World.Cell.FREE or avoid.has(c)) else cap
	for ly in bh:
		for lx in bw:
			var k := ly * bw + lx
			var v := near[k]
			if lx > 0:
				v = minf(v, near[k - 1] + 1.0)
			if ly > 0:
				v = minf(v, near[k - bw] + 1.0)
				if lx > 0:
					v = minf(v, near[k - bw - 1] + SQRT2)
				if lx < bw - 1:
					v = minf(v, near[k - bw + 1] + SQRT2)
			near[k] = v
	for ly in range(bh - 1, -1, -1):
		for lx in range(bw - 1, -1, -1):
			var k := ly * bw + lx
			var v := near[k]
			if lx < bw - 1:
				v = minf(v, near[k + 1] + 1.0)
			if ly < bh - 1:
				v = minf(v, near[k + bw] + 1.0)
				if lx < bw - 1:
					v = minf(v, near[k + bw + 1] + SQRT2)
				if lx > 0:
					v = minf(v, near[k + bw - 1] + SQRT2)
			near[k] = v
	# Cost of entering each cell of the box (INF: can't be crossed).
	var cost := PackedFloat32Array()
	cost.resize(n)
	for ly in bh:
		for lx in bw:
			var c := (ly + by0) * world.width + lx + bx0
			var k := ly * bw + lx
			var hard := world.hardness_at(c)
			if hard == INF:
				cost[k] = INF
				continue
			var at := world.cell_center(c)
			var at_end := at.distance_to(from) <= end_r or at.distance_to(to) <= end_r
			var v := 1.0
			if hard > 0.0:
				v += hardness_w * maxf(0.0, hard - 1.0)
			elif not at_end:
				v += cavity_w
			if not at_end and near[k] < cap:
				v += cavity_w * (1.0 - near[k] / cap)
			v *= 1.0 + meander * World._value_noise((lx + bx0) / meander_scale, (ly + by0) / meander_scale, noise_seed)
			cost[k] = v
	# A* from start to goal (costs per cell entered, times the step length).
	@warning_ignore("integer_division")
	var ls := (start / world.width - by0) * bw + start % world.width - bx0
	@warning_ignore("integer_division")
	var lg := (goal / world.width - by0) * bw + goal % world.width - bx0
	if ls < 0 or ls >= n or lg < 0 or lg >= n:
		return PackedVector2Array()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var heap := _Heap.new()
	var gx := lg % bw
	@warning_ignore("integer_division")
	var gy := lg / bw
	g[ls] = 0.0
	heap.push(0.0, ls)
	var dx: PackedInt32Array = [1, -1, 0, 0, 1, 1, -1, -1]
	var dy: PackedInt32Array = [0, 0, 1, -1, 1, -1, 1, -1]
	var found := false
	while not heap.is_empty():
		var cur := heap.pop()
		if closed[cur] != 0:
			continue
		if cur == lg:
			found = true
			break
		closed[cur] = 1
		var cx := cur % bw
		@warning_ignore("integer_division")
		var cy := cur / bw
		for d in 8:
			var nx := cx + dx[d]
			var ny := cy + dy[d]
			if nx < 0 or ny < 0 or nx >= bw or ny >= bh:
				continue
			var nb := ny * bw + nx
			if closed[nb] != 0 or cost[nb] == INF:
				continue
			# No squeezing diagonally between two blocked cells.
			if d >= 4 and (cost[cy * bw + nx] == INF or cost[ny * bw + cx] == INF):
				continue
			var ng := g[cur] + cost[nb] * (SQRT2 if d >= 4 else 1.0)
			if ng < g[nb]:
				g[nb] = ng
				came[nb] = cur
				var hx := absi(nx - gx)
				var hy := absi(ny - gy)
				heap.push(ng + mini(hx, hy) * SQRT2 + absi(hx - hy), nb)
	if not found:
		return PackedVector2Array()
	var cells: PackedInt32Array = []
	var k := lg
	while k >= 0:
		cells.append(k)
		k = came[k]
	cells.reverse()
	# Every other cell, then one round of corner cutting (Chaikin) to smooth it.
	var pts := PackedVector2Array([from])
	for j in range(2, cells.size() - 2, 2):
		var lc := cells[j]
		@warning_ignore("integer_division")
		pts.append(Vector2((lc % bw + bx0 + 0.5) * cs, (lc / bw + by0 + 0.5) * cs))
	pts.append(to)
	return smooth(pts)

## One round of Chaikin corner cutting, keeping the two ends.
static func smooth(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		if k > 0:
			out.append(a.lerp(b, 0.25))
		if k < pts.size() - 2:
			out.append(a.lerp(b, 0.75))
	out.append(pts[pts.size() - 1])
	return out

## Length of a polyline.
static func length_of(pts: PackedVector2Array) -> float:
	var total := 0.0
	for k in pts.size() - 1:
		total += pts[k].distance_to(pts[k + 1])
	return total

## Binary min-heap of (key, value) pairs.
class _Heap:
	var keys: PackedFloat32Array = []
	var values: PackedInt32Array = []

	func is_empty() -> bool:
		return values.is_empty()

	func push(key: float, value: int) -> void:
		keys.append(key)
		values.append(value)
		var k := values.size() - 1
		while k > 0:
			@warning_ignore("integer_division")
			var parent := (k - 1) / 2
			if keys[parent] <= keys[k]:
				break
			_swap(k, parent)
			k = parent

	func pop() -> int:
		var top := values[0]
		var last := values.size() - 1
		_swap(0, last)
		keys.resize(last)
		values.resize(last)
		var k := 0
		while true:
			var l := 2 * k + 1
			var r := l + 1
			var m := k
			if l < last and keys[l] < keys[m]:
				m = l
			if r < last and keys[r] < keys[m]:
				m = r
			if m == k:
				break
			_swap(k, m)
			k = m
		return top

	func _swap(a: int, b: int) -> void:
		var tk := keys[a]
		keys[a] = keys[b]
		keys[b] = tk
		var tv := values[a]
		values[a] = values[b]
		values[b] = tv
