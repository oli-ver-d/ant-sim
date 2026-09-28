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
## A point may add "jump": sim seconds run all at once in the first frame at
## or after its time ({"t": 40, "tpf": 0.5, "jump": 120}), for time skips
## hidden under a fade; the cameras then snap to their targets.
##
## Camera stories (see CameraDirector): both cameras share one `story`, so
## {"ant": "same"} on the nest camera continues what the surface camera
## followed. An "across" follow's ant is handed each frame to the camera of
## the part that shows its layer (_update_across), and with "switch_mode"
## the layout mode changes when its layer isn't shown: to "nest" when it goes
## underground from "surface", to "surface" when it comes up from "nest".
## The mode then stays until the next render.layout.modes point.

const VIDEO_FPS := 60.0

var config: SimConfig = preload("res://sim/default_config.tres")
var registry: Registry
var data: Dictionary
var sim: Simulation
var runner: SimRunner
var view: WorldView
var camera: CameraDirector
## Split surface/underground layout (render.layout, or toggled with L); null
## until first used, and while unused the world is drawn full screen.
var layout: SplitLayout
var _layout_spec: Dictionary = {"mode": "split", "colony": 0}
## The nest's underground layer view and its camera (created with the layout).
var nest_view: WorldView
var nest_camera: CameraDirector
## Camera keyframes for the nest view ("camera": {"nest": [...]}).
var _nest_keyframes: Array = []
## "surface" (the world full screen), "split" or "nest".
var _mode: String = "surface"
## Timed layout changes ("render.layout.modes": [{"t": video s, "mode": ...}]).
var _mode_schedule: Array[Dictionary] = []
var _layout_layer: CanvasLayer
## Captions, fades and colour grade (render.captions/fades/grade), or null.
var presentation: Presentation
## Rings on the story target (render.story_marker), one per camera.
var markers: Array[StoryMarker] = []
var _marker_windows: Array[Vector3] = []
## Video seconds played so far.
var video_time: float = 0.0
## Video length from the scenario ("duration"), in seconds.
var duration: float = 20.0

var _tpf_points: Array[Vector2] = []  # (video time, ticks per frame)
## Time jumps (video time, sim seconds), sorted, and how many have been made.
var _jumps: Array[Vector2] = []
var _jumps_done: int = 0
## Index of the render.layout.modes point applied last.
var _mode_point: int = -1

## seed_value < 0 uses the scenario's seed. extra_ticks run after the
## scenario's own warmup, before the first frame. layout_mode ("split" or
## "normal") overrides the scenario's render.layout mode.
func setup(scenario_name: String, seed_value: int = -1, extra_ticks: int = 0,
		debug_readout: RichTextLabel = null, layout_mode: String = "") -> void:
	setup_data(ScenarioLoader.load_data(scenario_name), seed_value, extra_ticks, debug_readout, layout_mode)

## setup() from scenario data already loaded (or built in code, e.g. tests).
func setup_data(scenario: Dictionary, seed_value: int = -1, extra_ticks: int = 0,
		debug_readout: RichTextLabel = null, layout_mode: String = "") -> void:
	registry = Registry.create_default()
	CoreRenderers.register(registry)
	data = scenario
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
	# Split layout, under everything else.
	_layout_layer = CanvasLayer.new()
	_layout_layer.layer = -1
	add_child(_layout_layer)

	camera = CameraDirector.new()
	add_child(camera)
	var cams: Variant = data.get("camera", [])
	if cams is Dictionary:
		_nest_keyframes = cams.get("nest", [])
		cams = cams.get("surface", [])
	camera.setup(sim, cams)
	camera.make_current()
	_marker_windows = StoryMarker.parse(render.get("story_marker", []))
	_add_marker(view, camera)
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
	if Presentation.wanted(render):
		presentation = Presentation.new()
		presentation.setup(render)
		add_child(presentation)

## Advances video time by `delta` seconds; `speed` multiplies the scenario's
## own ticks-per-frame (interactive speed keys).
func advance(delta: float, speed: float = 1.0) -> void:
	video_time += delta
	_apply_mode_schedule()
	var jump := 0.0
	while _jumps_done < _jumps.size() and _jumps[_jumps_done].x <= video_time + 1e-6:
		jump += _jumps[_jumps_done].y
		_jumps_done += 1
	runner.advance(ticks_per_frame_at(video_time) * VIDEO_FPS * delta * speed + jump * config.tick_rate)
	view.alpha = runner.alpha()
	camera.alpha = runner.alpha()
	if nest_view != null:
		nest_view.alpha = runner.alpha()
		nest_camera.alpha = runner.alpha()
	_update_across()
	camera.update_camera(video_time, delta)
	if nest_view != null and _mode != "surface":
		nest_camera.update_camera(video_time, delta)
	if jump > 0.0:
		camera.snap()
		if nest_camera != null:
			nest_camera.snap()
			nest_camera.update_camera(video_time, 0.0)
		camera.update_camera(video_time, 0.0)
	for m in markers:
		m.video_time = video_time
	if presentation != null:
		presentation.update(video_time)

