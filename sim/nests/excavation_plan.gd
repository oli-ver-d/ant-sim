class_name ExcavationPlan
extends RefCounted
## The digging a nest wants done in its underground layer, as a list of jobs.
## A job is a shape to dig out (a DigShape: a tunnel along a path with a
## radius per point, an irregular blob of lobes, or any cell set), dug
## starting from `origin`, a point in space that is already open (the end of
## the tunnel it branches off, the rim of the chamber it leaves from). A job
## is open once its origin cell is free, so a chamber waits for the tunnel
## leading to it. Diggers take the open job with the lowest `priority` that
## has room for them (max_diggers), walk to its origin (a nav field per job),
## then to its digging face (a small local field over the job's box, toward
## cells next to the job's remaining soil) and bite one of the job's soil
## cells beside them. Each cell has a rank (DigShape: progress along a path,
## closeness to where a blob is entered), and the bitten cell is a weighted
## random pick among those in reach, favouring the highest ranked and the
## softest soil, so tunnels advance along their path and chambers open up
## outward from the way in, with an uneven, crumbling face. See the core
## "dig" behaviour.
##
## `overdig` (world units) makes new shapes' outlines rough (DigShape), so
## walls come out scalloped; `ragged` sets how uneven the face is (0: always
## the highest ranked cell, as a deterministic order).
##
## add_job() plans the classic capsule (every soil cell within `radius` of
## the segment a-b: a tunnel, or a round chamber when a == b).
##
## A job can open a portal when it is finished (e.g. the entrance shaft of a
## sealed nest, see open_portal_when_done()).

class Job:
	var id: int
	var name: String
	var origin: Vector2
	## The shape being dug (its cells, ranks and, for paths, points and radii).
	var shape: DigShape
	## Where digging heads: the path's end, or a blob's way in.
	var face_target: Vector2
	## Capsule jobs (add_job): the segment and radius they were planned with.
	var a: Vector2
	var b: Vector2
	var radius: float
	var priority: float
	var max_diggers: int
	## Soil cells of the job when it was planned.
	var cells: PackedInt32Array = []
	## Of those, still soil.
	var remaining: int = 0
	var diggers: int = 0
	var done: bool = false
	## Nav field toward the origin (removed when done).
	var nav_field: int = -1
	## Local field: distance (NavGrid units) to a cell where a digger can bite,
	## over the cells of `box` (row-major), rebuilt when a dig lands in the box.
	var box: Rect2i
	var local: PackedInt32Array = []
	var local_log: int = -1
	var open_portal: Portal = null
	## Free-form tags for whoever planned it (e.g. "gallery", "widening").
	var tags: Dictionary = {}

var world: World
var nav: NavGrid
var layer: int
## Work removed from a soil cell per bite (a cell of normal soil holds 0.8-1.2).
var bite: float = 1.2
## Soil cells a bite clears: the one bitten and, beside it, more of the
## same job's digging face (a pellet is a mouthful of soil, bigger than a
## cell).
var cells_per_bite: int = 3
## Roughness of new shapes' outlines (world units, see DigShape); 0 = exact.
var overdig: float = 0.0
## Seed of the outline noise.
var rough_seed: int = 0
## How uneven the digging face is: rank difference (world units) at which a
## cell is e times less likely to be bitten. 0 = always the best ranked.
var ragged: float = 6.0
var jobs: Array[Job] = []
## Soil cell -> id of the job it belongs to.
var _cell_job: Dictionary[int, int] = {}
## Soil cell -> its rank in that job (see DigShape).
var _cell_rank: Dictionary[int, float] = {}
## Jobs finished so far, in order.
var finished: PackedInt32Array = []

func _init(on_layer: SimLayer) -> void:
	world = on_layer.world
	nav = on_layer.nav()
	layer = on_layer.index

