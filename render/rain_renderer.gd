class_name RainRenderer
extends Node2D
## Draws the simulation's rain showers with rain.gdshader. Each shower gets
## two rects: one on the ground layer (wet soil, splash rings) and one in this
## node, which sits above everything else (overcast dimming, falling drops).
## The ground stays wet for a while after a shower and dries slowly.

## Sim seconds for the rain to build up and to die away.
const FADE_IN := 1.0
const FADE_OUT := 1.5
## Sim seconds to soak the ground, and the half-life of drying afterwards.
const SOAK_TIME := 2.5
const DRY_HALF_LIFE := 10.0

var sim: Simulation
## Fraction of the way from the previous tick to the current one (set by WorldView).
var alpha: float = 1.0
var _ground_parent: Node2D
var _rects: Array[Array] = []  # per shower: [ground ColorRect, sky ColorRect]
var _clock: float = 0.0

## ground_parent: a node drawn just above the ground, below everything else.
func bind(simulation: Simulation, ground_parent: Node2D) -> void:
	sim = simulation
	_ground_parent = ground_parent

func _process(delta: float) -> void:
	if sim == null:
		return
	_clock += delta
	while _rects.size() < sim.rain.size():
		var shower := sim.rain[_rects.size()]
		var ground := _make_rect(shower, 0)
		var sky := _make_rect(shower, 1)
		_ground_parent.add_child(ground)
		add_child(sky)
		_rects.append([ground, sky])
	# Sim time at the interpolated render point.
	var now := sim.time() - (1.0 - alpha) * sim.dt
	for k in sim.rain.size():
		var shower := sim.rain[k]
		var start := float(shower["start"])
		var until := float(shower["until"])
		var intensity := clampf((now - start) / FADE_IN, 0.0, 1.0) * clampf(1.0 - (now - until) / FADE_OUT, 0.0, 1.0)
		var wet := clampf((now - start) / SOAK_TIME, 0.0, 1.0)
		if now > until:
			wet *= pow(0.5, (now - until) / DRY_HALF_LIFE)
		for rect: ColorRect in _rects[k]:
			rect.visible = wet > 0.005 or intensity > 0.0
			var mat := rect.material as ShaderMaterial
			mat.set_shader_parameter("clock", _clock)
			mat.set_shader_parameter("intensity", intensity)
			mat.set_shader_parameter("wetness", wet)

func _make_rect(shower: Dictionary, layer: int) -> ColorRect:
	var area: Dictionary = shower["area"]
	var bounds: Rect2
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/rain.gdshader")
	if area.has("rect"):
		bounds = ScenarioEvents.rect2(area["rect"])
	else:
		var c := ScenarioEvents.vec2(area["center"])
		var r := float(area["radius"])
		bounds = Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		mat.set_shader_parameter("circle", true)
		mat.set_shader_parameter("center", c)
		mat.set_shader_parameter("radius", r)
	mat.set_shader_parameter("layer", layer)
	mat.set_shader_parameter("world_size", Vector2(sim.config.world_size))
	mat.set_shader_parameter("origin", bounds.position)
	mat.set_shader_parameter("rect_size", bounds.size)
	var rect := ColorRect.new()
	rect.position = bounds.position
	rect.size = bounds.size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	rect.visible = false
	return rect
