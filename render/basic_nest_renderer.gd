class_name BasicNestRenderer
extends Node2D
## Renderer for BasicNest. The hole, its rim and worn apron are drawn by the
## core EntranceRenderer ("hole" style by default); a basic nest has nothing
## else to show.

var nest: NestType

func bind(_sim: Simulation, target: Object) -> void:
	nest = target as NestType
	position = nest.entrance_position()
