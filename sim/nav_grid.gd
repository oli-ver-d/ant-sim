class_name NavGrid
extends RefCounted
## Navigation over a layer's free cells: one distance field per named target
## (e.g. "portal:0", a chamber), each holding every free cell's walking
## distance to the target's source cells. Ants follow a field downhill (see
## Travel), which is reliable in narrow tunnels where pheromone trails are not.
##
## Distances are integers: STRAIGHT per orthogonal step and DIAGONAL per
## diagonal step (about 5:7, close to Euclidean), and a diagonal step is only
## allowed when both cells beside it are free, so paths never cut corners.
## Unreachable cells (and blocked ones) hold UNREACHED.
##
## Fields follow the world: digging only frees cells, so each freed cell (read
## from World.dig_log) is relaxed into every field locally; any other change
## (World.edit_version) recomputes every field. update() does this and is
## called by the Simulation at the start of every tick.

const UNREACHED := 1 << 30
const STRAIGHT := 5
const DIAGONAL := 7

## One target's distance field.
class Field:
	var id: int
	var name: StringName
	var sources: PackedInt32Array = []
	var dist: PackedInt32Array = []

var world: World
## Fields by id; ids are never reused, so ants can keep one in a scratch slot.
var fields: Dictionary[int, Field] = {}
var _by_name: Dictionary[StringName, int] = {}
var _next_id: int = 0
var _edit_version: int = -1
var _log_read: int = 0
# Neighbour offsets (dx, dy) and step costs, orthogonal first.
var _dx: PackedInt32Array = [1, -1, 0, 0, 1, 1, -1, -1]
var _dy: PackedInt32Array = [0, 0, 1, -1, 1, -1, 1, -1]
var _cost: PackedInt32Array = [STRAIGHT, STRAIGHT, STRAIGHT, STRAIGHT, DIAGONAL, DIAGONAL, DIAGONAL, DIAGONAL]

func _init(target_world: World) -> void:
	world = target_world
	_edit_version = world.edit_version
	_log_read = world.dig_log.size()

## Creates (or replaces) the field `target_name` toward the given source cells
## and returns its id. Sources that are still soil join the field once dug.
func set_target(target_name: StringName, sources: PackedInt32Array) -> int:
	var f: Field
	if _by_name.has(target_name):
		f = fields[_by_name[target_name]]
	else:
		f = Field.new()
		f.id = _next_id
		_next_id += 1
		f.name = target_name
		fields[f.id] = f
		_by_name[target_name] = f.id
	f.sources = sources
	_compute(f)
	return f.id

## Field toward the cell at a world position.
func set_target_point(target_name: StringName, at: Vector2) -> int:
	return set_target(target_name, PackedInt32Array([world.cell_at(at)]))

func remove_target(target_name: StringName) -> void:
	if _by_name.has(target_name):
		fields.erase(_by_name[target_name])
		_by_name.erase(target_name)

func has_target(target_name: StringName) -> bool:
	return _by_name.has(target_name)

## Field id for a target name, or -1.
func field_id(target_name: StringName) -> int:
	return _by_name.get(target_name, -1)

## Walking distance (world units) from `at` to field `id`'s target, or INF.
func distance(id: int, at: Vector2) -> float:
	var f: Field = fields.get(id)
	var cell := world.cell_at(at)
	if f == null or cell < 0 or f.dist[cell] >= UNREACHED:
		return INF
	return f.dist[cell] * world.cell_size / float(STRAIGHT)

## Brings every field up to date with the world (see the class notes).
func update() -> void:
	if world.edit_version != _edit_version:
		_edit_version = world.edit_version
		_log_read = world.dig_log.size()
		for id: int in fields:
			_compute(fields[id])
		return
	var log := world.dig_log
	var n := log.size()
	while _log_read < n:
		var cell := log[_log_read]
		_log_read += 1
		if world.obstacles[cell] == World.Cell.FREE:
			for id: int in fields:
				_relax_from(fields[id], cell)