## Plans a capsule job (see the class notes) and returns it. Cells another
## unfinished job already claims stay with that job. With overdig on, the
## capsule's outline is rough like any other shape.
func add_job(job_name: String, origin: Vector2, a: Vector2, b: Vector2, radius: float,
		priority: float = 0.0, max_diggers: int = 4) -> Job:
	var shape: DigShape
	if overdig > 0.0:
		shape = DigShape.path(world, PackedVector2Array([a, b]) if a != b else PackedVector2Array([a]),
				PackedFloat32Array([radius, radius]) if a != b else PackedFloat32Array([radius]), overdig, rough_seed)
		shape.face_target = b
	else:
		# Exactly the cells within the radius, each ranked by closeness to b.
		shape = DigShape.from_cells(world, world.cells_in_segment(a, b, radius), b)
	var job := add_shape_job(job_name, origin, shape, priority, max_diggers)
	job.a = a
	job.b = b
	job.radius = radius
	return job

## Plans a tunnel along `points` with radius `radii[k]` at points[k].
func add_path_job(job_name: String, origin: Vector2, points: PackedVector2Array, radii: PackedFloat32Array,
		priority: float = 0.0, max_diggers: int = 4) -> Job:
	return add_shape_job(job_name, origin, DigShape.path(world, points, radii, overdig, rough_seed), priority, max_diggers)

## Plans a blob of ellipses (DigShape.ellipses: 5 floats per lobe), opened
## up outward from `face_target`.
func add_blob_job(job_name: String, origin: Vector2, lobes: PackedFloat32Array, face_target: Vector2,
		priority: float = 0.0, max_diggers: int = 4) -> Job:
	return add_shape_job(job_name, origin, DigShape.ellipses(world, lobes, face_target, overdig, rough_seed),
			priority, max_diggers)

## Plans any shape and returns the job. Cells another unfinished job already
## claims stay with that job; only soil cells are dug (stones stay).
func add_shape_job(job_name: String, origin: Vector2, shape: DigShape, priority: float = 0.0,
		max_diggers: int = 4) -> Job:
	var job := Job.new()
	job.id = jobs.size()
	job.name = job_name
	job.origin = origin
	job.shape = shape
	job.face_target = shape.face_target
	job.a = origin
	job.b = shape.face_target
	job.priority = priority
	job.max_diggers = max_diggers
	for k in shape.cells.size():
		var cell := shape.cells[k]
		if world.is_soil(cell) and not _cell_job.has(cell):
			job.cells.append(cell)
			_cell_job[cell] = job.id
			_cell_rank[cell] = shape.rank[k]
	job.remaining = job.cells.size()
	var cs := world.cell_size
	var o := Vector2i(int(origin.x / cs), int(origin.y / cs))
	var lo := Vector2i(mini(shape.box.position.x, o.x), mini(shape.box.position.y, o.y)) - Vector2i(3, 3)
	var hi := Vector2i(maxi(shape.box.end.x, o.x + 1), maxi(shape.box.end.y, o.y + 1)) + Vector2i(3, 3)
	lo = lo.clamp(Vector2i.ZERO, Vector2i(world.width - 1, world.height - 1))
	hi = hi.clamp(Vector2i.ZERO, Vector2i(world.width, world.height))
	job.box = Rect2i(lo, hi - lo)
	jobs.append(job)
	if job.remaining == 0:
		_finish(job)
	else:
		job.nav_field = nav.set_target_point(StringName("job:%d" % job.id), origin)
	return job

## Every soil cell claimed by an unfinished job (cell -> job id), e.g. for
## routing new tunnels clear of planned chambers.
func planned_cells() -> Dictionary[int, int]:
	return _cell_job

## Opens `portal` when `job` is finished (at once if it already is).
func open_portal_when_done(job: Job, portal: Portal) -> void:
	job.open_portal = portal
	if job.done:
		portal.open = true

func is_open(job: Job) -> bool:
	return not job.done and world.obstacles[world.cell_at(job.origin)] == World.Cell.FREE

## Soil cells left in unfinished jobs.
func remaining() -> int:
	var n := 0
	for job in jobs:
		if not job.done:
			n += job.remaining
	return n

