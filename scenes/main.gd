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
##   --safe=1 --debug=1 --pheromones=0 --cutaway=1 --tuning=1   initial overlay state
##   --layout=split|normal|nest  split surface/underground view, the surface full
##                          screen, or the nest's underground full screen
##                          (overrides the scenario's render.layout)
##
## Keys: Space pause, P pheromones, D debug overlay, S safe zones, N nest cutaway,
##       L cycles surface / split / nest (underground full screen) layouts,
##       T tuning panel, F follow the ant under the cursor (again to stop),
##       C scenario camera, 1-5 speed (1/2/4/8/16x the scenario's pace), Esc quit.
## Mouse: left-drag draws walls (Shift+left-drag erases), right-click places
##       the food type selected in the tuning panel, wheel zooms, middle-drag pans.

const SPEEDS: PackedFloat32Array = [1, 2, 4, 8, 16]

var player: ScenarioPlayer
var sim: Simulation
var hud: Label
var debug_readout: RichTextLabel
var safe_zones: Overlays.SafeZones
var tuning: TuningPanel

var paused := false
var speed := 1.0
var _screenshot_path := ""
var _frames_until_shot := -1
## Smoothed milliseconds of simulation work per rendered frame.
var _sim_ms := 0.0
## Wall drawing: last stamped point while the left button is held.
var _drawing := false
var _draw_last := Vector2.ZERO
var _food_rng := RandomNumberGenerator.new()
## Per colony: deliveries at the start of each of the last 60 sim seconds.
var _delivery_history: Array[PackedInt32Array] = []
var _history_second := -1

const WALL_WIDTH := 16.0
## Longest stretch of time one interactive frame may advance (seconds).
const MAX_FRAME_ADVANCE := 1.0 / 30.0

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
	player.setup(args.get("scenario", "basic_forage"), int(args.get("seed", -1)), int(args.get("ticks", 0)),
			debug_readout, str(args.get("layout", "")))
	sim = player.sim
	player.view.debug_view.mouse_world = _mouse_world

	tuning = TuningPanel.new()
	tuning.setup(sim, player.registry)
	tuning.position = Vector2(1080 - TuningPanel.WIDTH - 16, 170)
	tuning.size = Vector2(TuningPanel.WIDTH, 1920 - 170 - 420)
	tuning.visible = false
	layer.add_child(tuning)
	_food_rng.randomize()

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
	if args.has("tuning"):
		tuning.visible = true
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
		# Advance at most two frames' worth: if a frame runs long (a heavy
		# scene, a hitch), the sim slows down instead of asking for ever more
		# ticks per frame and spiralling. Recordings always advance 1/60 s.
		player.advance(minf(delta, MAX_FRAME_ADVANCE), speed)
		_sim_ms = lerpf(_sim_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	_update_hud()

func _update_hud() -> void:
	var lines: PackedStringArray = []
	lines.append("FPS %d   t %.1fs   sim %.0fs   %.1f ms/frame   x%d%s" % [Engine.get_frames_per_second(),
			player.video_time, sim.time(), _sim_ms, int(speed), "   PAUSED" if paused else ""])
	_sample_deliveries()
	for colony in sim.colonies:
		var history := _delivery_history[colony.id]
		var per_min := colony.delivered_items - history[0] if history.size() > 0 else 0
		var simulated := "" if colony.abstract == 0 else " (%d simulated)" % colony.population
		lines.append("%s #%d: %d ants%s, %d delivered (%d/min)" % [colony.species.display_name, colony.id,
				colony.total_population(), simulated, colony.delivered_items, per_min])
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
			KEY_L:
				player.toggle_layout()
			KEY_T:
				tuning.visible = not tuning.visible
			KEY_F:
				if cam.mode == CameraDirector.Mode.FOLLOW:
					cam.mode = CameraDirector.Mode.MANUAL
				elif player.shows_world_at(get_viewport().get_mouse_position()):
					var ant := cam.nearest_ant(_mouse_world())
					if ant >= 0:
						cam.follow(ant)
			KEY_C:
				if not cam.keyframes.is_empty():
					cam.mode = CameraDirector.Mode.SCRIPT
			_:
				if key >= KEY_1 and key < KEY_1 + SPEEDS.size():
					speed = SPEEDS[key - KEY_1]
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# In the split layout the mouse only acts on the surface part.
		if mb.pressed and not player.shows_world_at(mb.position):
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drawing = mb.pressed
			if mb.pressed:
				_draw_last = _world_at(mb.position)
				_stamp_wall(_draw_last, _draw_last, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_place_food(_world_at(mb.position))
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if cam.mode == CameraDirector.Mode.SCRIPT:
				cam.mode = CameraDirector.Mode.MANUAL
			var factor := 1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
			cam.zoom = (cam.zoom * factor).clamp(Vector2.ONE, Vector2(10, 10))
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		cam.mode = CameraDirector.Mode.MANUAL
		cam.position -= (event as InputEventMouseMotion).relative / cam.zoom
	elif event is InputEventMouseMotion and _drawing:
		var at := _world_at((event as InputEventMouseMotion).position)
		_stamp_wall(_draw_last, at, (event as InputEventMouseMotion).shift_pressed)
		_draw_last = at

## World position under a point in viewport coordinates (as mouse events give),
## on whichever part of the screen shows the world.
func _world_at(screen: Vector2) -> Vector2:
	return player.screen_to_world(screen)

func _mouse_world() -> Vector2:
	return _world_at(get_viewport().get_mouse_position())

## Left-drag: draws a wall segment (or erases with Shift). Ants caught under a
## new wall are moved out, so none ever ends up inside an obstacle.
func _stamp_wall(a: Vector2, b: Vector2, erase: bool) -> void:
	var kind := World.Cell.FREE if erase else World.Cell.WALL
	sim.world.draw_polyline(PackedVector2Array([a, b]), WALL_WIDTH, kind)
	if not erase:
		sim.evict_ants_from_obstacles()

## Right-click: places the tuning panel's selected food type (default
## parameters, random rotation and shape seed) under the cursor.
func _place_food(at: Vector2) -> void:
	if tuning.food_type == "" or sim.world.is_blocked(at):
		return
	sim.add_food_source(tuning.food_type, {"pos": [at.x, at.y],
			"rotation": _food_rng.randf_range(0.0, 360.0), "seed": _food_rng.randi()})

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

## Records each colony's delivery count once per simulated second, keeping
## the last 60, for the "per minute" rate in the HUD.
func _sample_deliveries() -> void:
	while _delivery_history.size() < sim.colonies.size():
		_delivery_history.append(PackedInt32Array())
	var second := int(sim.time())
	if second == _history_second:
		return
	_history_second = second
	for colony in sim.colonies:
		var history := _delivery_history[colony.id]
		history.append(colony.delivered_items)
		if history.size() > 60:
			history.remove_at(0)
		_delivery_history[colony.id] = history
