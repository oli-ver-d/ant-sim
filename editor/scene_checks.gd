class_name SceneChecks
extends RefCounted
## M16i: the scene half of the scenario validator: problems of what the scenario places and
## schedules, not of its schema (nests, food and entrances outside the world or in a wall, events,
## camera keys and captions after the video ends, overlapping colonies, captions in the platform's
## unsafe margins). GUI-free. Malformed data is skipped (the schema checks report it).
##
## An issue is {"path": Array, "severity": "error" | "warning", "message": String}; `path` is the
## document path of the offending item or key.

## Two nests closer than this (world units), or than the sum of their "radius" params, overlap.
const MIN_NEST_DISTANCE := 60.0
## Slack (pixels) before a caption box counts as outside the safe zone.
const SAFE_TOLERANCE := 2.0

## Scene issues of scenario `data` (the parsed JSON Dictionary). `sim` is the Simulation built
## from it by ScenarioLoader (for the walls and entrances); when null, the checks that need it are
## skipped, and the world size comes from the document ("world.size") or the default config.
static func issues(data: Dictionary, registry: Registry, sim: Simulation = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var world := _world_size(data, sim)
	var points: Array[Dictionary] = _points(data)
	_check_points(out, points, world, sim)
	_check_portals(out, points, world, sim)
	_check_colonies(out, data)
	_check_timing(out, data)
	_check_captions(out, data)
	return out

# --- helpers --------------------------------------------------------------------------------

static func _issue(path: Array, severity: String, message: String) -> Dictionary:
	return {"path": path, "severity": severity, "message": message}

static func _is_num(v: Variant) -> bool:
	return v is float or v is int

static func _vec(v: Variant) -> Variant:
	if v is Array and (v as Array).size() >= 2 and _is_num(v[0]) and _is_num(v[1]):
		return Vector2(float(v[0]), float(v[1]))
	return null

static func _fmt(x: float) -> String:
	return str(snappedf(x, 0.1)).trim_suffix(".0")

static func _fmt_v(p: Vector2) -> String:
	return "(%s, %s)" % [_fmt(p.x), _fmt(p.y)]

static func _list(data: Dictionary, key: String) -> Array:
	var v: Variant = data.get(key)
	return v if v is Array else []

## The world size: the built sim's, else the document's "world.size", else the default config's.
static func _world_size(data: Dictionary, sim: Simulation) -> Vector2:
	if sim != null and sim.world != null:
		return Vector2(sim.world.size)
	var config: SimConfig = load("res://sim/default_config.tres")
	return Vector2(ScenarioLoader.world_size(data, config))

## The placed points to check: {"path", "pos", "what"} for each nest and food source.
static func _points(data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var colonies := _list(data, "colonies")
	for i in colonies.size():
		if colonies[i] is Dictionary:
			var p: Variant = _vec((colonies[i] as Dictionary).get("nest"))
			if p != null:
				out.append({"path": ["colonies", i], "pos": p, "what": "Nest", "colony": i})
	var food := _list(data, "food")
	for i in food.size():
		if food[i] is Dictionary:
			var p: Variant = _vec((food[i] as Dictionary).get("pos"))
			if p != null:
				out.append({"path": ["food", i, "pos"], "pos": p, "what": "Food", "colony": -1})
	return out

static func _outside_message(what: String, pos: Vector2, world: Vector2) -> String:
	return "%s is outside the world %s; world is %sx%s" % [what, _fmt_v(pos), _fmt(world.x), _fmt(world.y)]

static func _inside(pos: Vector2, world: Vector2) -> bool:
	return pos.x >= 0.0 and pos.y >= 0.0 and pos.x < world.x and pos.y < world.y

# --- world bounds and walls -----------------------------------------------------------------

static func _check_points(out: Array[Dictionary], points: Array[Dictionary], world: Vector2, sim: Simulation) -> void:
	for pt in points:
		var pos: Vector2 = pt["pos"]
		if not _inside(pos, world):
			out.append(_issue(pt["path"], "error", _outside_message(pt["what"], pos, world)))
		elif sim != null and sim.world != null and sim.world.is_blocked(pos):
			out.append(_issue(pt["path"], "error", "%s is inside a wall or water %s" % [pt["what"], _fmt_v(pos)]))

## Surface ends of the built sim's portals (nest entrances), reported at the nearest nest's colony.
static func _check_portals(out: Array[Dictionary], points: Array[Dictionary], world: Vector2, sim: Simulation) -> void:
	if sim == null:
		return
	for portal in sim.portals:
		if portal.layer_a != 0:
			continue
		var pos := portal.pos_a
		var bad := ""
		if not _inside(pos, world):
			bad = _outside_message("Nest entrance", pos, world)
		elif sim.world != null and sim.world.is_blocked(pos):
			bad = "Nest entrance is inside a wall or water %s" % _fmt_v(pos)
		if bad == "":
			continue
		var best: Array = ["colonies"]
		var best_d := INF
		for pt in points:
			if pt["colony"] >= 0 and (pt["pos"] as Vector2).distance_to(pos) < best_d:
				best_d = (pt["pos"] as Vector2).distance_to(pos)
				best = pt["path"]
		out.append(_issue(best, "error", bad))

# --- colonies -------------------------------------------------------------------------------

static func _nest_radius(col: Dictionary) -> float:
	var np: Variant = col.get("nest_params")
	if np is Dictionary and _is_num((np as Dictionary).get("radius")):
		return maxf(float((np as Dictionary)["radius"]), 0.0)
	return 0.0

static func _check_colonies(out: Array[Dictionary], data: Dictionary) -> void:
	var colonies := _list(data, "colonies")
	for j in colonies.size():
		if not (colonies[j] is Dictionary):
			continue
		var pj: Variant = _vec((colonies[j] as Dictionary).get("nest"))
		if pj == null:
			continue
		for i in j:
			if not (colonies[i] is Dictionary):
				continue
			var pi: Variant = _vec((colonies[i] as Dictionary).get("nest"))
			if pi == null:
				continue
			var limit := maxf(MIN_NEST_DISTANCE, _nest_radius(colonies[i]) + _nest_radius(colonies[j]))
			var d: float = (pi as Vector2).distance_to(pj)
			if d < limit:
				out.append(_issue(["colonies", j], "warning",
						"Nest overlaps colony %d's nest (%s apart, at least %s wanted)" % [i + 1, _fmt(d), _fmt(limit)]))
				break

# --- timing ---------------------------------------------------------------------------------

## Lists of video-time items: [path of the list, label]; the caller checks each item's "t".
static func _video_lists(data: Dictionary) -> Array:
	var out: Array = []
	var cam: Variant = data.get("camera")
	if cam is Dictionary:
		out.append([["camera", "surface"], "Camera key"])
		out.append([["camera", "nest"], "Camera key"])
	else:
		out.append([["camera"], "Camera key"])
	out.append([["render", "layout", "modes"], "Layout mode"])
	out.append([["render", "captions"], "Caption"])
	out.append([["render", "fades"], "Fade"])
	out.append([["render", "grade"], "Grade point"])
	out.append([["render", "story_marker"], "Story marker"])
	return out

static func _get_at(data: Variant, path: Array) -> Variant:
	var cur: Variant = data
	for key: Variant in path:
		if cur is Dictionary and key is String and (cur as Dictionary).has(key):
			cur = (cur as Dictionary)[key]
		else:
			return null
	return cur

static func _check_timing(out: Array[Dictionary], data: Dictionary) -> void:
	var map := TimelineModel.time_map(data)
	var duration := map.duration
	for spec: Array in _video_lists(data):
		var list: Variant = _get_at(data, spec[0])
		if not (list is Array):
			continue
		for i in (list as Array).size():
			var e: Variant = (list as Array)[i]
			if not (e is Dictionary) or not _is_num((e as Dictionary).get("t")):
				continue
			var t := float(e["t"])
			if t > duration + 1e-6:
				var path: Array = (spec[0] as Array).duplicate()
				path.append(i)
				path.append("t")
				out.append(_issue(path, "warning", "%s at %ss is after the video ends (%ss)" % [spec[1], _fmt(t), _fmt(duration)]))
	var end_sim := map.sim_time_at(duration)
	var events := _list(data, "events")
	for i in events.size():
		var e: Variant = events[i]
		if not (e is Dictionary) or not _is_num((e as Dictionary).get("t")):
			continue
		var t := float(e["t"])
		if t > end_sim + 1e-6:
			out.append(_issue(["events", i, "t"], "warning",
					"Event at %ss (sim time) never happens: the video ends at sim time %ss" % [_fmt(t), _fmt(end_sim)]))

# --- captions -------------------------------------------------------------------------------

static func _check_captions(out: Array[Dictionary], data: Dictionary) -> void:
	var render: Variant = data.get("render")
	if not (render is Dictionary):
		return
	var captions: Variant = (render as Dictionary).get("captions")
	if not (captions is Array):
		return
	var frame := _frame(data)
	var safe := frame.safe_rect()
	var column := Presentation.caption_column(frame)
	var s := frame.scale()
	var font := ThemeDB.fallback_font
	for i in (captions as Array).size():
		var c: Variant = (captions as Array)[i]
		if not (c is Dictionary):
			continue
		var cd: Dictionary = c
		var style: Variant = Presentation.STYLES.get(str(cd.get("style", "caption")))
		if style == null:
			style = Presentation.STYLES["caption"]
		var fs := roundi(int((style as Dictionary)["size"]) * s)
		var box := font.get_multiline_string_size(str(cd.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, column.y, fs)
		var top := Presentation.caption_top(frame, str(cd.get("pos", "bottom")), box.y)
		var left := column.x + (column.y - minf(box.x, column.y)) * 0.5
		var rect := Rect2(left, top, minf(box.x, column.y), box.y)
		var tol := SAFE_TOLERANCE
		if rect.position.x < safe.position.x - tol or rect.end.x > safe.end.x + tol \
				or rect.position.y < safe.position.y - tol or rect.end.y > safe.end.y + tol:
			out.append(_issue(["render", "captions", i], "warning",
					"Caption reaches into the unsafe margin of the '%s' safe zones" % frame.safe_zones))

## The output frame of `data`, tolerating a malformed "output" section (no errors pushed).
static func _frame(data: Dictionary) -> OutputFrame:
	var out: Variant = data.get("output")
	var size := OutputFrame.DEFAULT_SIZE
	var zones := OutputFrame.DEFAULT_SAFE_ZONES
	if out is Dictionary:
		var od: Dictionary = out
		if od.get("safe_zones") is String and OutputFrame.SAFE_ZONES.has(od["safe_zones"]):
			zones = od["safe_zones"]
		var sz: Variant = od.get("size")
		if sz is Array and (sz as Array).size() == 2 and _is_num(sz[0]) and _is_num(sz[1]):
			var v := Vector2i(int(sz[0]), int(sz[1]))
			if OutputFrame.valid_size(v):
				size = v
	return OutputFrame.new(size, zones)