## The open job a new digger should take (lowest priority value with room),
## or null if there is none.
func pick_job() -> Job:
	var best: Job = null
	for job in jobs:
		if job.diggers >= job.max_diggers or not is_open(job):
			continue
		if best == null or job.priority < best.priority:
			best = job
	return best

func job_by_id(id: int) -> Job:
	return jobs[id] if id >= 0 and id < jobs.size() else null

## Removes one bite from `cell` (a soil cell of `job`). Returns the work dug
## out (0 if the cell was already gone).
func dig_cell(target: Job, cell: int, amount: float = -1.0) -> float:
	if not world.is_soil(cell):
		return 0.0
	var take := _dig_one(target, cell, bite if amount < 0.0 else amount)
	if amount < 0.0 and cells_per_bite > 1 and not target.done:
		# More of the face beside it, nearest the bitten cell first.
		var extra := 0
		var cx := cell % world.width
		@warning_ignore("integer_division")
		var cy := cell / world.width
		for k in 8:
			if extra >= cells_per_bite - 1:
				break
			var nx := cx + _DX[k]
			var ny := cy + _DY[k]
			if nx < 0 or ny < 0 or nx >= world.width or ny >= world.height:
				continue
			var n := ny * world.width + nx
			if _cell_job.get(n, -1) == target.id and _free_beside(n):
				take += _dig_one(target, n, bite)
				extra += 1
	return take

func _dig_one(target: Job, cell: int, amount: float) -> float:
	if not world.is_soil(cell):
		return 0.0
	var take := minf(amount, world.soil[cell])
	if world.dig(cell, take + 1e-5):
		if _cell_job.get(cell, -1) == target.id:
			target.remaining -= 1
			if target.remaining <= 0:
				_finish(target)
		_cell_job.erase(cell)
		_cell_rank.erase(cell)
	return take

## True if a free cell touches cell c (it is on the digging face).
func _free_beside(c: int) -> bool:
	for nb: int in [c - 1, c + 1, c - world.width, c + world.width]:
		if nb >= 0 and nb < world.obstacles.size() and world.obstacles[nb] == World.Cell.FREE:
			return true
	return false

## Where a digger at `at` inside the job's box should step next toward the
## digging face: `at` itself if it can bite from here, or Vector2.INF if the
## face can't be reached from here (e.g. still outside the box).
func face_step(target: Job, at: Vector2) -> Vector2:
	var cx := int(at.x / world.cell_size) - target.box.position.x
	var cy := int(at.y / world.cell_size) - target.box.position.y
	if cx < 0 or cy < 0 or cx >= target.box.size.x or cy >= target.box.size.y:
		return Vector2.INF
	_refresh_local(target)
	var w := target.box.size.x
	var here := target.local[cy * w + cx]
	if here >= NavGrid.UNREACHED:
		return Vector2.INF
	if here == 0:
		return at
	# Best neighbour inside the box (no corner cutting).
	var best := -1
	var best_d := here
	for k in 8:
		var nx := cx + _DX[k]
		var ny := cy + _DY[k]
		if nx < 0 or ny < 0 or nx >= w or ny >= target.box.size.y:
			continue
		if k >= 4 and (not _free_local(target, nx, cy) or not _free_local(target, cx, ny)):
			continue
		var d := target.local[ny * w + nx]
		if d < best_d:
			best_d = d
			best = ny * w + nx
	if best < 0:
		return at
	@warning_ignore("integer_division")
	return Vector2((best % w + target.box.position.x + 0.5) * world.cell_size,
			(best / w + target.box.position.y + 0.5) * world.cell_size)

