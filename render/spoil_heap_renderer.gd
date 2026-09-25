class_name SpoilHeapRenderer
extends Node2D
## The heap of dug-out soil beside a nest entrance (NestType.spoil_position_of()),
## one crumb per pellet carried up through it (NestType.spoil_count). The heap
## is a fan on the outward side of its entrance, wider across than along and
## bent round the entrance like a crescent; crumbs are the ochres and browns
## of the soil below, tinted toward the ground material the heap lies on
## (GroundMap). For "crater" and "mound" entrances some crumbs spill back
## along the way to the rim, so heap and entrance read as one piece of
## excavation.
##
## Crumb n lands within a size that grows with n, so earlier crumbs never
## move and the heap spreads by accretion; later crumbs sit a little higher,
## so the middle builds up lighter. Drawn in chunks of CHUNK crumbs, each its
## own canvas item: only the newest chunk is redrawn as pellets arrive, so a
## big heap costs no more to keep up to date than a small one. Past
## MAX_CRUMBS the heap only grows by scaling, and a soft shadow keeps its
## outline.

const CHUNK := 60
const MAX_CRUMBS := 6000
## Subsoil a little lighter and redder than the topsoil (ground.gdshader's
## soil is 0.13-0.24).
const COLORS: PackedColorArray = [Color(0.33, 0.23, 0.14), Color(0.38, 0.27, 0.17), Color(0.26, 0.18, 0.11),
		Color(0.42, 0.31, 0.2)]
## Crumb colour on each ground material (GroundMap.MATERIALS order), mixed
## in by the material's weight under the heap (soil and moss: none); from
## ground.gdshader's palette.
const MATERIAL_TINT: PackedColorArray = [Color(0, 0, 0, 0), Color(0.48, 0.38, 0.26, 0.5),
		Color(0.42, 0.39, 0.35, 0.35), Color(0, 0, 0, 0), Color(0.3, 0.21, 0.12, 0.25), Color(0.45, 0.37, 0.29, 0.45)]
## Share of crumbs that spill toward the rim of a crater or mound entrance.
const SPILL := 0.22
## The fan's half-size along its way out and across it, in heap radii.
const ALONG := 0.7
const ACROSS := 1.3

var nest: NestType
## Which entrance's heap (0 = the main one; see NestType.spoil_position_of).
var entrance: int = 0
var _chunks: Array[HeapChunk] = []
var _base: Node2D
var _shape: HeapShape

func bind(sim: Simulation, target: Object) -> void:
	nest = target as NestType
	position = nest.spoil_position_of(entrance)
	_shape = HeapShape.new()
	var from := nest.entrance_position() if entrance == 0 else nest.extra_portals[entrance - 1].pos_a
	var out := position - from
	_shape.out = out.normalized() if out.length() > 0.01 else Vector2.RIGHT
	if nest.entrance_style == "crater" or nest.entrance_style == "mound":
		# Back to the rim, from the heap (local coordinates).
		_shape.spill_to = from - position + _shape.out * nest.radius * 1.4
	_shape.tint = ground_tint(sim.ground, position)
	_base = Node2D.new()
	_base.rotation = _shape.out.angle()
	_base.draw.connect(_draw_base)
	add_child(_base)

func _process(_delta: float) -> void:
	var crumbs := mini(nest.spoil_count(entrance), MAX_CRUMBS)
	while _chunks.size() * CHUNK < crumbs:
		var chunk := HeapChunk.new()
		chunk.first = _chunks.size() * CHUNK
		chunk.seed_base = nest.colony_id * 6151 + 29 + entrance * 7727
		chunk.shape = _shape
		_chunks.append(chunk)
		add_child(chunk)
	for chunk in _chunks:
		var count := clampi(crumbs - chunk.first, 0, CHUNK)
		if count != chunk.count and (count - chunk.count >= 4 or count == CHUNK):
			chunk.count = count
			chunk.queue_redraw()
	var r := _radius(crumbs)
	if absf(_base.scale.y - r) > 0.5:
		_base.scale = Vector2(ALONG, ACROSS) * r
		_base.queue_redraw()

## Radius of the heap with n crumbs.
static func _radius(n: int) -> float:
	return 4.0 + sqrt(float(n)) * 1.25

## Tint (rgb, strength in a) for crumbs on the ground at `at`.
static func ground_tint(ground: GroundMap, at: Vector2) -> Color:
	if ground == null:
		return Color(0, 0, 0, 0)
	var rgb := Vector3.ZERO
	var amount := 0.0
	for m in GroundMap.MATERIALS.size():
		var t := MATERIAL_TINT[m]
		var w := ground.weight_at(GroundMap.MATERIALS[m], at)
		rgb += Vector3(t.r, t.g, t.b) * t.a * w
		amount += t.a * w
	if amount <= 0.0:
		return Color(0, 0, 0, 0)
	rgb /= amount
	return Color(rgb.x, rgb.y, rgb.z, amount)

## Where crumb n of a heap lands (local to the heap), from its own rng.
static func crumb_position(n: int, rng: RandomNumberGenerator, shape: HeapShape) -> Vector2:
	var r := _radius(n)
	if shape.spill_to != Vector2.ZERO and rng.randf() < SPILL:
		# Spilled back toward the rim, spreading wider near the heap.
		var t := rng.randf()
		var side := shape.spill_to.orthogonal().normalized()
		return shape.spill_to * t + side * rng.randf_range(-1.0, 1.0) * (2.0 + r * 0.5 * (1.0 - t))
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf())
	var local := Vector2(cos(a) * ALONG, sin(a) * ACROSS) * d * r
	# A crescent: the ends bend back round the entrance.
	local.x -= 0.45 * local.y * local.y / (ACROSS * r)
	return local.rotated(shape.out.angle())

## A soft, darker footprint under the crumbs (unit circle, scaled to the fan).
func _draw_base() -> void:
	if nest.spoil_count(entrance) == 0:
		return
	for k in 4:
		var t := float(k) / 3.0
		_base.draw_circle(Vector2(0.05, 0.08), 1.3 - 0.35 * t, Color(0.05, 0.03, 0.02, 0.05))
		_base.draw_circle(Vector2.ZERO, 1.15 - 0.3 * t, Color(COLORS[2], 0.08 + 0.05 * t))

## How a heap lies: which way is out from its entrance, where the rim is (for
## spilled crumbs; zero = none) and the ground tint.
class HeapShape extends RefCounted:
	var out: Vector2 = Vector2.RIGHT
	var spill_to: Vector2 = Vector2.ZERO
	var tint: Color = Color(0, 0, 0, 0)

class HeapChunk extends Node2D:
	var first: int = 0
	var count: int = 0
	var seed_base: int
	var shape: HeapShape

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		var tint := Color(shape.tint, 1.0)
		for n in range(first, first + count):
			rng.seed = seed_base + n * 104729
			var p := SpoilHeapRenderer.crumb_position(n, rng, shape)
			var r := rng.randf_range(1.0, 2.0)
			var col := COLORS[rng.randi() % COLORS.size()].lightened(rng.randf() * 0.06 + minf(0.08, n / 20000.0)).darkened(rng.randf() * 0.15)
			col = col.lerp(tint.darkened(rng.randf() * 0.2), shape.tint.a)
			draw_circle(p + Vector2(0.45, 0.7), r, Color(0, 0, 0, 0.25))
			draw_circle(p, r, col)
