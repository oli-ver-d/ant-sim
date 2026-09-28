class_name StoryMarker
extends Node2D
## A soft ring on what the camera story follows (CameraDirector.story_pos: the
## followed ant or brood item), so "our" egg or worker can be told apart in a
## pile. Render only. Drawn in world space on top of its WorldView, one per
## camera (ScenarioPlayer). From the scenario's "render" section:
##
##   "story_marker": [{"t": 16, "until": 57, "fade": 0.5}, ...]
##       shown between t and until (video seconds), faded in and out over
##       `fade` seconds (default 0.5).

## Ring radius on screen, in pixels, at least (small targets at low zoom).
const MIN_RADIUS_PX := 26.0
## Ring radius in world units, at least (large targets at high zoom).
const MIN_RADIUS_WORLD := 5.5
const COLOR := Color(1.0, 0.93, 0.7)

var camera: CameraDirector
## (t, until, fade) windows.
var windows: Array[Vector3] = []
var video_time := 0.0

static func parse(spec: Variant) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if spec is Array:
		for w: Dictionary in spec:
			out.append(Vector3(float(w["t"]), float(w.get("until", INF)), maxf(float(w.get("fade", 0.5)), 0.0)))
	return out

## Opacity at video time t: 1 inside a window, ramped over its fade.
static func alpha_at(wins: Array[Vector3], t: float) -> float:
	var a := 0.0
	for w in wins:
		if t < w.x or t > w.y:
			continue
		var f := maxf(w.z, 0.0001)
		a = maxf(a, clampf((t - w.x) / f, 0.0, 1.0) * clampf((w.y - t) / f, 0.0, 1.0))
	return a

func _init() -> void:
	z_index = 100

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if camera == null:
		return
	var a := alpha_at(windows, video_time)
	if a <= 0.0:
		return
	var p: Variant = camera.story_pos()
	if p == null:
		return
	var z := maxf(camera.zoom.x, 0.01)
	var pulse := 1.0 + 0.08 * sin(video_time * 4.0)
	var r := maxf(MIN_RADIUS_PX / z, MIN_RADIUS_WORLD) * pulse
	draw_arc(p, r + 2.5 / z, 0.0, TAU, 48, Color(0, 0, 0, 0.3 * a), 4.0 / z, true)
	draw_arc(p, r, 0.0, TAU, 48, Color(COLOR, 0.85 * a), 2.5 / z, true)
