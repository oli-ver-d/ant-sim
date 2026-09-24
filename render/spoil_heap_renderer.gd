class_name SpoilHeapRenderer
extends Node2D
## The heap of dug-out soil beside a nest entrance (NestType.spoil_position()),
## one crumb per pellet carried up (NestType.spoil_items), in the ochres and
## browns of the soil below. Crumb n lands within a radius that grows with n,
## so earlier crumbs never move and the heap spreads by accretion; later
## crumbs sit a little higher, so the middle builds up lighter.
##
## Drawn in chunks of CHUNK crumbs, each its own canvas item: only the newest
## chunk is redrawn as pellets arrive, so a big heap costs no more to keep up
## to date than a small one. Past MAX_CRUMBS the heap only grows by
## scaling, and a soft shadow keeps its outline.

const CHUNK := 60
const MAX_CRUMBS := 6000
const COLORS: PackedColorArray = [Color(0.4, 0.28, 0.17), Color(0.46, 0.34, 0.22), Color(0.31, 0.21, 0.13),
		Color(0.5, 0.39, 0.26)]

var nest: NestType
var _chunks: Array[HeapChunk] = []
var _base: Node2D

func bind(_sim: Simulation, target: Object) -> void:
	nest = target as NestType
	position = nest.spoil_position()
	_base = Node2D.new()
	_base.draw.connect(_draw_base)
	add_child(_base)

func _process(_delta: float) -> void:
	var crumbs := mini(nest.spoil_items, MAX_CRUMBS)
	while _chunks.size() * CHUNK < crumbs:
		var chunk := HeapChunk.new()
		chunk.first = _chunks.size() * CHUNK
		chunk.seed_base = nest.colony_id * 6151 + 29
		_chunks.append(chunk)
		add_child(chunk)
	for chunk in _chunks:
		var count := clampi(crumbs - chunk.first, 0, CHUNK)
		if count != chunk.count and (count - chunk.count >= 4 or count == CHUNK):
			chunk.count = count
			chunk.queue_redraw()
	var r := _radius(crumbs)
	if absf(_base.scale.x - r) > 0.5:
		_base.scale = Vector2.ONE * r
		_base.queue_redraw()

## Radius of the heap with n crumbs.
static func _radius(n: int) -> float:
	return 4.0 + sqrt(float(n)) * 1.25

## A soft, darker footprint under the crumbs (unit circle, scaled).
func _draw_base() -> void:
	if nest.spoil_items == 0:
		return
	for k in 4:
		var t := float(k) / 3.0
		_base.draw_circle(Vector2(0.05, 0.08), 1.3 - 0.35 * t, Color(0.05, 0.03, 0.02, 0.05))
		_base.draw_circle(Vector2.ZERO, 1.15 - 0.3 * t, Color(COLORS[2], 0.08 + 0.05 * t))

class HeapChunk extends Node2D:
	var first: int = 0
	var count: int = 0
	var seed_base: int

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		for n in range(first, first + count):
			rng.seed = seed_base + n * 104729
			var p := Vector2.from_angle(rng.randf() * TAU) * SpoilHeapRenderer._radius(n) * sqrt(rng.randf())
			var r := rng.randf_range(1.0, 2.0)
			var col := COLORS[rng.randi() % COLORS.size()].lightened(rng.randf() * 0.1 + minf(0.1, n / 20000.0)).darkened(rng.randf() * 0.15)
			draw_circle(p + Vector2(0.45, 0.7), r, Color(0, 0, 0, 0.25))
			draw_circle(p, r, col)
