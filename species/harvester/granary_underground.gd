class_name GranaryUnderground
extends Node2D
## A harvester nest's underground, drawn on its layer's WorldView
## ("underground:granary_nest"): the heaps of stored seeds and the chaff
## around them in each chamber (one canvas item per chamber, redrawn only
## when that chamber's seeds change, at most REDRAW_EVERY seconds apart),
## and the brood (the core BroodRenderer). The soil, tunnels, ants and items
## are drawn by the core.

## Seconds between redraws of a busy chamber.
const REDRAW_EVERY := 0.25
## Chaff flecks drawn per unit of chaff mass, and the cap per chamber.
const FLECKS_PER_MASS := 40.0
const MAX_FLECKS := 400
const CHAFF := Color(0.7, 0.58, 0.36)

var sim: Simulation
var nest: GranaryNest
var view: WorldView
var _heaps: Array[Heap] = []
var _brood: BroodRenderer

func bind(simulation: Simulation, target: Object) -> void:
	sim = simulation
	nest = target as GranaryNest
	_brood = BroodRenderer.new()
	_brood.bind(sim, nest)
	add_child(_brood)

func _process(delta: float) -> void:
	if nest.chambers_layout == null:
		return
	if _brood.view == null:
		_brood.view = view
	while _heaps.size() < nest.chamber_version.size():
		var h := Heap.new()
		h.nest = nest
		h.k = _heaps.size()
		_heaps.append(h)
		add_child(h)
		move_child(h, 0)
	for h in _heaps:
		h.wait -= delta
		if h.drawn != nest.chamber_version[h.k] and h.wait <= 0.0:
			h.drawn = nest.chamber_version[h.k]
			h.wait = REDRAW_EVERY
			h.queue_redraw()

## One chamber's seeds and chaff.
class Heap:
	extends Node2D

	var nest: GranaryNest
	var k: int
	var drawn: int = -1
	var wait: float = 0.0

	func _draw() -> void:
		# Chaff first: pale husk flecks strewn around the heap.
		var rng := RandomNumberGenerator.new()
		rng.seed = nest.colony_id * 7919 + k * 101 + 7
		var flecks := mini(int(nest.chaff[k] * FLECKS_PER_MASS), MAX_FLECKS)
		var centre := nest.heap_centre(k)
		var spread := 8.0 + sqrt(nest.stored_in[k] / 0.4) * 1.9
		for n in flecks:
			var p := centre + Vector2.from_angle(rng.randf() * TAU) * spread * (0.5 + 0.6 * sqrt(rng.randf()))
			draw_set_transform(p, rng.randf() * TAU, Vector2(1.8, 0.8))
			draw_circle(Vector2.ZERO, rng.randf_range(0.5, 0.9), CHAFF.darkened(rng.randf() * 0.35))
		# Seeds: shaded ellipses with a contact shadow, shrinking as eaten.
		var elongation := Vector2(1.6, 1.0)
		for s in nest.seed_pos.size():
			if nest.seed_chamber[s] != k:
				continue
			var look := nest.seed_look[s]
			var r := 2.1 * sqrt(nest.seed_mass[s] / 0.4)
			var rot := float(look % 628) * 0.01
			var c := nest.seed_color[s]
			var at := nest.seed_pos[s]
			draw_set_transform(at + Vector2(0.6, 0.9), rot, elongation)
			draw_circle(Vector2.ZERO, r, Color(0, 0, 0, 0.35))
			draw_set_transform(at, rot, elongation)
			draw_circle(Vector2.ZERO, r, c.darkened(0.2))
			draw_circle(Vector2(-0.15, -0.2) * r, r * 0.7, c)
			draw_circle(Vector2(-0.35, -0.35) * r, r * 0.25, c.lightened(0.4))
		draw_set_transform(Vector2.ZERO)
