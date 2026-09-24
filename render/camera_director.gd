class_name CameraDirector
extends Camera2D
## Scenario-driven camera. Keyframes (in video seconds):
##   {"t": 0, "pos": [x, y], "zoom": 3, "ease": "in_out"}
##   {"t": 4, "follow": {"near": [x, y], "state": "carry_home", "colony": 0}, "zoom": 5}
##   {"t": 9, "fit": "excavation", "margin": 60, "min_zoom": 0.4, "max_zoom": 4}
## Between two keyframes position and zoom are interpolated with the *second*
## keyframe's easing ("linear", "in", "out", "in_out"; default "in_out").
## Zoom is interpolated in log space so zooming feels even.
##
## A "follow" keyframe targets an ant: the first time it's needed, the ant
## nearest "near" (optionally in a given state / colony) is chosen, and from
## then on the target is that ant's position, smoothed so its wiggles don't
## shake the frame. If the ant disappears, its last position is kept.
##
## A "fit": "excavation" keyframe frames everything dug so far on the
## camera's layer (World.dug_rect) plus `margin` world units, zoomed to fit the
## view within [min_zoom, max_zoom]; the framing eases (FIT_SMOOTHING) as the
## nest grows.
##
## Modes: SCRIPT plays keyframes; FOLLOW tracks one ant (interactive "F");
## MANUAL leaves the camera to the user.

enum Mode { SCRIPT, FOLLOW, MANUAL }

## Seconds for the smoothed follow target to cover ~63% of the distance to the ant.
const FOLLOW_SMOOTHING := 0.35
## Seconds for a fit framing to cover ~63% of a change in the dug area.
const FIT_SMOOTHING := 1.2

var mode: Mode = Mode.SCRIPT
var keyframes: Array[Dictionary] = []
var sim: Simulation
## Interpolation alpha between completed ticks (set by the player each frame).
var alpha: float = 1.0
var follow_ant: int = -1
## Layer the camera looks at (its world size bounds the view).
var layer: int = 0

# Per-keyframe resolved follow state.
var _kf_ant: Dictionary[int, int] = {}
var _kf_smoothed: Dictionary[int, Vector2] = {}
var _follow_smoothed := Vector2.ZERO
## Smoothed dug area for "fit" keyframes (empty until first used).
var _fit_rect := Rect2()
var _fit_ready := false

func setup(simulation: Simulation, frames: Array, on_layer: int = 0) -> void:
	sim = simulation
	layer = on_layer
	var world := _world_size()
	limit_left = 0
	limit_top = 0
	limit_right = int(world.x)
	limit_bottom = int(world.y)
	position = world * 0.5
	keyframes.clear()
	for kf: Dictionary in frames:
		keyframes.append(kf)
	keyframes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	mode = Mode.SCRIPT if not keyframes.is_empty() else Mode.MANUAL

## Called once per frame with the video time and frame duration.
func update_camera(video_time: float, delta: float) -> void:
	match mode:
		Mode.SCRIPT:
			_update_follow_targets(video_time, delta)
			_update_fit(delta)
			_apply_keyframes(video_time)
		Mode.FOLLOW:
			if follow_ant >= 0 and sim.alive[follow_ant] != 0:
				_follow_smoothed = _smooth(_follow_smoothed, _ant_pos(follow_ant), delta)
				position = _follow_smoothed

## Start following an ant (interactive mode).
func follow(ant: int) -> void:
	follow_ant = ant
	_follow_smoothed = position
	mode = Mode.FOLLOW

## Index of the live ant nearest `at`, optionally filtered, or -1.
func nearest_ant(at: Vector2, state_id: String = "", colony: int = -1) -> int:
	var best := -1
	var best_d := INF
	for i in sim.high_water:
		if sim.alive[i] == 0:
			continue
		if sim.layer[i] != layer or (colony >= 0 and sim.colony_id[i] != colony):
			continue
		if state_id != "" and sim.state_id(i) != state_id:
			continue
		var d := sim.shown_pos[i].distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = i
	return best

func _apply_keyframes(t: float) -> void:
	var n := keyframes.size()
	if t <= float(keyframes[0]["t"]):
		_set_view(_target(0), _zoom_of(0))
		return
	if t >= float(keyframes[n - 1]["t"]):
		_set_view(_target(n - 1), _zoom_of(n - 1))
		return
	var k := 0
	while float(keyframes[k + 1]["t"]) < t:
		k += 1
	var a := keyframes[k]
	var b := keyframes[k + 1]
	var u := (t - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 0.0001)
	var e := _ease(u, str(b.get("ease", "in_out")))
	var z := exp(lerpf(log(_zoom_of(k)), log(_zoom_of(k + 1)), e))
	_set_view(_target(k).lerp(_target(k + 1), e), z)

