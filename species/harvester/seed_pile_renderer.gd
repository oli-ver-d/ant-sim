class_name SeedPileRenderer
extends Node2D
## Draws each remaining seed of a SeedPile as a small shaded ellipse with a
## contact shadow. Redraws only when a seed is taken.

var pile: SeedPile
var _version: int = -1

func bind(_sim: Simulation, target: Object) -> void:
	pile = target as SeedPile

func _process(_delta: float) -> void:
	if pile.version != _version:
		_version = pile.version
		queue_redraw()

func _draw() -> void:
	var elongation := Vector2(1.6, 1.0)
	for s in pile.seed_pos.size():
		if pile.seed_alive[s] == 0:
			continue
		var r := pile.seed_size * pile.seed_scale[s]
		var c := pile.seed_color[s]
		draw_set_transform(pile.seed_pos[s] + Vector2(0.8, 1.2), pile.seed_rot[s], elongation)
		draw_circle(Vector2.ZERO, r, Color(0, 0, 0, 0.35))
		draw_set_transform(pile.seed_pos[s], pile.seed_rot[s], elongation)
		draw_circle(Vector2.ZERO, r, c.darkened(0.2))
		draw_circle(Vector2(-0.15, -0.2) * r, r * 0.7, c)
		draw_circle(Vector2(-0.35, -0.35) * r, r * 0.25, c.lightened(0.4))
	draw_set_transform(Vector2.ZERO)
