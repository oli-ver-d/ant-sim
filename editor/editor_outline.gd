class_name EditorOutline
extends RefCounted
## The scenario editor's outline tree (rows of sections and their items) and
## the world-space bounds of an item, computed from the scenario dictionary
## alone so they can be tested without the GUI. Paths are as in ScenarioDoc.

## Top-level keys shown under the "Scenario" row (general settings).
const SCENARIO_KEYS: Array[String] = ["name", "description", "seed", "duration", "warmup", "ticks_per_frame", "max_agents"]
## Sections in display order: key, label, and whether it is shown even when absent.
const SECTIONS: Array[Array] = [
	["colonies", "Colonies", true], ["food", "Food", true], ["obstacles", "Obstacles", true],
	["ground", "Ground", true], ["scenery", "Scenery", false], ["debris", "Debris", false],
	["events", "Events", false], ["camera", "Camera", false], ["render", "Render", false],
	["world", "World", true], ["output", "Output", true],
]
## Timed lists under "render" shown as outline rows: key, row label, item label.
const RENDER_TIMED: Array[Array] = [["captions", "Captions", "Caption"], ["fades", "Fades", "Fade"],
		["grade", "Grade", "Grade"], ["story_marker", "Story marker", "Marker"], ["layout", "Layout modes", "Mode"]]
const NEST_HALF := 60.0
const FOOD_RADIUS := 30.0
const PROP_RADIUS := 20.0

# --- outline -------------------------------------------------------------------