## The point to steer toward to go downhill in field `id` from `at`: the
## centre of the cell two steps down the field, or `at` itself at the target
## (or where the field doesn't reach).
func downhill(id: int, at: Vector2) -> Vector2:
	var f: Field = fields.get(id)
	var cell := world.cell_at(at)
	if f == null or cell < 0:
		return at
	var dist := f.dist
	var here := dist[cell]
	if here >= UNREACHED:
		# Standing on a blocked or cut-off cell (e.g. just after arriving):
		# head for the best free neighbour, if any.
		var near := _best_neighbour(dist, cell)
		return world.cell_center(near) if near >= 0 else at
	if here == 0:
		return at
	var step1 := _best_neighbour(dist, cell)
	if step1 < 0 or dist[step1] >= here:
		return at
	var step2 := _best_neighbour(dist, step1)
	if step2 < 0 or dist[step2] >= dist[step1]:
		return world.cell_center(step1)
	return world.cell_center(step2)

## Neighbour of `cell` with the lowest distance (allowed moves only), or -1.
func _best_neighbour(dist: PackedInt32Array, cell: int) -> int:
	var w := world.width
	var h := world.height
	var obs := world.obstacles
	var cx := cell % w
	@warning_ignore("integer_division")
	var cy := cell / w
	var best := -1
	var best_d := UNREACHED
	for k in 8:
		var nx := cx + _dx[k]
		var ny := cy + _dy[k]
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			continue
		var n := ny * w + nx
		if obs[n] != World.Cell.FREE:
			continue
		if k >= 4 and (obs[cy * w + nx] != World.Cell.FREE or obs[ny * w + cx] != World.Cell.FREE):
			continue
		if dist[n] < best_d:
			best_d = dist[n]
			best = n
	return best

## Full recompute of one field from its sources.
func _compute(f: Field) -> void:
	var d := PackedInt32Array()
	d.resize(world.width * world.height)
	d.fill(UNREACHED)
	var queue: PackedInt32Array = []
	for s in f.sources:
		if s >= 0 and s < d.size() and world.obstacles[s] == World.Cell.FREE:
			d[s] = 0
			queue.append(s)
	f.dist = PackedInt32Array()
	d = _spread(d, queue)
	f.dist = d

## A cell was freed: give it a distance from its neighbours (or 0 if it's a
## source) and spread any improvement outward. Its free neighbours are
## re-spread too, since the new cell may open diagonal moves between them.
func _relax_from(f: Field, cell: int) -> void:
	var d := f.dist
	# Detach so writes below don't copy the whole array (copy-on-write).
	f.dist = PackedInt32Array()
	var queue: PackedInt32Array = []
	if f.sources.has(cell):
		d[cell] = 0
	queue.append(cell)
	var w := world.width
	var cx := cell % w
	@warning_ignore("integer_division")
	var cy := cell / w
	for k in 8:
		var nx := cx + _dx[k]
		var ny := cy + _dy[k]
		if nx >= 0 and ny >= 0 and nx < w and ny < world.height:
			var n := ny * w + nx
			if d[n] < UNREACHED:
				queue.append(n)
	d = _spread(d, queue)
	f.dist = d

## Label-correcting spread (queue-based Bellman-Ford): pops cells and lowers
## their neighbours' distances until nothing improves.
func _spread(d: PackedInt32Array, queue: PackedInt32Array) -> PackedInt32Array:
	var w := world.width
	var h := world.height
	var obs := world.obstacles
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var dc := d[c]
		if dc >= UNREACHED:
			continue
		var cx := c % w
		@warning_ignore("integer_division")
		var cy := c / w
		for k in 8:
			var nx := cx + _dx[k]
			var ny := cy + _dy[k]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var n := ny * w + nx
			if obs[n] != World.Cell.FREE:
				continue
			if k >= 4 and (obs[cy * w + nx] != World.Cell.FREE or obs[ny * w + cx] != World.Cell.FREE):
				continue
			var nd := dc + _cost[k]
			if nd < d[n]:
				d[n] = nd
				queue.append(n)
		# Keep the queue from growing without bound on big spreads.
		if head > 4096 and head * 2 > queue.size():
			queue = queue.slice(head)
			head = 0
	return d
