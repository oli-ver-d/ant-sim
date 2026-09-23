extends Node2D
## Interactive entry point. M0 placeholder: draws the empty world so the
## project runs; the simulation and renderers are wired in from M1.

var config: SimConfig = preload("res://sim/default_config.tres")

func _draw() -> void:
	var world := Rect2(Vector2.ZERO, Vector2(config.world_size))
	draw_rect(world, Color(0.16, 0.11, 0.07))
	draw_string(ThemeDB.fallback_font, Vector2(40, 100), "Ant Colony Simulator - M0 scaffold",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(0.9, 0.85, 0.75))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