static func build(data: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	_row(rows, "Scenario", [], 0)
	if data.get("ticks_per_frame") is Array:
		# The speed schedule's points (its items are selected on the timeline).
		_row(rows, "Speed", ["ticks_per_frame"], 0)
		_list_rows(rows, data["ticks_per_frame"], ["ticks_per_frame"], _speed_label)
	for spec: Array in SECTIONS:
		var key: String = spec[0]
		if not data.has(key) and not spec[2]:
			continue
		_row(rows, spec[1], [key], 0)
		var v: Variant = data.get(key)
		match key:
			"colonies":
				_list_rows(rows, v, [key], _colony_label)
			"food":
				_list_rows(rows, v, [key], _food_label)
			"obstacles":
				_list_rows(rows, v, [key], _obstacle_label)
			"ground":
				if v is Dictionary and v.get("regions") is Array:
					_list_rows(rows, v["regions"], [key, "regions"], _region_label, 1)
			"scenery":
				_list_rows(rows, v, [key], _scenery_label)
			"debris":
				_list_rows(rows, v, [key], _debris_label)
			"events":
				_list_rows(rows, v, [key], _event_label)
			"camera":
				if v is Array:
					_list_rows(rows, v, [key], _camera_label)
				elif v is Dictionary:
					for track: String in ["surface", "nest"]:
						if v.has(track):
							_row(rows, track.capitalize() + " camera", [key, track], 1)
							_list_rows(rows, v[track], [key, track], _camera_label, 2)
			"render":
				if v is Dictionary:
					for timed: Array in RENDER_TIMED:
						var list: Variant = v.get(timed[0])
						if timed[0] == "layout":
							list = v["layout"].get("modes") if v.get("layout") is Dictionary else null
						if list is Array:
							var p: Array = ["render", "layout", "modes"] if timed[0] == "layout" else ["render", timed[0]]
							_row(rows, timed[1], p, 1)
							_list_rows(rows, list, p, _timed_label.bind(timed[2]), 2)
	for key: Variant in data.keys():
		if not _is_known(key):
			_row(rows, str(key), [key], 0)
	return rows

static func _row(rows: Array[Dictionary], label: String, path: Array, depth: int) -> void:
	rows.append({"label": label, "path": path, "depth": depth})

static func _list_rows(rows: Array[Dictionary], list: Variant, base: Array, label_fn: Callable, depth: int = 1) -> void:
	if not list is Array:
		return
	for i: int in list.size():
		_row(rows, label_fn.call(i, list[i]), base + [i], depth)

static func _is_known(key: Variant) -> bool:
	if key is String:
		if key in SCENARIO_KEYS:
			return true
		for spec: Array in SECTIONS:
			if spec[0] == key:
				return true
	return false

# --- labels ----------------------------------------------------------------------

static func _num(v: Variant) -> String:
	if v is float or v is int:
		return ScenarioJson.number(float(v))
	return "?"

## "x,y" of a [x, y] value, or "".
static func _xy(v: Variant) -> String:
	var p: Variant = _vec(v)
	return "" if p == null else "%s,%s" % [_num(p.x), _num(p.y)]

static func _at_suffix(v: Variant) -> String:
	var s := _xy(v)
	return "" if s == "" else " @ " + s

static func _str(d: Dictionary, key: String, default: String = "?") -> String:
	var v: Variant = d.get(key)
	return v if v is String and v != "" else default

static func _colony_label(i: int, c: Variant) -> String:
	if not c is Dictionary:
		return "Colony %d: ?" % i
	return "Colony %d: %s%s" % [i, _str(c, "species"), _at_suffix(c.get("nest"))]

static func _food_label(i: int, f: Variant) -> String:
	if not f is Dictionary:
		return "Food %d: ?" % i
	return "Food %d: %s%s" % [i, _str(f, "type"), _at_suffix(f.get("pos"))]

static func _obstacle_label(i: int, o: Variant) -> String:
	if not o is Dictionary:
		return "Obstacle %d: ?" % i
	var s := "Obstacle %d: %s" % [i, _str(o, "shape")]
	if o.get("kind") is String:
		s += " " + o["kind"]
	return s

static func _region_label(i: int, r: Variant) -> String:
	if not r is Dictionary:
		return "Region %d: ?" % i
	var s := "Region %d: %s" % [i, _str(r, "material")]
	if r.get("shape") is String:
		s += " " + r["shape"]
	return s

static func _scenery_label(i: int, s: Variant) -> String:
	if not s is Dictionary:
		return "Prop %d: ?" % i
	if s.has("scatter"):
		var sc: Variant = s["scatter"]
		return "Scatter %d: %s" % [i, _str(sc, "preset", "scatter") if sc is Dictionary else "scatter"]
	return "Prop %d: %s%s" % [i, _str(s, "type"), _at_suffix(_prop_anchor(s))]

static func _debris_label(i: int, d: Variant) -> String:
	if not d is Dictionary:
		return "Debris %d: ?" % i
	return "Debris %d: %s%s" % [i, _str(d, "type"), _at_suffix(d.get("pos"))]

static func _event_label(i: int, e: Variant) -> String:
	if not e is Dictionary:
		return "Event %d: ?" % i
	return "Event %d: %s @ %ss" % [i, _str(e, "type"), _num(e.get("t"))]

static func _speed_label(i: int, p: Variant) -> String:
	if not p is Dictionary:
		return "Point %d: ?" % i
	var s := "Point %d: %ss" % [i, _num(p.get("t"))]
	if p.has("tpf"):
		s += " tpf " + _num(p["tpf"])
	if p.has("jump"):
		s += " jump " + _num(p["jump"])
	return s

## "Caption 2: 12s A queen lands" (the text or mode when there is one).
static func _timed_label(i: int, p: Variant, noun: String) -> String:
	if not p is Dictionary:
		return "%s %d: ?" % [noun, i]
	var s := "%s %d: %ss" % [noun, i, _num(p.get("t"))]
	for key: String in ["text", "mode"]:
		if p.get(key) is String:
			var text: String = (p[key] as String).split("\n")[0]
			s += " " + (text.left(30) + "…" if text.length() > 30 else text)
	return s

static func _camera_label(i: int, k: Variant) -> String:
	if not k is Dictionary:
		return "Camera %d: ?" % i
	var s := "Camera %d: %ss" % [i, _num(k.get("t"))]
	if k.has("follow"):
		s += " follow"
	elif k.has("fit"):
		s += " fit"
	elif _xy(k.get("pos")) != "":
		s += " pos " + _xy(k["pos"])
	return s

## The position a prop is labelled with: its centre, pos or first point.
static func _prop_anchor(p: Dictionary) -> Variant:
	for key: String in ["center", "pos"]:
		if p.has(key):
			return p[key]
	var pts: Variant = p.get("points")
	if pts is Array and not pts.is_empty():
		return pts[0]
	return null

# --- bounds ----------------------------------------------------------------------

## The path of the item (row-level) that `path` lies in, or [] if none.
static func _item_path(path: Array) -> Array:
	if path.size() < 2:
		return []
	match path[0]:
		"colonies", "food", "obstacles", "scenery", "debris", "events":
			return path.slice(0, 2)
		"ground":
			return path.slice(0, 3) if path.size() >= 3 and path[1] == "regions" else []
		"camera":
			if path.size() >= 3 and path[1] is String:
				return path.slice(0, 3)
			return path.slice(0, 2)
	return []

static func _lookup(data: Dictionary, path: Array) -> Variant:
	var v: Variant = data
	for key: Variant in path:
		if v is Dictionary and v.has(key):
			v = v[key]
		elif v is Array and key is int and key >= 0 and key < v.size():
			v = v[key]
		else:
			return null
	return v

## World-space bounds of the item at (or containing) `path`, or Rect2() (no
## area) when it has no position.
static func item_bounds(data: Dictionary, path: Array) -> Rect2:
	var ip := _item_path(path)
	if ip.is_empty():
		return Rect2()
	var item: Variant = _lookup(data, ip)
	if not item is Dictionary:
		return Rect2()
	var b := Rect2()
	match ip[0]:
		"colonies":
			b = _box(item.get("nest"), NEST_HALF)
		"food":
			b = _circle(item.get("pos"), _radius(item, FOOD_RADIUS))
		"obstacles":
			b = _shape_bounds(item, true)
		"ground":
			b = _shape_bounds(item, false)
		"scenery":
			if item.has("scatter"):
				var sc: Variant = item["scatter"]
				b = _rect(sc.get("rect")) if sc is Dictionary else Rect2()
			else:
				b = _prop_bounds(item)
		"debris":
			b = _debris_bounds(item)
		"events":
			b = _event_bounds(item)
		"camera":
			b = _box(item.get("pos"), 20.0)
	return b if b.has_area() else Rect2()

static func _vec(v: Variant) -> Variant:
	if v is Array and v.size() >= 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int):
		return Vector2(float(v[0]), float(v[1]))
	return null

