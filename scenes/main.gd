extends Node2D
## Interactive entry point: plays a scenario through ScenarioPlayer (same as
## the recorder, including its camera script and speed schedule) with a HUD,
## overlays and controls.
##
## Command-line (after "--"):
##   --scenario=<name>      scenario in res://scenarios (default basic_forage)
##   --seed=<n>             override the scenario seed
##   --ticks=<n>            run n extra ticks before the first frame
##   --at=<s>               fast-forward to video time s before the first frame
##   --ants=<n>             top each colony up to n ants (stress test)
##   --probe=1              print FPS and simulation cost every 2 s
##   --screenshot=<path>    save a PNG after the first frames, then quit
##   --zoom=<z> --center=<x>,<y>   manual camera (overrides the scenario's)
##   --safe=1 --debug=1 --pheromones=0 --cutaway=1   initial overlay state
##
## Keys: Space pause, P pheromones, D debug overlay, S safe zones, N nest cutaway,
##       F follow the ant under the cursor (again to stop), C scenario camera,
##       1-5 speed (1/2/4/8/16x the scenario's pace),
##       mouse wheel zoom, middle-drag pan, Esc quit.

const SPEEDS: PackedFloat32Array = [1, 2, 4, 8, 16]

var player: ScenarioPlayer
var sim: Simulation
var hud: Label
var debug_readout: RichTextLabel
var safe_zones: Overlays.SafeZones

var paused := false
var speed := 1.0
var _screenshot_path := ""
var _frames_until_shot := -1
## Smoothed milliseconds of simulation work per rendered frame.
var _sim_ms := 0.0

func _ready() -> void:
	var args := _parse_args()

	var layer := CanvasLayer.new()
	add_child(layer)
	debug_readout = RichTextLabel.new()
	debug_readout.bbcode_enabled = true
	debug_readout.fit_content = true
	debug_readout.position = Vector2(24, 190)
	debug_readout.size = Vector2(700, 0)
	debug_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_readout.add_theme_font_size_override("normal_font_size", 24)
	debug_readout.visible = false
	layer.add_child(debug_readout)
	safe_zones = Overlays.SafeZones.new()
	safe_zones.visible = args.has("safe")
	layer.add_child(safe_zones)
	hud = Label.new()
	hud.position = Vector2(24, 24)
	hud.add_theme_font_size_override("font_size", 28)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)

	player = ScenarioPlayer.new()
	add_child(player)
	player.setup(args.get("scenario", "basic_forage"), int(args.get("seed", -1)), int(args.get("ticks", 0)), debug_readout)
	sim = player.sim

	var ants := int(args.get("ants", 0))
	for colony in sim.colonies:
		if ants > colony.population:
			colony.nest.spawn_ants(sim, ants - colony.population)

	# Fast-forward exactly as a recording would play.
	var at := float(args.get("at", 0.0))
	while player.video_time < at - 1e-6:
		player.advance(1.0 / ScenarioPlayer.VIDEO_FPS)

	if args.has("center") or args.has("zoom"):
		var cam := player.camera
		cam.mode = CameraDirector.Mode.MANUAL
		if args.has("center"):
			var c: PackedStringArray = str(args["center"]).split(",")
			cam.position = Vector2(float(c[0]), float(c[1]))
		cam.zoom = Vector2.ONE * float(args.get("zoom", 1.0))

	if args.get("pheromones", "1") == "0":
		player.view.pheromone_renderer.visible = false
	if args.has("debug"):
		_toggle_debug()
	if args.has("cutaway") and player.cutaway == null:
		player.toggle_cutaway()
	if args.has("probe"):
		add_child(load("res://tests/frame_probe.gd").new())

	_screenshot_path = args.get("screenshot", "")
	if _screenshot_path != "":
		paused = true
		hud.visible = args.has("debug")
		_frames_until_shot = 3

func _process(delta: float) -> void:
	if _frames_until_shot >= 0:
		_frames_until_shot -= 1
		if _frames_until_shot < 0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(_screenshot_path)
			print("Saved screenshot %s (%dx%d)" % [_screenshot_path, img.get_width(), img.get_height()])
			get_tree().quit()
		return

	if not paused:
		var t0 := Time.get_ticks_usec()
		player.advance(delta, speed)
		_sim_ms = lerpf(_sim_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	_update_hud()

func _update_hud() -> void:
	var lines: PackedStringArray = []
	lines.append("FPS %d   t %.1fs   sim %.0fs   %.1f ms/frame   x%d%s" % [Engine.get_frames_per_second(),
			player.video_time, sim.time(), _sim_ms, int(speed), "   PAUSED" if paused else ""])
	for colony in sim.colonies:
		lines.append("%s #%d: %d ants, %d delivered" % [colony.species.display_name, colony.id,
				colony.population, colony.delivered_items])
	hud.text = "\n".join(lines)

func _unhandled_input(event: InputEvent) -> void:
	var cam := player.camera
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		match key:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_SPACE:
				paused = not paused
			KEY_P:
				player.view.pheromone_renderer.visible = not player.view.pheromone_renderer.visible
			KEY_D:
				_toggle_debug()
			KEY_S:
				safe_zones.visible = not safe_zones.visible
			KEY_N:
				player.toggle_cutaway()
			KEY_F:
				if cam.mode == CameraDirector.Mode.FOLLOW:
					cam.mode = CameraDirector.Mode.MANUAL
				else:
					var ant := cam.nearest_ant(get_global_mouse_position())
					if ant >= 0:
						cam.follow(ant)
			KEY_C:
				if not cam.keyframes.is_empty():
					cam.mode = CameraDirector.Mode.SCRIPT
			_:
				if key >= KEY_1 and key < KEY_1 + SPEEDS.size():
					speed = SPEEDS[key - KEY_1]
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if cam.mode == CameraDirector.Mode.SCRIPT:
				cam.mode = CameraDirector.Mode.MANUAL
			var factor := 1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
			cam.zoom = (cam.zoom * factor).clamp(Vector2.ONE, Vector2(10, 10))
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		cam.mode = CameraDirector.Mode.MANUAL
		cam.position -= (event as InputEventMouseMotion).relative / cam.zoom

func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv := arg.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out

func _toggle_debug() -> void:
	player.view.debug_view.visible = not player.view.debug_view.visible
	debug_readout.visible = player.view.debug_view.visible
