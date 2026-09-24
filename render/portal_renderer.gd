class_name PortalRenderer
extends Node2D
## Draws the ends of portals that come out on an underground layer: the
## bottom of a shaft, seen from above. Open, daylight falls down it onto the
## floor (a soft warm pool fading out over the floor, with a ring of packed
## earth around the hole); closed, it is a plug of loose soil. The surface
## end is drawn by the nest's renderer.

const LIGHT := Color(1.0, 0.92, 0.72, 0.55)
const RIM := Color(0.18, 0.12, 0.07, 0.45)
const PLUG := Color(0.33, 0.23, 0.14)

var sim: Simulation
var layer: int = 1
var _open: PackedByteArray = []
var _glow: GradientTexture2D

func bind(simulation: Simulation, on_layer: int) -> void:
	sim = simulation
	layer = on_layer
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.75))
	g.add_point(0.7, Color(1, 1, 1, 0.18))
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 128
	_glow.height = 128

func _process(_delta: float) -> void:
	var state := PackedByteArray()
	for p in sim.portals:
		state.append(1 if p.open else 0)
	if state != _open:
		_open = state
		queue_redraw()

func _draw() -> void:
	for p in sim.portals:
		if p.layer_b != layer:
			continue
		var at := p.pos_b
		var r := p.radius
		if p.open:
			draw_arc(at, r * 0.95, 0.0, TAU, 40, RIM, r * 0.25, true)
			# Daylight from above: brightest under the hole, spilling over the floor.
			var s := r * 3.2
			draw_texture_rect(_glow, Rect2(at - Vector2(s, s), Vector2(s, s) * 2.0), false, LIGHT)
		else:
			var rng := RandomNumberGenerator.new()
			rng.seed = p.id * 7919 + 17
			draw_circle(at, r * 0.95, PLUG)
			for n in 26:
				var q := at + Vector2.from_angle(rng.randf() * TAU) * r * 0.85 * sqrt(rng.randf())
				var cr := rng.randf_range(0.7, 1.6)
				draw_circle(q + Vector2(0.4, 0.6), cr, Color(0, 0, 0, 0.25))
				draw_circle(q, cr, PLUG.lightened(rng.randf() * 0.3))