func _set_view(pos: Vector2, z: float) -> void:
	zoom = Vector2(z, z)
	# Keep the view inside the world (Camera2D limits also clamp, but only the
	# drawn view; clamping the position keeps interpolation well-behaved).
	var half := get_viewport_rect().size * 0.5 / z
	var world := _world_size()
	position = Vector2(clampf(pos.x, minf(half.x, world.x * 0.5), maxf(world.x - half.x, world.x * 0.5)),
			clampf(pos.y, minf(half.y, world.y * 0.5), maxf(world.y - half.y, world.y * 0.5)))

## Target position of keyframe k at the current moment.
func _target(k: int) -> Vector2:
	var kf := keyframes[k]
	if kf.has("follow"):
		if _kf_smoothed.has(k):
			return _kf_smoothed[k]
		return ScenarioEvents.vec2(kf["follow"].get("near", [0, 0]))
	if kf.has("fit"):
		return _fit_rect.get_center()
	var world := _world_size()
	return ScenarioEvents.vec2(kf.get("pos", [world.x * 0.5, world.y * 0.5]))

## Resolves and smooths follow targets for keyframes in use around time t.
func _update_follow_targets(t: float, delta: float) -> void:
	for k in keyframes.size():
		var kf := keyframes[k]
		if not kf.has("follow"):
			continue
		# Needed from the previous keyframe's time until the next one's.
		var start := float(keyframes[k - 1]["t"]) if k > 0 else -INF
		var end := float(keyframes[k + 1]["t"]) if k + 1 < keyframes.size() else INF
		if t < start or t > end:
			continue
		var f: Dictionary = kf["follow"]
		if not _kf_ant.has(k):
			var near := ScenarioEvents.vec2(f.get("near", [0, 0]))
			_kf_ant[k] = nearest_ant(near, str(f.get("state", "")), int(f.get("colony", -1)))
			_kf_smoothed[k] = _ant_pos(_kf_ant[k]) if _kf_ant[k] >= 0 else near
		var ant: int = _kf_ant[k]
		if ant >= 0 and sim.alive[ant] != 0:
			_kf_smoothed[k] = _smooth(_kf_smoothed[k], _ant_pos(ant), delta)

func _ant_pos(i: int) -> Vector2:
	return sim.prev_pos[i].lerp(sim.shown_pos[i], alpha)

static func _smooth(current: Vector2, target_pos: Vector2, delta: float) -> Vector2:
	return current.lerp(target_pos, 1.0 - exp(-delta / FOLLOW_SMOOTHING))

static func _ease(u: float, kind: String) -> float:
	u = clampf(u, 0.0, 1.0)
	match kind:
		"linear":
			return u
		"in":
			return u * u * u
		"out":
			return 1.0 - pow(1.0 - u, 3.0)
		_:
			# Cubic ease-in-out.
			return 4.0 * u * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0

func _world_size() -> Vector2:
	return Vector2(sim.layers[layer].world.size)

## Zoom of keyframe k (a "fit" keyframe's zoom follows the dug area).
func _zoom_of(k: int) -> float:
	var kf := keyframes[k]
	if not kf.has("fit"):
		return float(kf.get("zoom", 1.0))
	var margin := float(kf.get("margin", 60.0))
	var view := get_viewport_rect().size
	var want := _fit_rect.grow(margin).size
	var z := minf(view.x / maxf(want.x, 1.0), view.y / maxf(want.y, 1.0))
	return clampf(z, float(kf.get("min_zoom", 0.3)), float(kf.get("max_zoom", 4.0)))

## Eases the fit framing toward the layer's dug area.
func _update_fit(delta: float) -> void:
	var world := sim.layers[layer].world
	var target_rect := world.dug_rect if world.dug_cells > 0 else Rect2(_world_size() * 0.5, Vector2.ZERO)
	if not _fit_ready:
		_fit_rect = target_rect
		_fit_ready = true
		return
	var k := 1.0 - exp(-delta / FIT_SMOOTHING)
	_fit_rect = Rect2(_fit_rect.position.lerp(target_rect.position, k), _fit_rect.size.lerp(target_rect.size, k))

## Jumps the fit framing to the current dug area (e.g. after fast-forwarding).
func snap_fit() -> void:
	_fit_ready = false
	_update_fit(0.0)
