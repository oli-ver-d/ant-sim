extends Node2D
## Interactive entry point: loads a scenario, runs the simulation on a fixed
## tick and shows it through WorldView.
##
## Command-line (after "--"):
##   --scenario=<name>      scenario in res://scenarios (default basic_forage)
##   --seed=<n>             override the scenario seed
##   --ticks=<n>            run n ticks before the first frame
##   --screenshot=<path>    save a PNG after the first frames, then quit
##
## Keys: Space pause, P pheromones, 1-5 speed (1/2/4/8/16 ticks per frame),
##       mouse wheel zoom, middle-drag pan, Esc quit.

const SPEEDS: PackedInt32Array = [1, 2, 4, 8, 16]
## Cap on ticks per frame so a slow frame can't snowball.
const MAX_TICKS_PER_FRAME := 32

var config: SimConfig = preload("res://sim/default_config.tres")
var registry: Registry
var sim: Simulation
var view: WorldView
var camera: Camera2D
var hud: Label

var paused := false
var speed := 1
var _accumulator := 0.0
var _screenshot_path := ""
var _frames_until_shot := -1
var _last_step_ms := 0.0

func _ready() -> void:
	var args := _parse_args()
	registry = Registry.create_default()
	CoreRenderers.register(registry)
	sim = ScenarioLoader.load_simulation(args.get("scenario", "basic_forage"), registry, config,
			int(args.get("seed", -1)))

	for t in int(args.get("ticks", 0)):
		sim.step()

	view = WorldView.new()
	view.setup(sim, registry)
	add_child(view)

	camera = Camera2D.new()
	camera.position = Vector2(config.world_size) * 0.5
	add_child(camera)
	camera.make_current()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(24, 24)
	hud.add_theme_font_size_override("font_size", 28)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)

	_screenshot_path = args.get("screenshot", "")
	if _screenshot_path != "":
		paused = true
		hud.visible = false
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
		# Fixed-step accumulator: the sim always advances in whole ticks of
		# sim.dt, `speed` times faster than real time.
		_accumulator += delta * speed
		var ticks := 0
		var t0 := Time.get_ticks_usec()
		while _accumulator >= sim.dt and ticks < MAX_TICKS_PER_FRAME:
			sim.step()
			_accumulator -= sim.dt
			ticks += 1
		if ticks == MAX_TICKS_PER_FRAME:
			_accumulator = 0.0
		if ticks > 0:
			_last_step_ms = (Time.get_ticks_usec() - t0) / 1000.0 / ticks
	_update_hud()

func _update_hud() -> void:
	var lines: PackedStringArray = []
	lines.append("FPS %d   tick %d   %.1f ms/tick   x%d%s" % [Engine.get_frames_per_second(),
			sim.tick_count, _last_step_ms, speed, "   PAUSED" if paused else ""])
	for colony in sim.colonies:
		lines.append("%s #%d: %d ants, %d delivered" % [colony.species.display_name, colony.id,
				colony.population, colony.delivered_items])
	hud.text = "\n".join(lines)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		match key:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_SPACE:
				paused = not paused
			KEY_P:
				view.pheromone_renderer.visible = not view.pheromone_renderer.visible
			_:
				if key >= KEY_1 and key < KEY_1 + SPEEDS.size():
					speed = SPEEDS[key - KEY_1]
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.5, 0.5), Vector2(8, 8))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.1).clamp(Vector2(0.5, 0.5), Vector2(8, 8))
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		camera.position -= (event as InputEventMouseMotion).relative / camera.zoom

func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv := arg.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out
