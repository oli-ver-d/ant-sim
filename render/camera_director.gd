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
## A "follow" keyframe targets an ant: the first time it's needed (from the
## previous keyframe's time), the ant nearest "near" on this camera's layer
## (optionally in a given state / colony) is chosen, and from then on the
## target is that ant's position, smoothed so its wiggles don't shake the
## frame ("smoothing": seconds to cover ~63% of the distance, default
## FOLLOW_SMOOTHING; larger is slower and more cinematic, 0 locks on). If the
## ant dies or is on another layer, its last position is kept.
##
## Follow targets (the "follow" dictionary):
##   {"near": [x, y], "state": "...", "colony": 0}   nearest matching ant
##   {"ant": "same"}      whatever the story follows now: the ant (or brood
##                        item) the latest follow keyframe on either camera
##                        chose, or the ant an "across" follow was handed on
##   {"ant": 12}          ant slot 12
##   {"brood": "first" | "last" | "near" | <id>, "stage": "egg", "near": [x, y], "colony": 0}
##                        a brood record of the colony's nest (brood care on):
##                        the oldest / newest (matching "stage"), the one
##                        nearest "near", or a record id. It's followed by id
##                        through its stages (carried brood rides with its
##                        nurse), then as the ant it becomes when it ecloses
##                        (Brood.emerged_as).
##   "across": true       keep the ant through portals: ScenarioPlayer hands it
##                        to the camera of the layout part showing its layer
##                        (carry()); with "switch_mode": true the layout mode
##                        changes so its layer is shown (see ScenarioPlayer).
## The follow keyframe's own "zoom" is used by the camera it's handed to.
## After a time jump (ScenarioPlayer, "jump" on a ticks_per_frame point)
## snap() moves smoothed targets straight to where they are now.
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
## What the story follows now, shared by the cameras of one ScenarioPlayer:
## {"ant": i} or {"brood": id, "colony": c}. Read by {"ant": "same"}.
var story: Dictionary = {}

# Per-keyframe resolved follow state: the ant, or a brood id (with its colony)
# until it becomes an ant, and the smoothed target.
var _kf_ant: Dictionary[int, int] = {}
var _kf_brood: Dictionary[int, Vector2i] = {}
var _kf_smoothed: Dictionary[int, Vector2] = {}
var _follow_smoothed := Vector2.ZERO
## Smoothed dug area for "fit" keyframes (empty until first used).
var _fit_rect := Rect2()
var _fit_ready := false
## An ant handed to this camera by an "across" follow on another camera
## (see carry()), and how to frame it.
var _carry_ant: int = -1
var _carry_zoom: float = 1.0
var _carry_smoothing: float = FOLLOW_SMOOTHING
var _carry_smoothed := Vector2.ZERO

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
			if _carry_ant >= 0:
				if _on_my_layer(_carry_ant):
					_carry_smoothed = _smooth(_carry_smoothed, _ant_pos(_carry_ant), delta, _carry_smoothing)
				_set_view(_carry_smoothed, _carry_zoom)
			else:
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

## Index of the keyframe in effect at time t (the last one at or before it), or -1.
func keyframe_at(t: float) -> int:
	var k := -1
	for n in keyframes.size():
		if float(keyframes[n]["t"]) <= t + 1e-6:
			k = n
	return k

## The ant keyframe k follows now (-1 if none yet, or it follows brood).
func followed_ant(k: int) -> int:
	return _kf_ant.get(k, -1)

## The brood id keyframe k follows now (-1 if it follows an ant or nothing).
func followed_brood(k: int) -> int:
	return _kf_brood[k].x if _kf_brood.has(k) else -1

## If the keyframe in effect at t is an "across" follow of a live ant:
## {"ant", "t" (the keyframe's), "zoom", "smoothing", "switch_mode"}; otherwise empty.
func across_at(t: float) -> Dictionary:
	if mode != Mode.SCRIPT:
		return {}
	var k := keyframe_at(t)
	if k < 0 or not keyframes[k].has("follow"):
		return {}
	var f: Dictionary = keyframes[k]["follow"]
	var ant := followed_ant(k)
	if not bool(f.get("across", false)) or ant < 0 or sim.alive[ant] == 0:
		return {}
	return {"ant": ant, "t": float(keyframes[k]["t"]), "zoom": float(keyframes[k].get("zoom", zoom.x)),
		"smoothing": _smoothing_of(k), "switch_mode": bool(f.get("switch_mode", false))}

## Frames `ant` (handed on by an "across" follow) instead of playing this
## camera's keyframes, until carry(-1). A newly handed ant is cut to.
func carry(ant: int, z: float = 1.0, smoothing: float = FOLLOW_SMOOTHING) -> void:
	if ant != _carry_ant and ant >= 0:
		_carry_smoothed = _ant_pos(ant)
		story = _set_story(story, {"ant": ant})
	_carry_ant = ant
	_carry_zoom = z
	_carry_smoothing = smoothing

## The ant this camera was handed, or -1.
func carried_ant() -> int:
	return _carry_ant

## Jumps smoothed targets and fit framing to where they are now (after a
## time jump, under a fade).
func snap() -> void:
	snap_fit()
	for k: int in _kf_smoothed.keys():
		var p: Variant = _tracked_pos(k)
		if p != null:
			_kf_smoothed[k] = p
	if _carry_ant >= 0 and _on_my_layer(_carry_ant):
		_carry_smoothed = _ant_pos(_carry_ant)

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
		if not _kf_smoothed.has(k):
			_resolve(k)
		_track_brood(k)
		var p: Variant = _tracked_pos(k)
		if p != null:
			_kf_smoothed[k] = _smooth(_kf_smoothed[k], p, delta, _smoothing_of(k))

