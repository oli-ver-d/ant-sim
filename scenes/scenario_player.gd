class_name ScenarioPlayer
extends Node2D
## Plays a scenario: builds the simulation, its WorldView and CameraDirector,
## and advances everything by video time. Shared by the interactive scene
## (main.gd) and the recorder (record.gd), so a recording looks exactly like
## the scenario plays interactively.
##
## Speed: the scenario's "ticks_per_frame" schedule says how many sim ticks
## to run per 60 fps video frame (0.5 = real time at 30 ticks/s); values
## between schedule points are ramped linearly so speed-ups are smooth.

const VIDEO_FPS := 60.0
## Default cutaway inset placement (screen pixels): top left, below the top safe zone.
const DEFAULT_CUTAWAY_RECT := [40, 170, 440, 330]

var config: SimConfig = preload("res://sim/default_config.tres")
var registry: Registry
var data: Dictionary
var sim: Simulation
var runner: SimRunner
var view: WorldView
var camera: CameraDirector
## Nest cutaway inset, if the scenario asks for one (or toggled with N).
var cutaway: CutawayPanel
## Split surface/underground layout (render.layout, or toggled with L); null
## until first used, and while unused the world is drawn full screen.
var layout: SplitLayout
var _layout_spec: Dictionary = {"mode": "split", "colony": 0}
## The nest's underground layer view and its camera (layered nests, created
## with the layout).
var nest_view: WorldView
var nest_camera: CameraDirector
## Camera keyframes for the nest view ("camera": {"nest": [...]}).
var _nest_keyframes: Array = []
## "surface" (the world full screen), "split" or "nest".
var _mode: String = "surface"
## Timed layout changes ("render.layout.modes": [{"t": video s, "mode": ...}]).
var _mode_schedule: Array[Dictionary] = []
var _layout_layer: CanvasLayer
var _hud: CanvasLayer
## Video seconds played so far.
var video_time: float = 0.0
## Video length from the scenario ("duration"), in seconds.
var duration: float = 20.0

var _tpf_points: Array[Vector2] = []  # (video time, ticks per frame)

## seed_value < 0 uses the scenario's seed. extra_ticks run after the
## scenario's own warmup, before the first frame. layout_mode ("split" or
## "normal") overrides the scenario's render.layout mode.
func setup(scenario_name: String, seed_value: int = -1, extra_ticks: int = 0,
		debug_readout: RichTextLabel = null, layout_mode: String = "") -> void:
	registry = Registry.create_default()
	CoreRenderers.register(registry)
	data = ScenarioLoader.load_data(scenario_name)
	sim = ScenarioLoader.build(data, registry, config, seed_value)
	duration = float(data.get("duration", 20.0))

	var warmup := int(float(data.get("warmup", 0.0)) * config.tick_rate) + extra_ticks
	for t in warmup:
		sim.step()
	runner = SimRunner.new(sim)

	view = WorldView.new()
	view.setup(sim, registry, float(sim.rng.seed % 100), debug_readout)
	add_child(view)
	var render: Dictionary = data.get("render", {})
	view.pheromone_renderer.visible = bool(render.get("pheromones", true))
	view.pheromone_renderer.opacity = float(render.get("pheromone_opacity", view.pheromone_renderer.opacity))
	# Split layout (under everything else), then a screen-space layer for insets.
	_layout_layer = CanvasLayer.new()
	_layout_layer.layer = -1
	add_child(_layout_layer)
	_hud = CanvasLayer.new()
	add_child(_hud)
	if render.has("cutaway"):
		var c: Dictionary = render["cutaway"]
		_add_cutaway(int(c.get("colony", 0)), ScenarioEvents.rect2(c.get("rect", DEFAULT_CUTAWAY_RECT)))
		if cutaway != null:
			cutaway.from_time = float(c.get("from", -INF))
			cutaway.to_time = float(c.get("to", INF))

	camera = CameraDirector.new()
	add_child(camera)
	var cams: Variant = data.get("camera", [])
	if cams is Dictionary:
		_nest_keyframes = cams.get("nest", [])
		cams = cams.get("surface", [])
	camera.setup(sim, cams)
	camera.make_current()
	if render.has("layout"):
		_layout_spec.merge(render["layout"], true)
	var mode := str(_layout_spec.get("mode", "split")) if render.has("layout") else "normal"
	if layout_mode != "":
		mode = layout_mode
	for m: Dictionary in _layout_spec.get("modes", []):
		_mode_schedule.append(m)
	_mode_schedule.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	if layout_mode == "" and not _mode_schedule.is_empty():
		mode = str(_mode_schedule[0]["mode"])
	else:
		_mode_schedule.clear()
	if mode == "split" or mode == "nest":
		set_mode(mode)

	_parse_tpf(data.get("ticks_per_frame", config.ticks_per_frame))

## Advances video time by `delta` seconds; `speed` multiplies the scenario's
## own ticks-per-frame (interactive speed keys).
func advance(delta: float, speed: float = 1.0) -> void:
	video_time += delta
	_apply_mode_schedule()
	runner.advance(ticks_per_frame_at(video_time) * VIDEO_FPS * delta * speed)
	view.alpha = runner.alpha()
	if cutaway != null:
		cutaway.update_visibility(video_time)
	camera.alpha = runner.alpha()
	camera.update_camera(video_time, delta)
	if nest_view != null and _mode != "surface":
		nest_view.alpha = runner.alpha()
		nest_camera.alpha = runner.alpha()
		nest_camera.update_camera(video_time, delta)