static func _radius(d: Dictionary, default: float) -> float:
	var r: Variant = d.get("radius")
	return float(r) if (r is float or r is int) and r > 0 else default

static func _box(centre: Variant, half: float) -> Rect2:
	var p: Variant = _vec(centre)
	return Rect2() if p == null else Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0)

static func _circle(centre: Variant, radius: float) -> Rect2:
	return _box(centre, radius)

static func _rect(v: Variant) -> Rect2:
	if v is Array and v.size() >= 4:
		for n: Variant in v:
			if not (n is float or n is int):
				return Rect2()
		return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return Rect2()

## Bounding box of a [[x, y], ...] list grown by `pad`.
static func _points_bounds(pts: Variant, pad: float) -> Rect2:
	if not pts is Array:
		return Rect2()
	var b := Rect2()
	var any := false
	for pt: Variant in pts:
		var p: Variant = _vec(pt)
		if p == null:
			continue
		if any:
			b = b.expand(p)
		else:
			b = Rect2(p, Vector2.ZERO)
			any = true
	return b.grow(pad) if any else Rect2()

## An obstacle-style shape; without "shape" it is inferred from the keys when
## `infer`, and there is no area (whole world) otherwise.
static func _shape_bounds(d: Dictionary, infer: bool) -> Rect2:
	var shape: String = d["shape"] if d.get("shape") is String else ""
	if shape == "" and infer:
		shape = "polyline" if d.has("points") else ("rect" if d.has("rect") else "circle")
	match shape:
		"circle":
			return _circle(d.get("center"), _radius(d, 0.0))
		"rect":
			return _rect(d.get("rect"))
		"polyline":
			var w: Variant = d.get("width")
			return _points_bounds(d.get("points"), (float(w) if w is float or w is int else 16.0) * 0.5)
		"polygon":
			return _points_bounds(d.get("points"), 0.0)
	return Rect2()

