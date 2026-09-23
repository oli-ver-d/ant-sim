class_name FungusNestRenderer
extends Node2D
## Draws a FungusNest on the surface: a mound of excavated soil around the
## entrance that grows with every chamber dug, and the waste dump beside it,
## a grey-brown pile of spent substrate that grows with every load dumped.

const SOIL := Color(0.36, 0.26, 0.17)
const WASTE := Color(0.4, 0.37, 0.31)
## Clumps drawn per load dumped, and the cap.
const CLUMPS_PER_LOAD := 1.0
const MAX_CLUMPS := 900

var nest: FungusNest
var _drawn_loads: int = -1
var _drawn_chambers: int = -1

func bind(_sim: Simulation, target: Object) -> void:
	nest = target as FungusNest
	position = nest.entrance_position()

func _process(_delta: float) -> void:
	# Redraw in steps so a busy dump doesn't redraw every frame.
	if nest.dumped_items - _drawn_loads >= 3 or nest.chambers != _drawn_chambers:
		_drawn_loads = nest.dumped_items
		_drawn_chambers = nest.chambers
		queue_redraw()

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = nest.colony_id * 7919 + 3
	# Excavated soil: loose crumbs heaped around the entrance, more per chamber.
	var mound := nest.radius * (2.2 + 0.5 * nest.chambers)
	for k in 5:
		var t := float(k) / 4.0
		draw_circle(Vector2.ZERO, mound * (1.2 - 0.35 * t), Color(SOIL, 0.1 + 0.08 * t))
	for n in 60 + 40 * nest.chambers:
		var p := Vector2.from_angle(rng.randf() * TAU) * mound * (0.35 + 0.75 * sqrt(rng.randf()))
		var r := rng.randf_range(0.8, 2.0)
		# Lit from the top-left like everything else: a shadow, then the crumb.
		draw_circle(p + Vector2(0.4, 0.6), r, Color(0, 0, 0, 0.25))
		draw_circle(p, r, SOIL.lightened(rng.randf() * 0.25))

	# Waste dump: clumps scattered around the dump point, spreading as it grows.
	# (Own RNG so the pile doesn't reshuffle when the mound grows.)
	rng.seed = nest.colony_id * 7919 + 11
	var dump := nest.dump_offset
	var clumps := mini(int(_drawn_loads * CLUMPS_PER_LOAD), MAX_CLUMPS)
	for n in clumps:
		# Clump n lands within a radius that grows with n, so earlier clumps
		# stay put and the pile spreads by accretion.
		var spread := 5.0 + sqrt(float(n)) * 1.3
		var p := dump + Vector2.from_angle(rng.randf() * TAU) * spread * sqrt(rng.randf())
		var r := rng.randf_range(1.2, 2.2)
		draw_circle(p + Vector2(0.5, 0.7), r, Color(0, 0, 0, 0.22))
		draw_circle(p, r, WASTE.darkened(rng.randf() * 0.35).lerp(Color(0.5, 0.46, 0.36), rng.randf() * 0.3))

	# Entrance: a dark crater.
	draw_circle(Vector2.ZERO, nest.radius * 1.5, SOIL.darkened(0.35))
	draw_circle(Vector2.ZERO, nest.radius, Color(0.05, 0.03, 0.02))
