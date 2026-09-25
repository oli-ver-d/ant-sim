class_name SeedNestRenderer
extends Node2D
## Draws a SeedNest: a pale cleared disc of sand around the entrance, and a
## pile of seed husks (chaff) beside it that grows with seeds delivered. The
## crater itself is drawn by the core EntranceRenderer.

const SAND := Color(0.46, 0.36, 0.24)
const HUSK := Color(0.72, 0.6, 0.38)
## Husks drawn per seed delivered, and the cap.
const HUSKS_PER_SEED := 0.5
const MAX_HUSKS := 500

var nest: SeedNest
var _drawn_seeds: int = -1

func bind(_sim: Simulation, target: Object) -> void:
	nest = target as SeedNest
	position = nest.entrance_position()

func _process(_delta: float) -> void:
	# Redraw in steps so a busy nest doesn't redraw every frame.
	if nest.seeds_received - _drawn_seeds >= 4 or _drawn_seeds < 0:
		_drawn_seeds = nest.seeds_received
		queue_redraw()

func _draw() -> void:
	var r := nest.disc_radius
	# Cleared disc with a soft edge.
	for k in 6:
		var t := float(k) / 5.0
		draw_circle(Vector2.ZERO, r * (1.15 - 0.15 * t), Color(SAND, 0.12 + 0.1 * t))
	# Husk midden to one side, spreading as it grows.
	var rng := RandomNumberGenerator.new()
	rng.seed = nest.colony_id * 7919 + 1
	var husks := mini(int(_drawn_seeds * HUSKS_PER_SEED), MAX_HUSKS)
	var midden := Vector2(r * 0.8, r * 0.25)
	var spread := 6.0 + sqrt(float(husks)) * 1.6
	for n in husks:
		var p := midden + Vector2.from_angle(rng.randf() * TAU) * spread * sqrt(rng.randf())
		draw_set_transform(p, rng.randf() * TAU, Vector2(1.7, 1.0))
		draw_circle(Vector2.ZERO, rng.randf_range(1.0, 1.8), HUSK.darkened(rng.randf() * 0.3))
	draw_set_transform(Vector2.ZERO)