func ticks_per_frame_at(t: float) -> float:
	if _tpf_points.size() == 1 or t <= _tpf_points[0].x:
		return _tpf_points[0].y
	for k in range(1, _tpf_points.size()):
		var b := _tpf_points[k]
		if t < b.x:
			var a := _tpf_points[k - 1]
			return lerpf(a.y, b.y, (t - a.x) / maxf(b.x - a.x, 0.0001))
	return _tpf_points[_tpf_points.size() - 1].y

func _parse_tpf(spec: Variant) -> void:
	_tpf_points.clear()
	if spec is Array:
		for p: Dictionary in spec:
			_tpf_points.append(Vector2(float(p["t"]), float(p["tpf"])))
		_tpf_points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	if _tpf_points.is_empty():
		_tpf_points.append(Vector2(0.0, float(spec) if (spec is float or spec is int) else config.ticks_per_frame))

## Shows or hides colony 0's nest cutaway (interactive toggle).
func toggle_cutaway() -> void:
	if cutaway == null:
		_add_cutaway(0, ScenarioEvents.rect2(DEFAULT_CUTAWAY_RECT))
		return
	var shown := cutaway.visible
	cutaway.from_time = INF if shown else -INF
	cutaway.to_time = INF
	cutaway.update_visibility(video_time)

func _add_cutaway(colony_id: int, rect: Rect2) -> void:
	cutaway = CutawayPanel.create(sim, registry, colony_id, rect)
	if cutaway != null:
		_hud.add_child(cutaway)

## Switches the layout: "surface" (or "normal": the world full screen),
## "split" (surface and nest) or "nest" (the nest full screen, layered nests
## only). Returns false (and stays as it was) if the colony's nest has no
## view to split with, or "nest" isn't possible.
func set_mode(new_mode: String) -> bool:
	if new_mode == "normal":
		new_mode = "surface"
	if new_mode != "surface" and layout == null:
		layout = SplitLayout.create(sim, registry, _layout_spec)
		if layout == null:
			return false
		_layout_layer.add_child(layout)
		if layout.nest_viewport != null:
			_build_nest_view()
	if layout == null:
		return new_mode == "surface"
	if new_mode == "nest" and not layout.has_nest_mode():
		return false
	var split := new_mode != "surface"
	var parent: Node = layout.surface_viewport if split else self
	if view.get_parent() != parent:
		view.reparent(parent, false)
		camera.reparent(parent, false)
		# Keep the world under the insets when drawn full screen.
		if not split:
			move_child(view, 0)
			move_child(camera, 1)
		camera.make_current()
	if split:
		layout.set_mode(new_mode)
	layout.visible = split
	_mode = new_mode
	return true

## The nest's underground layer view and camera, in the layout's nest viewport.
func _build_nest_view() -> void:
	var nest := layout.nest
	nest_view = WorldView.new()
	nest_view.setup(sim, registry, float(sim.rng.seed % 100) + 50.0, null, nest.underground_layer)
	nest_view.pheromone_renderer.visible = false
	layout.nest_viewport.add_child(nest_view)
	nest_camera = CameraDirector.new()
	layout.nest_viewport.add_child(nest_camera)
	var frames := _nest_keyframes if not _nest_keyframes.is_empty() else [{"t": 0, "fit": "excavation", "margin": 80}]
	nest_camera.setup(sim, frames, nest.underground_layer)
	nest_camera.make_current()

## Current layout mode: "surface", "split" or "nest".
func mode() -> String:
	return _mode

## Split layout on or off (off = the surface full screen).
func set_split(on: bool) -> bool:
	return set_mode("split" if on else "surface")

func is_split() -> bool:
	return _mode == "split"

## Interactive toggle (L): surface -> split -> nest (layered nests) -> surface.
func toggle_layout() -> void:
	_mode_schedule.clear()
	match _mode:
		"surface":
			if not set_mode("split"):
				set_mode("nest")
		"split":
			if not set_mode("nest"):
				set_mode("surface")
		_:
			set_mode("surface")

## True if a screen point (1080x1920 frame pixels) shows the world.
func shows_world_at(screen: Vector2) -> bool:
	return _mode == "surface" or (_mode == "split" and layout.is_on_surface(screen))

## World position under a screen point (1080x1920 frame pixels).
func screen_to_world(screen: Vector2) -> Vector2:
	if is_split():
		return layout.screen_to_world(screen)
	return get_viewport().get_canvas_transform().affine_inverse() * screen

## Switches layout mode when the scenario's schedule says so (a --layout
## override or an interactive L press stops the schedule).
func _apply_mode_schedule() -> void:
	if _mode_schedule.is_empty():
		return
	var want := ""
	for m in _mode_schedule:
		if float(m["t"]) <= video_time + 1e-6:
			want = str(m["mode"])
	if want != "" and want != _mode:
		set_mode(want)
