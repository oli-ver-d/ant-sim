class_name SeedNestRenderer
extends Node2D
## Draws a SeedNest: a pale cleared disc of sand around the entrance, and
## seed husks (chaff) along its edge that grow with seeds delivered. The
## crater itself is drawn by the core EntranceRenderer.

const SAND := Color(0.46, 0.36, 0.24)
const HUSK := Color(0.72, 0.6, 0.38)
## Husks drawn per seed delivered, and the cap.
const HUSKS_PER_SEED := 0.5
const MAX_HUSKS := 500

var nest: SeedNest
var _drawn_seeds: int = -1
var _middens_version: int = -1

func bind(_sim: Simulation, target: Object) -> void:
	nest = target as SeedNest
	position = nest.entrance_position()

func _process(_delta: float) -> void:
	var t := Profiler.start()
	# Redraw in steps so a busy nest doesn't redraw every frame.
	if nest.seeds_received - _drawn_seeds >= 4 or _drawn_seeds < 0 or nest.middens_version != _middens_version:
		_drawn_seeds = nest.seeds_received
		_middens_version = nest.middens_version
		queue_redraw()
	Profiler.stop("SeedNestRenderer._process", t)

func _draw() -> void:
	var t := Profiler.start()
	_draw_body()
	Profiler.stop("SeedNestRenderer._draw", t)

func _draw_body() -> void:
	var r := nest.disc_radius
	# Cleared disc with a soft edge.
	for k in 6:
		var t := float(k) / 5.0
		draw_circle(Vector2.ZERO, r * (1.15 - 0.15 * t), Color(SAND, 0.12 + 0.1 * t))
	# Husks in a band along the disc's edge, like the ring middens of
	# granary nests, spreading round it as they pile up.
	var rng := RandomNumberGenerator.new()
	rng.seed = nest.colony_id * 7919 + 1
	var husks := mini(int(_drawn_seeds * HUSKS_PER_SEED), MAX_HUSKS)
	# Centred on the colony's own midden (where its dead go) once it has one.
	var mid := 0.3
	if not nest.middens.is_empty():
		mid = (nest.middens[0].position - nest.entrance_position()).angle()
	var arc := minf(1.9, 0.35 + float(husks) / 200.0)
	for n in husks:
		# Thicker toward the middle of the arc, ragged at its ends.
		var u := rng.randf() * 2.0 - 1.0
		var a := mid + u * absf(u) * arc
		var p := Vector2.from_angle(a) * r * (1.02 + (0.22 * (1.0 - absf(u)) + 0.05) * (rng.randf() - 0.3))
		draw_set_transform(p, rng.randf() * TAU, Vector2(1.7, 1.0))
		draw_circle(Vector2.ZERO, rng.randf_range(1.0, 1.8), HUSK.darkened(rng.randf() * 0.3))
	draw_set_transform(Vector2.ZERO)
