class_name Overlays
extends RefCounted
## Factory for the toggleable overlays. Both are hidden by default.

## TikTok / Reels UI safe zones on the 1080x1920 output frame: areas covered
## by the app's UI (top bar, caption and buttons at the bottom, action column
## on the right). Keep important action out of the shaded areas.
class SafeZones extends Control:
	const FRAME := Vector2(1080, 1920)
	const TOP := 150.0
	const BOTTOM := 400.0
	const RIGHT := 120.0
	const SHADE := Color(1.0, 0.2, 0.25, 0.22)
	const LINE := Color(1.0, 0.35, 0.4, 0.9)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = FRAME

	func _draw() -> void:
		var top := Rect2(0, 0, FRAME.x, TOP)
		var bottom := Rect2(0, FRAME.y - BOTTOM, FRAME.x, BOTTOM)
		var right := Rect2(FRAME.x - RIGHT, TOP, RIGHT, FRAME.y - TOP - BOTTOM)
		var font := ThemeDB.fallback_font
		for r: Rect2 in [top, bottom, right]:
			draw_rect(r, SHADE)
		draw_rect(Rect2(0, TOP, FRAME.x - RIGHT, FRAME.y - TOP - BOTTOM), LINE, false, 3.0)
		draw_string(font, Vector2(24, TOP - 24), "top UI %d px" % TOP, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, LINE)
		draw_string(font, Vector2(24, FRAME.y - BOTTOM + 48), "caption / buttons %d px" % BOTTOM, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, LINE)
		draw_string(font, Vector2(FRAME.x - RIGHT + 8, TOP + 48), "%d px" % RIGHT, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, LINE)

## Debug view in world space: every ant as a dot coloured by behaviour state;
## for ants near the mouse, their three pheromone sensors and heading; and a
## text readout of each channel's value under the cursor.
class DebugView extends Node2D:
	## Ants within this distance of the mouse show their sensors.
	const SENSOR_RADIUS := 60.0
	var sim: Simulation
	var readout: RichTextLabel
	## Returns the world position under the mouse; set it when the world is
	## drawn in a SubViewport (split layout). Unset: the mouse in this canvas.
	var mouse_world: Callable
	var _state_colors: PackedColorArray = []

	func bind(simulation: Simulation, label: RichTextLabel) -> void:
		sim = simulation
		readout = label
		for s in sim.behaviour_ids.size():
			_state_colors.append(Color.from_hsv(float(s) / sim.behaviour_ids.size(), 0.8, 1.0))

	func _process(_delta: float) -> void:
		if visible:
			queue_redraw()
			_update_readout()

	func _mouse() -> Vector2:
		return mouse_world.call() if mouse_world.is_valid() else get_global_mouse_position()

	func _draw() -> void:
		var mouse := _mouse()
		var font := ThemeDB.fallback_font
		for i in sim.high_water:
			if sim.alive[i] == 0:
				continue
			var p := sim.shown_pos[i]
			draw_circle(p, 2.0, _state_colors[sim.state[i]])
			if p.distance_to(mouse) < SENSOR_RADIUS:
				var colony := sim.colony_of(i)
				var h := sim.shown_heading[i]
				for a: float in [-colony.sensor_angle, 0.0, colony.sensor_angle]:
					var s := p + Vector2.from_angle(h + a) * colony.sensor_distance
					draw_line(p, s, Color(1, 1, 1, 0.5), 1.0)
					draw_circle(s, 1.5, Color.WHITE)
				draw_string(font, p + Vector2(6, -6), sim.state_id(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	func _update_readout() -> void:
		var mouse := _mouse()
		var lines: PackedStringArray = ["cursor (%d, %d)" % [mouse.x, mouse.y]]
		for c in sim.pheromones.channel_count():
			lines.append("%s: %.3f" % [sim.pheromones.names[c], sim.pheromones.sample(c, mouse)])
		for s in sim.behaviour_ids.size():
			lines.append("[color=#%s]●[/color] %s" % [_state_colors[s].to_html(false), sim.behaviour_ids[s]])
		readout.text = "\n".join(lines)