## Chooses keyframe k's ant or brood item.
func _resolve(k: int) -> void:
	var f: Dictionary = keyframes[k]["follow"]
	var near := ScenarioEvents.vec2(f.get("near", [0, 0]))
	var ant := -1
	if f.has("brood"):
		var colony := int(f.get("colony", 0))
		var brood := _brood_of(colony)
		var rec := -1 if brood == null else _pick_brood(brood, f, near)
		if rec >= 0:
			_kf_brood[k] = Vector2i(brood.id[rec], colony)
			story = _set_story(story, {"brood": brood.id[rec], "colony": colony})
	elif f.has("ant"):
		var which: Variant = f["ant"]
		if str(which) == "same":
			if story.has("brood"):
				_kf_brood[k] = Vector2i(int(story["brood"]), int(story["colony"]))
			else:
				ant = int(story.get("ant", -1))
		else:
			ant = int(which)
		if ant >= 0 and (ant >= sim.high_water or sim.alive[ant] == 0):
			ant = -1
	else:
		ant = nearest_ant(near, str(f.get("state", "")), int(f.get("colony", -1)))
	if ant >= 0:
		_kf_ant[k] = ant
		story = _set_story(story, {"ant": ant})
	_kf_smoothed[k] = near
	var p: Variant = _tracked_pos(k)
	if p != null:
		_kf_smoothed[k] = p

## Once keyframe k's brood item has emerged, follows the ant it became.
func _track_brood(k: int) -> void:
	if not _kf_brood.has(k):
		return
	var b := _kf_brood[k]
	var brood := _brood_of(b.y)
	if brood == null or brood.index_of(b.x) >= 0:
		return
	var ant := brood.emerged_as(b.x)
	if ant == Brood.NOT_EMERGED:
		return  # Died, or left the log: keep the last position.
	_kf_brood.erase(k)
	if ant >= 0:
		_kf_ant[k] = ant
		if story.get("brood", -1) == b.x:
			story = _set_story(story, {"ant": ant})

## Where keyframe k's target is now, or null if it isn't on this layer.
func _tracked_pos(k: int) -> Variant:
	if _kf_brood.has(k):
		return _brood_pos(_kf_brood[k].x, _kf_brood[k].y)
	var ant: int = _kf_ant.get(k, -1)
	if ant >= 0 and _on_my_layer(ant):
		return _ant_pos(ant)
	return null

## Where the story's ant or brood item is now, or null if it isn't on this
## camera's layer (or there is none). Read by StoryMarker.
func story_pos() -> Variant:
	if story.has("brood"):
		return _brood_pos(int(story["brood"]), int(story.get("colony", 0)))
	var ant := int(story.get("ant", -1))
	if ant >= 0 and ant < sim.high_water and _on_my_layer(ant):
		return _ant_pos(ant)
	return null

## Where brood record `id` of `colony` is drawn now (on its carrier if
## carried), or null if it's gone or not on this camera's layer.
func _brood_pos(id: int, colony: int) -> Variant:
	var brood := _brood_of(colony)
	var rec := brood.index_of(id) if brood != null else -1
	if rec < 0 or sim.colonies[colony].nest.underground_layer != layer:
		return null
	var c := brood.carrier[rec]
	if c >= 0 and sim.alive[c] != 0:
		var h := lerp_angle(sim.prev_heading[c], sim.shown_heading[c], alpha)
		return _ant_pos(c) + Vector2.from_angle(h) * sim.caste_of(c).size * 0.55
	return brood.pos[rec]

## Record index in `brood` for a follow's "brood" choice, or -1.
func _pick_brood(brood: Brood, f: Dictionary, near: Vector2) -> int:
	var which: Variant = f["brood"]
	var stage := Brood.STAGE_KEYS.find(str(f.get("stage", "")))
	if which is float or which is int:
		return brood.index_of(int(which))
	var best := -1
	var best_d := INF
	for rec in brood.count():
		if stage >= 0 and brood.stage[rec] != stage:
			continue
		match str(which):
			"first":
				return rec
			"last":
				best = rec
			_:
				var d := brood.pos[rec].distance_squared_to(near)
				if d < best_d:
					best_d = d
					best = rec
	return best

## The colony's brood if it has brood care (positions in the nest), or null.
func _brood_of(colony: int) -> Brood:
	if colony < 0 or colony >= sim.colonies.size():
		return null
	var nest := sim.colonies[colony].nest as ColonyNest
	if nest == null or nest.brood == null or not nest.brood.care:
		return null
	return nest.brood

## Updates the shared story in place (both cameras hold the same dictionary).
static func _set_story(s: Dictionary, what: Dictionary) -> Dictionary:
	s.clear()
	s.merge(what)
	return s

func _on_my_layer(ant: int) -> bool:
	return sim.alive[ant] != 0 and sim.layer[ant] == layer

func _smoothing_of(k: int) -> float:
	return float(keyframes[k].get("smoothing", FOLLOW_SMOOTHING))

func _ant_pos(i: int) -> Vector2:
	return sim.prev_pos[i].lerp(sim.shown_pos[i], alpha)

static func _smooth(current: Vector2, target_pos: Vector2, delta: float, tau: float = FOLLOW_SMOOTHING) -> Vector2:
	if tau <= 0.0:
		return target_pos
	return current.lerp(target_pos, 1.0 - exp(-delta / tau))

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
