class_name GranaryNestRenderer
extends Node2D
## Draws a GranaryNest on the surface: the pale disc harvesters clear around
## their entrance (wider as the colony grows, a smaller one round each extra
## entrance). Nothing shows while the founding nest is sealed. The entrances
## and spoil heaps are drawn by the core, and so is the midden of husks at the
## disc's edge (MiddenRenderer).

const SAND := Color(0.46, 0.36, 0.24)

var sim: Simulation
var nest: GranaryNest
var _drawn_open: int = -1
var _drawn_size: int = -1

func bind(simulation: Simulation, target: Object) -> void:
	sim = simulation
	nest = target as GranaryNest

func _process(_delta: float) -> void:
	var open := nest.entrances().size() if nest.has_entrance() else 0
	# The disc widens in steps as the colony grows.
	var size := int(sqrt(sim.colonies[nest.colony_id].total_population()))
	if open != _drawn_open or size != _drawn_size:
		_drawn_open = open
		_drawn_size = size
		queue_redraw()

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
