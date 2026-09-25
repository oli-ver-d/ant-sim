class_name GranaryNestRenderer
extends Node2D
## Draws a GranaryNest on the surface: the pale disc harvesters clear around
## their entrance (wider as the colony grows, a smaller one round each extra
## entrance) and the midden beside it, a pile of seed husks that grows with
## every load of chaff carried out. Nothing shows while the founding nest is
## sealed. The entrances and spoil heaps are drawn by the core.

const SAND := Color(0.46, 0.36, 0.24)
const HUSK := Color(0.8, 0.74, 0.58)
## Husks drawn per load dumped, and the cap.
const HUSKS_PER_LOAD := 3
const MAX_HUSKS := 1500

var sim: Simulation
var nest: GranaryNest
var _drawn_loads: int = -1
var _drawn_open: int = -1
var _drawn_size: int = -1
var _midden: Node2D

func bind(simulation: Simulation, target: Object) -> void:
	sim = simulation
	nest = target as GranaryNest
	_midden = Node2D.new()
	_midden.draw.connect(_draw_midden)
	add_child(_midden)

func _process(_delta: float) -> void:
	var open := nest.entrances().size() if nest.has_entrance() else 0
	# The disc widens in steps as the colony grows.
	var size := int(sqrt(sim.colonies[nest.colony_id].total_population()))
	if open != _drawn_open or size != _drawn_size:
		_drawn_open = open
		_drawn_size = size
		queue_redraw()
	if nest.dumped_items - _drawn_loads >= 2 or (_drawn_loads < 0 and nest.dumped_items > 0):
		_drawn_loads = nest.dumped_items
		_midden.queue_redraw()

func _draw() -> void:
	if _drawn_open <= 0:
		return
	var main := nest.entrance_position()
	var r := nest.cleared_radius(sim)
	for e in nest.entrances():
		var er := r if e == main else r * 0.55
		# Cleared ground with a soft edge.
		for k in 6:
			var t := float(k) / 5.0
			draw_circle(e, er * (1.15 - 0.15 * t), Color(SAND, 0.1 + 0.08 * t))

func _draw_midden() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = nest.colony_id * 7919 + 1
	var husks := mini(_drawn_loads * HUSKS_PER_LOAD, MAX_HUSKS)
	var at := nest.dump_position()
	var spread := 7.0 + sqrt(float(husks)) * 1.7
	for n in husks:
		var p := at + Vector2.from_angle(rng.randf() * TAU) * spread * sqrt(rng.randf())
		_midden.draw_set_transform(p, rng.randf() * TAU, Vector2(2.6, 0.6))
		_midden.draw_circle(Vector2.ZERO, rng.randf_range(0.8, 1.3), Color(HUSK.darkened(rng.randf() * 0.25), 0.8))
	_midden.draw_set_transform(Vector2.ZERO)