static func _prop_bounds(p: Dictionary) -> Rect2:
	if p.get("points") is Array:
		var w: Variant = p.get("width")
		return _points_bounds(p["points"], (float(w) if w is float or w is int else PROP_RADIUS * 2.0) * 0.5)
	for key: String in ["center", "pos"]:
		if p.has(key):
			return _circle(p[key], _radius(p, PROP_RADIUS))
	return Rect2()

static func _debris_bounds(d: Dictionary) -> Rect2:
	var r := PROP_RADIUS * 0.5
	var length: Variant = d.get("length")
	if length is float or length is int:
		r = maxf(r, float(length) * 0.5)
	return _circle(d.get("pos"), maxf(r, _radius(d, 0.0)))

static func _event_bounds(e: Dictionary) -> Rect2:
	var area: Variant = e.get("area")
	if area is Dictionary:
		if area.has("rect"):
			return _rect(area["rect"])
		return _circle(area.get("center"), _radius(area, 0.0))
	if e.get("food") is Dictionary:
		return _circle(e["food"].get("pos"), _radius(e["food"], FOOD_RADIUS))
	if e.get("obstacle") is Dictionary:
		return _shape_bounds(e["obstacle"], true)
	if e.get("colony") is Dictionary:
		return _box(e["colony"].get("nest"), NEST_HALF)
	if e.get("scenery") is Dictionary and not e["scenery"].has("scatter"):
		return _prop_bounds(e["scenery"])
	if e.get("scatter") is Dictionary:
		return _circle(e["scatter"].get("near"), _radius(e["scatter"], 150.0))
	if e.get("at") != null:
		return _box(e.get("at"), 20.0)
	return Rect2()

# --- reordering ------------------------------------------------------------------

## What dropping the item at `from_path` on the row `onto_path` does, for
## ScenarioDoc.move_item: {} if not allowed (or nothing changes), else
## {"path": from_path, "to": final index}. Both must be items of the same list.
## `section` is Tree's drop section: -1 above the target, 0 on it, 1 below it
## (on and below both put the item after the target).
static func drop_move(from_path: Array, onto_path: Array, section: int) -> Dictionary:
	if from_path.is_empty() or onto_path.size() != from_path.size():
		return {}
	if not (from_path[-1] is int and onto_path[-1] is int):
		return {}
	if from_path.slice(0, -1) != onto_path.slice(0, -1):
		return {}
	var from: int = from_path[-1]
	var target: int = onto_path[-1]
	var insert_at := target if section < 0 else target + 1
	var to := insert_at - 1 if insert_at > from else insert_at
	if to == from or to < 0:
		return {}
	return {"path": from_path, "to": to}

# --- paths -----------------------------------------------------------------------

## The section row's path for any path.
static func section_of(path: Array) -> Array:
	if path.is_empty() or not path[0] is String:
		return []
	var key: String = path[0]
	if key in SCENARIO_KEYS:
		return []
	return [key]

## Index of the deepest row whose path is a prefix of `path`, or -1.
static func row_for(rows: Array[Dictionary], path: Array) -> int:
	var best := -1
	var best_len := -1
	for i: int in rows.size():
		var rp: Array = rows[i]["path"]
		if rp.size() > path.size() or rp.size() <= best_len:
			continue
		if path.slice(0, rp.size()) == rp:
			best = i
			best_len = rp.size()
	return best
