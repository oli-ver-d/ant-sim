class_name FoodPileRenderer
extends Node2D
## Renderer for the generic FoodPile: a mound of crumbs that shrinks as it's
## taken. Redraws only when the source's version changes.

var source: FoodPile
var _version: int = -1

func bind(_sim: Simulation, target: Object) -> void:
	source = target as FoodPile
	position = source.position

func _process(_delta: float) -> void:
	if source.version != _version:
		_version = source.version
		queue_redraw()

func _draw() -> void:
	var r := source.current_radius()
	if r <= 0.5:
		return
	draw_circle(Vector2.ZERO, r * 1.1, source.color.darkened(0.45))
	draw_circle(Vector2.ZERO, r, source.color)
	# Crumb speckles from a fixed seed so they don't flicker between redraws.
	var rng := RandomNumberGenerator.new()
	rng.seed = source.id
	for n in int(r * 1.5):
		var p := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r * 0.9
		draw_circle(p, rng.randf_range(0.8, 1.8), source.color.lightened(rng.randf_range(0.1, 0.35)))