## The job's soil cell to bite from `at` (one of the 8 around its cell), or
## -1. With `rng` and `ragged` > 0 a weighted random pick: the best ranked
## (see DigShape) is likeliest, a cell `ragged` world units of rank behind it
## e times less likely, and harder soil (clay, roots) less likely in
## proportion to its hardness; without, the best ranked.
func bite_cell(target: Job, at: Vector2, rng: RandomNumberGenerator = null) -> int:
	var here := world.cell_at(at)
	if here < 0:
		return -1
	var cx := here % world.width
	@warning_ignore("integer_division")
	var cy := here / world.width
	var found: PackedInt32Array = []
	var ranks: PackedFloat32Array = []
	var best := -1
	var best_rank := -INF
	for k in 8:
		var nx := cx + _DX[k]
		var ny := cy + _DY[k]
		if nx < 0 or ny < 0 or nx >= world.width or ny >= world.height:
			continue
		var n := ny * world.width + nx
		if _cell_job.get(n, -1) != target.id:
			continue
		var r: float = _cell_rank.get(n, 0.0)
		found.append(n)
		ranks.append(r)
		if r > best_rank:
			best_rank = r
			best = n
	if rng == null or ragged <= 0.0 or found.size() < 2:
		return best
	var weights: PackedFloat32Array = []
	var total := 0.0
	for k in found.size():
		var w := exp((ranks[k] - best_rank) / ragged) / maxf(1.0, world.soil[found[k]] / world.soil_hardness)
		weights.append(w)
		total += w
	var pick := rng.randf() * total
	for k in found.size():
		pick -= weights[k]
		if pick <= 0.0:
			return found[k]
	return found[found.size() - 1]

## True if `cell` is still soil of `target` (a bite chosen earlier is still there).
func is_job_cell(target: Job, cell: int) -> bool:
	return _cell_job.get(cell, -1) == target.id

const _DX: PackedInt32Array = [1, -1, 0, 0, 1, 1, -1, -1]
const _DY: PackedInt32Array = [0, 0, 1, -1, 1, -1, 1, -1]

func _free_local(target: Job, x: int, y: int) -> bool:
	return world.obstacles[(y + target.box.position.y) * world.width + x + target.box.position.x] == World.Cell.FREE

## Rebuilds the job's local field if anything was dug in its box since.
func _refresh_local(target: Job) -> void:
	var log := world.dig_log
	if target.local_log >= 0:
		var changed := false
		for k in range(target.local_log, log.size()):
			var c := log[k]
			@warning_ignore("integer_division")
			if target.box.has_point(Vector2i(c % world.width, c / world.width)):
				changed = true
				break
		target.local_log = log.size()
		if not changed:
			return
	target.local_log = log.size()
	var w := target.box.size.x
	var h := target.box.size.y
	var d := PackedInt32Array()
	d.resize(w * h)
	d.fill(NavGrid.UNREACHED)
	var queue: PackedInt32Array = []
	# Sources: free cells beside one of the job's soil cells.
	for y in h:
		for x in w:
			if not _free_local(target, x, y):
				continue
			for k in 8:
				var nx := x + target.box.position.x + _DX[k]
				var ny := y + target.box.position.y + _DY[k]
				if nx < 0 or ny < 0 or nx >= world.width or ny >= world.height:
					continue
				if _cell_job.get(ny * world.width + nx, -1) == target.id:
					d[y * w + x] = 0
					queue.append(y * w + x)
					break
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var x := c % w
		@warning_ignore("integer_division")
		var y := c / w
		for k in 8:
			var nx := x + _DX[k]
			var ny := y + _DY[k]
			if nx < 0 or ny < 0 or nx >= w or ny >= h or not _free_local(target, nx, ny):
				continue
			if k >= 4 and (not _free_local(target, nx, y) or not _free_local(target, x, ny)):
				continue
			var nd := d[c] + (NavGrid.STRAIGHT if k < 4 else NavGrid.DIAGONAL)
			if nd < d[ny * w + nx]:
				d[ny * w + nx] = nd
				queue.append(ny * w + nx)
	target.local = d

func _finish(target: Job) -> void:
	target.done = true
	finished.append(target.id)
	nav.remove_target(StringName("job:%d" % target.id))
	target.nav_field = -1
	if target.open_portal != null:
		target.open_portal.open = true

## Fingerprint for Simulation.state_hash().
func hash_into(ctx: HashingContext) -> void:
	var state := PackedInt32Array()
	for job in jobs:
		state.append(job.remaining)
		state.append(job.diggers)
	if not state.is_empty():
		ctx.update(state.to_byte_array())
