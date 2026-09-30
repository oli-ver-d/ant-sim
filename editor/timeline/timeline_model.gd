class_name TimelineModel
extends RefCounted
## M16g: the timeline editor's data model, GUI-free. It maps video time to sim time (the same
## way ScenarioPlayer does), turns the scenario's time-keyed lists (camera, speed, layout,
## captions, fades, grade, story marker, events) into tracks of items, hit-tests them and
## computes the edits (move, resize, add). Nothing here writes to the scenario: the caller
## applies the returned values through its document. Malformed data yields no items.

## Video time to sim time for one scenario: the piecewise-linear ticks-per-frame curve, the
## jumps and the warmup (see ScenarioPlayer.advance).
class TimeMap extends RefCounted:
	## (video t, ticks per frame), sorted; constant before the first and after the last.
	var points: Array[Vector2] = []
	## (video t, sim seconds), sorted.
	var jumps: Array[Vector2] = []
	## Sim seconds run before video time 0.
	var warmup: float = 0.0
	var tick_rate: float = 30.0
	## Video length in seconds.
	var duration: float = 20.0
	var config: SimConfig = null

	## Ticks per frame at video time `t` (same as ScenarioPlayer.ticks_per_frame_at).
	func tpf_at(t: float) -> float:
		if points.size() == 1 or t <= points[0].x:
			return points[0].y
		for k in range(1, points.size()):
			var b := points[k]
			if t < b.x:
				var a := points[k - 1]
				return lerpf(a.y, b.y, (t - a.x) / maxf(b.x - a.x, 0.0001))
		return points[points.size() - 1].y

	## Exact integral of tpf over [0, t] (video seconds; the curve is piecewise linear).
	func _integral(t: float) -> float:
		if t <= 0.0:
			return 0.0
		var total := 0.0
		var lo := 0.0
		# Before the first point: constant.
		var first := points[0]
		if first.x > 0.0:
			var hi0 := minf(t, first.x)
			total += first.y * (hi0 - lo)
			lo = hi0
		for k in range(1, points.size()):
			if lo >= t:
				break
			var a := points[k - 1]
			var b := points[k]
			if b.x <= lo or b.x <= a.x:
				continue
			var hi := minf(t, b.x)
			var lo_a := maxf(lo, a.x)
			var ylo := lerpf(a.y, b.y, (lo_a - a.x) / (b.x - a.x))
			var yhi := lerpf(a.y, b.y, (hi - a.x) / (b.x - a.x))
			total += (ylo + yhi) * 0.5 * (hi - lo_a)
			lo = hi
		if lo < t:
			total += points[points.size() - 1].y * (t - lo)
		return total

	## Sim seconds elapsed at video time `video_t` (warmup, the curve and the jumps made).
	func sim_time_at(video_t: float) -> float:
		var s := warmup + 60.0 * _integral(video_t) / tick_rate
		for j in jumps:
			if j.x <= video_t + 1e-6:
				s += j.y
			else:
				break
		return s

	## The earliest video time >= 0 at which the sim clock has reached `sim_t`; INF if never.
	func video_time_at(sim_t: float) -> float:
		var s0 := sim_time_at(0.0)
		if sim_t <= s0 + 1e-9:
			return 0.0
		var marks: Array[float] = []
		for p in points:
			if p.x > 0.0:
				marks.append(p.x)
		for j in jumps:
			if j.x > 1e-6:
				marks.append(j.x)
		marks.sort()
		var t0 := 0.0
		for b in marks:
			if b <= t0:
				continue
			var y0 := tpf_at(t0)
			var y1 := tpf_at(b - 1e-9)
			var span := b - t0
			var s_end := s0 + 60.0 / tick_rate * (y0 + y1) * 0.5 * span
			if sim_t <= s_end + 1e-9:
				var need := (sim_t - s0) * tick_rate / 60.0
				var k := (y1 - y0) / span
				var denom := y0 + sqrt(maxf(y0 * y0 + 2.0 * k * need, 0.0))
				var x := 0.0 if denom <= 1e-12 else 2.0 * need / denom
				return t0 + clampf(x, 0.0, span)
			var s_at := sim_time_at(b)
			if sim_t <= s_at + 1e-9:
				return b
			s0 = s_at
			t0 = b
		var y := points[points.size() - 1].y
		if y <= 1e-12:
			return INF
		return t0 + (sim_t - s0) * tick_rate / (60.0 * y)

