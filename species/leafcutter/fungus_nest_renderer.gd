class_name FungusNestRenderer
extends Node2D
## Draws a FungusNest on the surface: a mound of excavated soil around the
## entrance that grows with every chamber dug, and the waste dump beside it,
## a grey-brown pile of spent substrate that grows with every load dumped.
##
## The dump is drawn in chunks of CHUNK clumps, each its own canvas item; only
## the newest, still-filling chunk is redrawn as loads arrive, so a big pile
## costs no more to keep up to date than a small one.

const SOIL := Color(0.36, 0.26, 0.17)
const WASTE := Color(0.4, 0.37, 0.31)
## Clumps drawn per load dumped, and the cap.
const CLUMPS_PER_LOAD := 1.0
const MAX_CLUMPS := 900
const CHUNK := 50

var nest: FungusNest
var _drawn_chambers: int = -1
var _drawn_open: bool = true
var _drawn_extra: int = 0
var _mound: Node2D
var _chunks: Array[DumpChunk] = []

func bind(_sim: Simulation, target: Object) -> void:
	nest = target as FungusNest
	position = nest.entrance_position()
	# Dump chunks go underneath (inserted before it); mound and entrance on top.
	_mound = Node2D.new()
	_mound.draw.connect(_draw_mound)
	add_child(_mound)

func _process(_delta: float) -> void:
	var extra := 0
	for p in nest.extra_portals:
		extra += 1 if p.open else 0
	if nest.chambers != _drawn_chambers or nest.has_entrance() != _drawn_open or extra != _drawn_extra:
		_drawn_extra = extra
		_drawn_open = nest.has_entrance()
		_drawn_chambers = nest.chambers
		_mound.queue_redraw()
	var clumps := mini(int(nest.dumped_items * CLUMPS_PER_LOAD), MAX_CLUMPS)
	while _chunks.size() * CHUNK < clumps:
		var chunk := DumpChunk.new()
		chunk.first = _chunks.size() * CHUNK
		chunk.dump = nest.dump_offset
		chunk.seed_base = nest.colony_id * 7919 + 11
		_chunks.append(chunk)
		add_child(chunk)
		move_child(chunk, _chunks.size() - 1)
	for chunk in _chunks:
		var count := clampi(clumps - chunk.first, 0, CHUNK)
		# Full chunks are drawn once; the filling one in steps of a few loads.
		if count != chunk.count and (count - chunk.count >= 3 or count == CHUNK):
			chunk.count = count
			chunk.queue_redraw()

func _draw_mound() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = nest.colony_id * 7919 + 3
	# Excavated soil: loose crumbs heaped around the entrance, more per chamber.
	var mound := nest.radius * (2.2 + 0.5 * nest.chambers)
	var crumbs := 60 + 40 * nest.chambers
	# A nest that digs its own underground heaps its spoil beside the entrance
	# (SpoilHeapRenderer); here just a rim, or a scuffed patch while sealed.
	if nest.underground_layer >= 0:
		mound = nest.radius * (2.0 if nest.has_entrance() else 1.3)
		crumbs = 70 if nest.has_entrance() else 30
	for k in 5:
		var t := float(k) / 4.0
		_mound.draw_circle(Vector2.ZERO, mound * (1.2 - 0.35 * t), Color(SOIL, 0.1 + 0.08 * t))
	for n in crumbs:
		var p := Vector2.from_angle(rng.randf() * TAU) * mound * (0.35 + 0.75 * sqrt(rng.randf()))
		var r := rng.randf_range(0.8, 2.0)
		# Lit from the top-left like everything else: a shadow, then the crumb.
		_mound.draw_circle(p + Vector2(0.4, 0.6), r, Color(0, 0, 0, 0.25))
		_mound.draw_circle(p, r, SOIL.lightened(rng.randf() * 0.25))
	# Entrance: a dark crater (none yet while a founding nest is sealed).
	if not nest.has_entrance():
		return
	_mound.draw_circle(Vector2.ZERO, nest.radius * 1.5, SOIL.darkened(0.35))
	_mound.draw_circle(Vector2.ZERO, nest.radius, Color(0.05, 0.03, 0.02))
	# Entrances opened later (a nest that grows digs more): each a smaller
	# rim of crumbs around its own crater.
	for p in nest.extra_portals:
		if not p.open:
			continue
		var at := p.pos_a - position
		for n in 40:
			var q := at + Vector2.from_angle(rng.randf() * TAU) * nest.radius * (1.0 + 0.9 * sqrt(rng.randf()))
			var r := rng.randf_range(0.8, 1.8)
			_mound.draw_circle(q + Vector2(0.4, 0.6), r, Color(0, 0, 0, 0.25))
			_mound.draw_circle(q, r, SOIL.lightened(rng.randf() * 0.25))
		_mound.draw_circle(at, nest.radius * 1.4, SOIL.darkened(0.35))
		_mound.draw_circle(at, nest.radius * 0.95, Color(0.05, 0.03, 0.02))

## Clumps first .. first + count - 1 of the dump. Each clump's look comes from
## its own seed, and clump n lands within a radius that grows with n, so
## earlier clumps never move and the pile spreads by accretion.
class DumpChunk extends Node2D:
	var first: int = 0
	var count: int = 0
	var dump: Vector2
	var seed_base: int

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		for n in range(first, first + count):
			rng.seed = seed_base + n * 104729
			var spread := 5.0 + sqrt(float(n)) * 1.3
			var p := dump + Vector2.from_angle(rng.randf() * TAU) * spread * sqrt(rng.randf())
			var r := rng.randf_range(1.2, 2.2)
			draw_circle(p + Vector2(0.5, 0.7), r, Color(0, 0, 0, 0.22))
			draw_circle(p, r, WASTE.darkened(rng.randf() * 0.35).lerp(Color(0.5, 0.46, 0.36), rng.randf() * 0.3))
