class_name BasicNestRenderer
extends Node2D
## Renderer for BasicNest: a dark entrance hole ringed by excavated soil.

var nest: NestType

func bind(_sim: Simulation, target: Object) -> void:
	nest = target as NestType
	position = nest.entrance_position()

func _draw() -> void:
	var r := nest.radius
	draw_circle(Vector2.ZERO, r * 2.2, Color(0.3, 0.21, 0.13))
	draw_circle(Vector2.ZERO, r * 1.5, Color(0.22, 0.15, 0.09))
	draw_circle(Vector2.ZERO, r, Color(0.05, 0.03, 0.02))