const SPAN_MIN := 0.1
const TICK_STEPS: Array[float] = [0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0, 600.0]

static func _is_num(v: Variant) -> bool:
	return v is float or v is int

## x rounded to 0.01, whole numbers as ints.
static func _round(x: float) -> Variant:
	return FieldValues.tidy(snappedf(x, 0.01))

static func _fmt(x: float) -> String:
	return str(_round(x))

## Value at `path` (dictionary keys and array indices) in `data`, or null.
static func _get_at(data: Variant, path: Array) -> Variant:
	var cur: Variant = data
	for key: Variant in path:
		if cur is Dictionary and key is String and (cur as Dictionary).has(key):
			cur = (cur as Dictionary)[key]
		elif cur is Array and key is int and int(key) >= 0 and int(key) < (cur as Array).size():
			cur = (cur as Array)[int(key)]
		else:
			return null
	return cur

# --- time mapping ---------------------------------------------------------------------------

## The time map of a scenario (`config` supplies the default speed and tick rate).
static func time_map(data: Dictionary, config: SimConfig = null) -> TimeMap:
	if config == null:
		config = load("res://sim/default_config.tres")
	var m := TimeMap.new()
	m.config = config
	m.tick_rate = float(config.tick_rate)
	var w: Variant = data.get("warmup", 0.0)
	m.warmup = float(w) if _is_num(w) else 0.0
	var d: Variant = data.get("duration", 20.0)
	m.duration = float(d) if _is_num(d) else 20.0
	var spec: Variant = data.get("ticks_per_frame", config.ticks_per_frame)
	if spec is Array:
		for p: Variant in spec:
			if not (p is Dictionary) or not _is_num((p as Dictionary).get("t")):
				continue
			var pd: Dictionary = p
			var t := float(pd["t"])
			if _is_num(pd.get("tpf")):
				m.points.append(Vector2(t, float(pd["tpf"])))
			if _is_num(pd.get("jump")) and float(pd["jump"]) > 0.0:
				m.jumps.append(Vector2(t, float(pd["jump"])))
		m.points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		m.jumps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	if m.points.is_empty():
		m.points.append(Vector2(0.0, float(spec) if _is_num(spec) else config.ticks_per_frame))
	return m

# --- tracks ---------------------------------------------------------------------------------

static func _track(id: String, label: String, kind: String, clock: String, list: Array) -> Dictionary:
	return {"id": id, "label": label, "kind": kind, "clock": clock, "list": list, "items": [] as Array[Dictionary]}

