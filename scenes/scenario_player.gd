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
var _hud: CanvasLayer
## Video seconds played so far.
var video_time: float = 0.0
## Video length from the scenario ("duration"), in seconds.
var duration: float = 20.0

var _tpf_points: Array[Vector2] = []  # (video time, ticks per frame)

## seed_value < 0 uses the scenario's seed. extra_ticks run after the
## scenario's own warmup, before the first frame.
func setup(scenario_name: String, seed_value: int = -1, extra_ticks: int = 0,
		debug_readout: RichTextLabel = null) -> void:
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
	# Screen-space layer for insets.
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
	camera.setup(sim, data.get("camera", []))
	camera.make_current()

	_parse_tpf(data.get("ticks_per_frame", config.ticks_per_frame))

## Advances video time by `delta` seconds; `speed` multiplies the scenario's
## own ticks-per-frame (interactive speed keys).
func advance(delta: float, speed: float = 1.0) -> void:
	video_time += delta
	runner.advance(ticks_per_frame_at(video_time) * VIDEO_FPS * delta * speed)
	view.alpha = runner.alpha()
	if cutaway != null:
		cutaway.update_visibility(video_time)
	camera.alpha = runner.alpha()
	camera.update_camera(video_time, delta)

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
