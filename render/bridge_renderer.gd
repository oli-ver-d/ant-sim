class_name BridgeRenderer
extends Node2D
## Draws the world's bridges (World.bridges) as big twigs lying across the
## obstacle, one per polyline segment, with a drop shadow on the water below.
## The twig overhangs the walkable strip at both ends and tapers toward its
## tip, so it's sized to cover the strip everywhere.

## World units each twig extends past the ends of its segment.
const OVERHANG := 12.0
const SHADOW_OFFSET := Vector2(3.0, 5.0)
const SHADOW := Color(0, 0, 0, 0.35)

var sim: Simulation
var _drawn: int = -1
var _twigs: Array[Dictionary] = []  # {"texture", "at", "rot", "size"}

func bind(simulation: Simulation) -> void:
	sim = simulation

func _process(_delta: float) -> void:
	if sim == null or sim.world.bridges.size() == _drawn:
		return
	_drawn = sim.world.bridges.size()
	# Twig looks come from their own RNG: rendering must never touch sim.rng.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_twigs.clear()
	for bridge in sim.world.bridges:
		var pts: PackedVector2Array = bridge["points"]
		var width := float(bridge["width"])
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var length := a.distance_to(b) + OVERHANG * 2.0
			# The twig tapers to 65% at its tip: keep the tip as wide as the strip.
			var img := Debris.twig_image(length, width * 0.5 / 0.65, rng)
			_twigs.append({
				"texture": ImageTexture.create_from_image(img),
				"at": (a + b) * 0.5,
				"rot": (b - a).angle(),
				"size": Vector2(img.get_size()) / Debris.RES,
			})
	queue_redraw()

func _draw() -> void:
	for twig in _twigs:
		var size: Vector2 = twig["size"]
		var rect := Rect2(-size * 0.5, size)
		draw_set_transform(twig["at"] + SHADOW_OFFSET, twig["rot"])
		draw_texture_rect(twig["texture"], rect, false, SHADOW)
		draw_set_transform(twig["at"], twig["rot"])
		draw_texture_rect(twig["texture"], rect, false)
	draw_set_transform(Vector2.ZERO)