## All tracks of the scenario, in display order (empty ones included).
static func tracks(data: Dictionary, map: TimeMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cam: Variant = data.get("camera")
	if cam is Dictionary:
		out.append(_track("camera_surface", "Camera: surface", "points", "video", ["camera", "surface"]))
		out.append(_track("camera_nest", "Camera: nest", "points", "video", ["camera", "nest"]))
	else:
		out.append(_track("camera", "Camera", "points", "video", ["camera"]))
	out.append(_track("speed", "Speed", "curve", "video", ["ticks_per_frame"]))
	out.append(_track("layout", "Layout", "points", "video", ["render", "layout", "modes"]))
	out.append(_track("captions", "Captions", "spans", "video", ["render", "captions"]))
	out.append(_track("fades", "Fades", "points", "video", ["render", "fades"]))
	out.append(_track("grade", "Grade", "points", "video", ["render", "grade"]))
	out.append(_track("story_marker", "Story marker", "spans", "video", ["render", "story_marker"]))
	out.append(_track("events", "Events (sim time)", "points", "sim", ["events"]))
	for tr in out:
		var list: Variant = _get_at(data, tr["list"])
		if not (list is Array):
			continue
		var items: Array[Dictionary] = tr["items"]
		for i in (list as Array).size():
			var e: Variant = (list as Array)[i]
			if not (e is Dictionary) or not _is_num((e as Dictionary).get("t")):
				continue
			items.append(_item(tr["id"], tr["list"], i, e, map))
	return out

static func _item(track_id: String, list: Array, index: int, e: Dictionary, map: TimeMap) -> Dictionary:
	var t := float(e["t"])
	var sim_t := -1.0
	if track_id == "events":
		sim_t = t
		t = map.video_time_at(sim_t)
	var until := -1.0
	var has_until := false
	if track_id == "captions" or track_id == "story_marker":
		has_until = _is_num(e.get("until"))
		if has_until:
			until = float(e["until"])
		else:
			until = t + 4.0 if track_id == "captions" else t
	var path := list.duplicate()
	path.append(index)
	return {"path": path, "t": t, "until": until, "has_until": has_until,
			"label": _label(track_id, e), "sim_t": sim_t}

static func _label(track_id: String, e: Dictionary) -> String:
	match track_id:
		"camera", "camera_surface", "camera_nest":
			var s := "camera"
			var pos: Variant = e.get("pos")
			if e.has("follow"):
				s = "follow"
			elif e.has("fit"):
				s = "fit"
			elif pos is Array and (pos as Array).size() >= 2 and _is_num(pos[0]) and _is_num(pos[1]):
				s = "pos %s,%s" % [_fmt(float(pos[0])), _fmt(float(pos[1]))]
			if _is_num(e.get("zoom")):
				s += " ×%s" % _fmt(float(e["zoom"]))
			return s
		"speed":
			var parts: PackedStringArray = []
			if _is_num(e.get("tpf")):
				parts.append("tpf %s" % _fmt(float(e["tpf"])))
			if _is_num(e.get("jump")):
				parts.append("jump %s s" % _fmt(float(e["jump"])))
			return ", ".join(parts) if not parts.is_empty() else "speed"
		"layout":
			return str(e.get("mode", "layout"))
		"captions":
			var text: Variant = e.get("text")
			if not (text is String):
				return "caption"
			var line: String = (text as String).split("\n")[0]
			if line.length() > 40:
				line = line.substr(0, 39) + "…"
			return line
		"fades":
			return "to %s" % _fmt(float(e["to"])) if _is_num(e.get("to")) else "fade"
		"grade":
			return "grade"
		"story_marker":
			return "marker"
		"events":
			return str(e.get("type", "event"))
	return ""

# --- hit testing ----------------------------------------------------------------------------

## The item of `track` at time `t` (within `tol` seconds of an edge or point, or inside a span):
## {index, part: "until" | "t" | "body"}, or {} for a miss.
static func hit(track: Dictionary, t: float, tol: float) -> Dictionary:
	var items: Array = track.get("items", [])
	var spans: bool = track.get("kind", "") == "spans"
	if spans:
		var best := -1
		var best_d := INF
		for i in items.size():
			var d := absf(float(items[i]["until"]) - t)
			if d <= tol and d <= best_d:
				best = i
				best_d = d
		if best >= 0:
			return {"index": best, "part": "until"}
	var best_t := -1
	var best_td := INF
	for i in items.size():
		var d := absf(float(items[i]["t"]) - t)
		if d <= tol and d <= best_td:
			best_t = i
			best_td = d
	if best_t >= 0:
		return {"index": best_t, "part": "t"}
	if spans:
		var body := -1
		var body_len := INF
		for i in items.size():
			var a := float(items[i]["t"])
			var b := float(items[i]["until"])
			if t >= a and t <= b and b - a <= body_len:
				body = i
				body_len = b - a
		if body >= 0:
			return {"index": body, "part": "body"}
	return {}

# --- edits ----------------------------------------------------------------------------------

static func _is_span_path(path: Array) -> bool:
	if path.size() == 3:
		return path[0] == "render" and (path[1] == "captions" or path[1] == "story_marker")
	return false

## The item at `path` with its time set to `video_t` (events: the matching sim time); a span
## with an explicit "until" keeps its length.
static func moved(data: Dictionary, item_path: Array, video_t: float, map: TimeMap) -> Dictionary:
	var src: Variant = _get_at(data, item_path)
	if not (src is Dictionary) or not _is_num((src as Dictionary).get("t")):
		return {}
	var item: Dictionary = (src as Dictionary).duplicate(true)
	var old_t := float(item["t"])
	var vt := maxf(video_t, 0.0)
	var new_t := map.sim_time_at(vt) if item_path[0] == "events" else vt
	new_t = float(_round(new_t))
	item["t"] = _round(new_t)
	if _is_span_path(item_path) and _is_num(item.get("until")):
		item["until"] = _round(float(item["until"]) + (new_t - old_t))
	return item

## The span at `path` with "until" set to `until_video` (at least SPAN_MIN after its start).
static func resized(data: Dictionary, item_path: Array, until_video: float) -> Dictionary:
	if not _is_span_path(item_path):
		return {}
	var src: Variant = _get_at(data, item_path)
	if not (src is Dictionary) or not _is_num((src as Dictionary).get("t")):
		return {}
	var item: Dictionary = (src as Dictionary).duplicate(true)
	item["until"] = _round(maxf(until_video, float(item["t"]) + SPAN_MIN))
	return item

## A new item for track `track_id` at video time `video_t`:
## {path, value, insert}. insert: insert `value` into the list at `path` (append); otherwise
## set `path` to `value` (the list is missing or is not a list yet).
static func new_item(track_id: String, data: Dictionary, video_t: float, map: TimeMap, extra: Dictionary = {}) -> Dictionary:
	var vt := maxf(video_t, 0.0)
	var t: Variant = _round(vt)
	var item := {}
	var list: Array = []
	match track_id:
		"camera", "camera_surface", "camera_nest":
			var w := Vector2(ScenarioLoader.world_size(data, map.config)) if map.config != null else Vector2(1080, 1920)
			item = {"t": t, "pos": [FieldValues.tidy(w.x / 2.0), FieldValues.tidy(w.y / 2.0)], "zoom": 1}
			list = ["camera"]
			if track_id == "camera_surface":
				list = ["camera", "surface"]
			elif track_id == "camera_nest":
				list = ["camera", "nest"]
		"speed":
			item = {"t": t, "tpf": _round(map.tpf_at(vt))}
			list = ["ticks_per_frame"]
		"layout":
			item = {"t": t, "mode": "split"}
			list = ["render", "layout", "modes"]
		"captions":
			item = {"t": t, "until": _round(vt + 4.0), "text": "Caption"}
			list = ["render", "captions"]
		"fades":
			item = {"t": t, "to": 1}
			list = ["render", "fades"]
		"grade":
			item = {"t": t, "brightness": 1}
			list = ["render", "grade"]
		"story_marker":
			item = {"t": t, "until": _round(vt + 5.0)}
			list = ["render", "story_marker"]
		"events":
			item = {"t": _round(map.sim_time_at(vt)), "type": "rain", "duration": 6}
			list = ["events"]
		_:
			return {}
	for k: Variant in extra:
		item[k] = extra[k]
	var cur: Variant = _get_at(data, list)
	if cur is Array:
		return {"path": list, "value": item, "insert": true}
	if track_id == "speed" and _is_num(cur) and vt > 0.0:
		return {"path": list, "value": [{"t": 0, "tpf": _round(float(cur))}, item], "insert": false}
	if track_id == "speed" and cur == null and vt > 0.0:
		return {"path": list, "value": [{"t": 0, "tpf": _round(map.tpf_at(0.0))}, item], "insert": false}
	return {"path": list, "value": [item], "insert": false}

## A camera keyframe showing the world rect of size `view_world` centred on `center`, for an
## output frame of `frame_size` (the frame then fits inside the viewed world rect).
static func camera_key_here(center: Vector2, view_world: Vector2, frame_size: Vector2, t: float) -> Dictionary:
	var zoom := 1.0
	if view_world.x > 0.0 and view_world.y > 0.0:
		zoom = maxf(frame_size.x / view_world.x, frame_size.y / view_world.y)
	return {"t": _round(maxf(t, 0.0)), "pos": [roundi(center.x), roundi(center.y)],
			"zoom": FieldValues.tidy(snappedf(zoom, 0.001))}

# --- ruler ----------------------------------------------------------------------------------

## The smallest tick spacing (seconds) that is at least `min_px` wide at `px_per_second`.
static func tick_step(px_per_second: float, min_px: float = 70.0) -> float:
	for s in TICK_STEPS:
		if s * px_per_second >= min_px:
			return s
	return TICK_STEPS[TICK_STEPS.size() - 1]

## `t` rounded to a multiple of `step` (unchanged when step <= 0).
static func snap_time(t: float, step: float) -> float:
	if step <= 0.0:
		return t
	return roundf(t / step) * step