## A StoryMarker for `cam`, drawn on top of `world_view` (if the scenario
## has story_marker windows).
func _add_marker(world_view: WorldView, cam: CameraDirector) -> void:
	if _marker_windows.is_empty():
		return
	var m := StoryMarker.new()
	m.camera = cam
	m.windows = _marker_windows
	m.video_time = video_time
	world_view.add_child(m)
	markers.append(m)

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
	_jumps.clear()
	_jumps_done = 0
	if spec is Array:
		for p: Dictionary in spec:
			if p.has("tpf"):
				_tpf_points.append(Vector2(float(p["t"]), float(p["tpf"])))
			if float(p.get("jump", 0.0)) > 0.0:
				_jumps.append(Vector2(float(p["t"]), float(p["jump"])))
		_tpf_points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		_jumps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	if _tpf_points.is_empty():
		_tpf_points.append(Vector2(0.0, float(spec) if (spec is float or spec is int) else config.ticks_per_frame))

## Switches the layout: "surface" (or "normal": the world full screen),
## "split" (surface and nest) or "nest" (the nest full screen). Returns
## false (and stays as it was) if the colony's nest has no underground layer.
func set_mode(new_mode: String) -> bool:
	if new_mode == "normal":
		new_mode = "surface"
	if new_mode != "surface" and layout == null:
		layout = SplitLayout.create(sim, _layout_spec)
		if layout == null:
			return false
		_layout_layer.add_child(layout)
		_build_nest_view()
	if layout == null:
		return new_mode == "surface"
	var split := new_mode != "surface"
	var parent: Node = layout.surface_viewport if split else self
	if view.get_parent() != parent:
		view.reparent(parent, false)
		camera.reparent(parent, false)
		# Back to where setup() put them, first in draw order.
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
	nest_camera.story = camera.story
	nest_camera.alpha = runner.alpha() if runner != null else 1.0
	nest_camera.make_current()
	_add_marker(nest_view, nest_camera)

## Current layout mode: "surface", "split" or "nest".
func mode() -> String:
	return _mode

## Split layout on or off (off = the surface full screen).
func set_split(on: bool) -> bool:
	return set_mode("split" if on else "surface")

func is_split() -> bool:
	return _mode == "split"

## Interactive toggle (L): surface -> split -> nest -> surface (nests with
## an underground layer only).
func toggle_layout() -> void:
	_mode_schedule.clear()
	match _mode:
		"surface":
			set_mode("split")
		"split":
			set_mode("nest")
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
	var point := -1
	for n in _mode_schedule.size():
		if float(_mode_schedule[n]["t"]) <= video_time + 1e-6:
			point = n
	# Only when a new point is reached, so an "across" follow's switch holds.
	if point < 0 or point == _mode_point:
		return
	_mode_point = point
	var want := str(_mode_schedule[point]["mode"])
	if want != _mode:
		set_mode(want)

## The layer of the nest shown in the layout's nest part (-1 if none).
func nest_layer() -> int:
	var c := int(_layout_spec.get("colony", 0))
	if c < 0 or c >= sim.colonies.size():
		return -1
	return sim.colonies[c].nest.underground_layer

## True if the current layout mode shows `l` (the surface or the nest's layer).
func shows_layer(l: int) -> bool:
	if l == camera.layer:
		return _mode != "nest"
	return l == nest_layer() and _mode != "surface"

## Hands an "across" follow's ant to the camera showing its layer (and
## switches layout mode for it if the keyframe asks); every other camera
## plays its own keyframes.
func _update_across() -> void:
	# The later of the two cameras' current across keyframes wins.
	var spec := camera.across_at(video_time)
	var source := camera
	if nest_camera != null:
		var under := nest_camera.across_at(video_time)
		if not under.is_empty() and (spec.is_empty() or float(under["t"]) > float(spec["t"])):
			spec = under
			source = nest_camera
	var holder: CameraDirector = null
	if not spec.is_empty():
		var ant: int = spec["ant"]
		var l := sim.layer[ant]
		if bool(spec["switch_mode"]) and not shows_layer(l):
			if l == camera.layer:
				set_mode("surface")
			elif l == nest_layer():
				set_mode("nest")
		if l != source.layer:
			if l == camera.layer:
				holder = camera
			elif nest_camera != null and l == nest_camera.layer:
				holder = nest_camera
	for cam: CameraDirector in [camera, nest_camera]:
		if cam == null:
			continue
		if cam == holder:
			cam.carry(int(spec["ant"]), float(spec["zoom"]), float(spec["smoothing"]))
		else:
			cam.carry(-1)
