class_name PhoridRenderer
extends Node2D
## Draws a FungusNest's phorid flies (PhoridFlies, nest_params "phorids") over
## the surface ants: a tiny hump-backed fly with a blur of beating wings,
## and its shadow on the ground, offset along the light by its height.
## Registered as "surface_top:fungus_nest"; draws nothing without "phorids".

const BODY := Color(0.22, 0.16, 0.09)
const WING := Color(0.88, 0.9, 0.92, 0.35)
const SHADOW := Color(0, 0, 0, 0.3)
## Body length in world units (a minim is 5, a media 9): a little larger
## than life, to be seen.
const SIZE := 3.4

var sim: Simulation
## The WorldView drawing this (set by it): its tick interpolation.
var view: WorldView
var flies: PhoridFlies

func bind(simulation: Simulation, target: Object) -> void:
	sim = simulation
	var nest := target as FungusNest
	if nest == null or nest.phorids.is_empty():
		set_process(false)
		return
	flies = PhoridFlies.new()
	flies.setup(nest.phorids, nest.colony_id, nest.entrance_position())

func _process(delta: float) -> void:
	var t := Profiler.start()
	_process_body(delta)
	Profiler.stop("PhoridRenderer._process", t)

func _process_body(_delta: float) -> void:
	# set_process(false) in bind() is undone when the node enters the tree.
	if flies == null:
		return
	var alpha := view.alpha if view != null else 1.0
	flies.update(sim, sim.time() - (1.0 - alpha) * sim.dt, alpha)
	queue_redraw()

func _draw() -> void:
	var t := Profiler.start()
	_draw_body()
	Profiler.stop("PhoridRenderer._draw", t)

func _draw_body() -> void:
	if flies == null:
		return
	var t := sim.time()
	for f in flies.count:
		var a := flies.shown[f]
		if a <= 0.0:
			continue
		var at := flies.pos[f]
		var h := flies.heading[f]
		var s := SIZE * (1.0 + flies.alt[f] * 0.02)
		# Shadow: small and soft, further off the higher it flies.
		var sc := SHADOW
		sc.a *= a
		draw_set_transform(at + WingRenderer.LIGHT * flies.alt[f], h, Vector2(s * 0.5, s * 0.3))
		draw_circle(Vector2.ZERO, 1.0, sc)
		# Wings: a pale blur over the stroke either side.
		var beat := sin(t * 170.0 + f * 1.7)
		for side: float in [-1.0, 1.0]:
			var wc := WING
			wc.a *= a
			var ang := h + side * (PI * 0.5 + 0.35 * beat) + PI * 0.15 * side
			draw_set_transform(at + Vector2.from_angle(ang) * s * 0.45, ang, Vector2(s * 0.5, s * 0.28))
			draw_circle(Vector2.ZERO, 1.0, wc)
		# Body: abdomen, humped thorax, small head.
		var bc := BODY
		bc.a *= a
		var fwd := Vector2.from_angle(h)
		draw_set_transform(at - fwd * s * 0.28, h, Vector2(s * 0.3, s * 0.2))
		draw_circle(Vector2.ZERO, 1.0, bc)
		draw_set_transform(at + fwd * s * 0.05, h, Vector2(s * 0.22, s * 0.22))
		draw_circle(Vector2.ZERO, 1.0, bc.lightened(0.12))
		draw_set_transform(at + fwd * s * 0.32, h, Vector2(s * 0.12, s * 0.12))
		draw_circle(Vector2.ZERO, 1.0, bc)
	draw_set_transform(Vector2.ZERO)
