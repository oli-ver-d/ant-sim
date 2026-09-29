class_name GizmoGeometry
extends RefCounted
## Pure geometry behind the scenario editor's canvas gizmos: the shapes (with
## their handles) of every positioned scenario item, hit testing, and edits that
## return a modified copy of an item. Works on the scenario Dictionary alone, so
## it is testable without the GUI. Paths are as in ScenarioDoc.
##
## A shape is a Dictionary:
##   "kind": "circle" | "rect" | "polyline" | "polygon" | "point"
##   "path": doc path of the Dictionary holding the shape's keys
##   "role": "body" (the item), "area" (scatter/rain/drop area) or "clear"
##   circle/point: "center": Vector2, "center_key": String; circle also
##     "radius": float, "radius_key": String ("" when not editable)
##   rect: "rect": Rect2 (key "rect")
##   polyline/polygon: "points": PackedVector2Array (key "points"); polyline "width"
##   optional "soft": float (ground regions), "hard": bool (clear shapes)

const DEFAULT_SOFT := 40.0
const DEFAULT_DROP_RADIUS := 150.0
const DEFAULT_TWIG_LENGTH := 34.0
const DEFAULT_PEBBLE_RADIUS := 5.0
const DEFAULT_PROP_WIDTH := 30.0
const DEFAULT_CLEAR_WIDTH := 40.0
const DEFAULT_OBSTACLE_WIDTH := 16.0

# --- item paths -----------------------------------------------------------------------

## Every item path in draw order.
static func item_paths(data: Dictionary) -> Array:
	var out: Array = []
	for key: String in ["colonies", "food", "obstacles"]:
		_append_list(out, data.get(key), [key])
	var ground: Variant = data.get("ground")
	if ground is Dictionary:
		_append_list(out, ground.get("regions"), ["ground", "regions"])
	for key: String in ["scenery", "debris", "events"]:
		_append_list(out, data.get(key), [key])
	var cam: Variant = data.get("camera")
	if cam is Array:
		_append_list(out, cam, ["camera"])
	elif cam is Dictionary:
		for track: String in ["surface", "nest"]:
			_append_list(out, cam.get(track), ["camera", track])
	return out

static func _append_list(out: Array, list: Variant, base: Array) -> void:
	if list is Array:
		for i: int in list.size():
			out.append(base + [i])

# --- small helpers --------------------------------------------------------------------

static func _is_num(v: Variant) -> bool:
	return v is float or v is int

static func _vec(v: Variant) -> Variant:
	if v is Array and v.size() >= 2 and _is_num(v[0]) and _is_num(v[1]):
		return Vector2(float(v[0]), float(v[1]))
	return null

static func _rect_of(v: Variant) -> Variant:
	if v is Array and v.size() >= 4:
		for i: int in 4:
			if not _is_num(v[i]):
				return null
		return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return null

## The points of a [[x, y], ...] list, or null when any entry is malformed or it is empty.
static func _points_of(v: Variant) -> Variant:
	if not v is Array or v.is_empty():
		return null
	var out := PackedVector2Array()
	for e: Variant in v:
		var p: Variant = _vec(e)
		if p == null:
			return null
		out.append(p)
	return out

## Radius when numeric and > 0, else `default`.
static func _radius(d: Dictionary, default: float) -> float:
	var r: Variant = d.get("radius")
	return float(r) if _is_num(r) and r > 0 else default

static func _width(d: Dictionary, default: float) -> float:
	var w: Variant = d.get("width")
	return float(w) if _is_num(w) and w > 0 else default

static func lookup(data: Variant, path: Array) -> Variant:
	var v: Variant = data
	for key: Variant in path:
		if v is Dictionary and v.has(key):
			v = v[key]
		elif v is Array and key is int and key >= 0 and key < v.size():
			v = v[key]
		else:
			return null
	return v

static func _circle(path: Array, role: String, center: Vector2, center_key: String, radius: float, radius_key: String) -> Dictionary:
	return {"kind": "circle", "path": path, "role": role, "center": center, "center_key": center_key,
			"radius": radius, "radius_key": radius_key}

static func _point(path: Array, role: String, center: Vector2, center_key: String) -> Dictionary:
	return {"kind": "point", "path": path, "role": role, "center": center, "center_key": center_key}

static func _rect_shape(path: Array, role: String, r: Rect2) -> Dictionary:
	return {"kind": "rect", "path": path, "role": role, "rect": r}

static func _poly(path: Array, role: String, kind: String, pts: PackedVector2Array, width: float) -> Dictionary:
	var s := {"kind": kind, "path": path, "role": role, "points": pts}
	if kind == "polyline":
		s["width"] = width
	return s

# --- shapes ---------------------------------------------------------------------------

static func shapes(data: Dictionary, item_path: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if item_path.is_empty():
		return out
	var item: Variant = lookup(data, item_path)
	if not item is Dictionary:
		return out
	match item_path[0]:
		"colonies":
			var c: Variant = _vec(item.get("nest"))
			if c != null:
				out.append(_circle(item_path, "body", c, "nest", EditorOutline.NEST_HALF, ""))
		"food":
			_food_shapes(out, item, item_path, "body")
		"obstacles":
			_obstacle_shapes(out, item, item_path, "body", true)
		"ground":
			_obstacle_shapes(out, item, item_path, "body", false)
			for s: Dictionary in out:
				var soft: Variant = item.get("soft")
				s["soft"] = float(soft) if _is_num(soft) and soft > 0 else DEFAULT_SOFT
		"scenery":
			_scenery_shapes(out, item, item_path)
		"debris":
			_debris_shapes(out, item, item_path)
		"events":
			_event_shapes(out, item, item_path)
		"camera":
			var p: Variant = _vec(item.get("pos"))
			if p != null:
				out.append(_point(item_path, "body", p, "pos"))
			elif item.get("follow") is Dictionary:
				var n: Variant = _vec(item["follow"].get("near"))
				if n != null:
					out.append(_point(item_path + ["follow"], "body", n, "near"))
	return out

static func _food_shapes(out: Array[Dictionary], d: Dictionary, path: Array, role: String) -> void:
	var c: Variant = _vec(d.get("pos"))
	if c != null:
		out.append(_circle(path, role, c, "pos", _radius(d, EditorOutline.FOOD_RADIUS), "radius"))

## An obstacle-style shape. Without "shape" it is inferred when `infer`, else there is none.
static func _obstacle_shapes(out: Array[Dictionary], d: Dictionary, path: Array, role: String, infer: bool) -> void:
	var kind: String = d["shape"] if d.get("shape") is String else ""
	if kind == "" and infer:
		kind = "polyline" if d.has("points") else ("rect" if d.has("rect") else "circle")
	match kind:
		"circle":
			var c: Variant = _vec(d.get("center"))
			if c != null:
				out.append(_circle(path, role, c, "center", _radius(d, 0.0), "radius"))
		"rect":
			var r: Variant = _rect_of(d.get("rect"))
			if r != null:
				out.append(_rect_shape(path, role, r))
		"polyline", "polygon":
			var pts: Variant = _points_of(d.get("points"))
			if pts != null:
				out.append(_poly(path, role, kind, pts, _width(d, DEFAULT_OBSTACLE_WIDTH)))

static func _scenery_shapes(out: Array[Dictionary], d: Dictionary, path: Array) -> void:
	if d.has("scatter"):
		var sc: Variant = d["scatter"]
		if not sc is Dictionary:
			return
		var spath := path + ["scatter"]
		var r: Variant = _rect_of(sc.get("rect"))
		if r != null:
			out.append(_rect_shape(spath, "area", r))
		var clear: Variant = sc.get("clear")
		if clear is Array:
			for j: int in clear.size():
				if clear[j] is Dictionary:
					_clear_shape(out, clear[j], spath + ["clear", j])
		return
	var pts: Variant = _points_of(d.get("points")) if d.get("points") is Array else null
	if pts != null:
		out.append(_poly(path, "body", "polyline", pts, _width(d, DEFAULT_PROP_WIDTH)))
		return
	for key: String in ["center", "pos"]:
		if d.has(key):
			var c: Variant = _vec(d[key])
			if c != null:
				out.append(_circle(path, "body", c, key, _radius(d, EditorOutline.PROP_RADIUS), "radius"))
			return

## A scatter "clear" shape; shape defaults to a polyline as in Scatter._shape_zone.
static func _clear_shape(out: Array[Dictionary], d: Dictionary, path: Array) -> void:
	var kind: String = d["shape"] if d.get("shape") is String else "polyline"
	var n := out.size()
	match kind:
		"circle":
			var c: Variant = _vec(d.get("center"))
			if c != null:
				out.append(_circle(path, "clear", c, "center", _radius(d, 0.0), "radius"))
		"rect":
			var r: Variant = _rect_of(d.get("rect"))
			if r != null:
				out.append(_rect_shape(path, "clear", r))
		_:
			var pts: Variant = _points_of(d.get("points"))
			if pts != null:
				out.append(_poly(path, "clear", "polyline", pts, _width(d, DEFAULT_CLEAR_WIDTH)))
	if out.size() > n:
		var reserve: Variant = d.get("reserve", false)
		out[n]["hard"] = not ((reserve is bool and reserve) or (_is_num(reserve) and reserve != 0))

static func _debris_shapes(out: Array[Dictionary], d: Dictionary, path: Array) -> void:
	var c: Variant = _vec(d.get("pos"))
	if c == null:
		return
	if not d.has("type") or d["type"] == "twig":
		var length: Variant = d.get("length")
		var l: float = float(length) if _is_num(length) and length > 0 else DEFAULT_TWIG_LENGTH
		out.append(_circle(path, "body", c, "pos", l * 0.5, ""))
	else:
		out.append(_circle(path, "body", c, "pos", _radius(d, DEFAULT_PEBBLE_RADIUS), "radius"))

static func _event_shapes(out: Array[Dictionary], e: Dictionary, path: Array) -> void:
	match e.get("type"):
		"rain":
			var a: Variant = e.get("area")
			if a is Dictionary:
				var apath := path + ["area"]
				if a.has("rect"):
					var r: Variant = _rect_of(a["rect"])
					if r != null:
						out.append(_rect_shape(apath, "area", r))
				else:
					var c: Variant = _vec(a.get("center"))
					if c != null:
						out.append(_circle(apath, "area", c, "center", _radius(a, 0.0), "radius"))
		"spawn_food":
			if e.get("food") is Dictionary:
				_food_shapes(out, e["food"], path + ["food"], "body")
		"add_obstacle", "remove_obstacle":
			if e.get("obstacle") is Dictionary:
				_obstacle_shapes(out, e["obstacle"], path + ["obstacle"], "body", true)
		"add_colony":
			if e.get("colony") is Dictionary:
				var c: Variant = _vec(e["colony"].get("nest"))
				if c != null:
					out.append(_circle(path + ["colony"], "body", c, "nest", EditorOutline.NEST_HALF, ""))
		"add_scenery":
			var sc: Variant = e.get("scenery")
			if sc is Dictionary:
				_scenery_shapes(out, sc, path + ["scenery"])
			elif sc is Array:
				for j: int in sc.size():
					if sc[j] is Dictionary:
						_scenery_shapes(out, sc[j], path + ["scenery", j])
		"remove_scenery":
			var at: Variant = _vec(e.get("at"))
			if at != null:
				out.append(_point(path, "body", at, "at"))
		"drop_debris":
			if e.get("scatter") is Dictionary:
				var near: Variant = _vec(e["scatter"].get("near"))
				if near != null:
					out.append(_circle(path + ["scatter"], "area", near, "near", _radius(e["scatter"], DEFAULT_DROP_RADIUS), "radius"))
			var pieces: Variant = e.get("debris")
			if pieces is Array:
				for j: int in pieces.size():
					if pieces[j] is Dictionary:
						_debris_shapes(out, pieces[j], path + ["debris", j])

# --- bounds and containment --------------------------------------------------------------

static func shape_bounds(shape: Dictionary) -> Rect2:
	match shape["kind"]:
		"circle":
			var r: float = shape["radius"]
			return Rect2(shape["center"] - Vector2(r, r), Vector2(r, r) * 2.0)
		"point":
			return Rect2(shape["center"], Vector2.ZERO)
		"rect":
			return (shape["rect"] as Rect2).abs()
		"polyline", "polygon":
			var pts: PackedVector2Array = shape["points"]
			if pts.is_empty():
				return Rect2()
			var b := Rect2(pts[0], Vector2.ZERO)
			for p: Vector2 in pts:
				b = b.expand(p)
			return b.grow(float(shape["width"]) * 0.5) if shape["kind"] == "polyline" else b
	return Rect2()

static func item_bounds(data: Dictionary, item_path: Array) -> Rect2:
	var b := Rect2()
	var any := false
	for s: Dictionary in shapes(data, item_path):
		var sb := shape_bounds(s)
		b = sb if not any else b.merge(sb)
		any = true
	return b

static func _dist_to_polyline(pts: PackedVector2Array, p: Vector2, closed: bool) -> float:
	if pts.is_empty():
		return INF
	if pts.size() == 1:
		return p.distance_to(pts[0])
	var best := INF
	var n := pts.size() if closed else pts.size() - 1
	for i: int in n:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % pts.size()])
		best = minf(best, p.distance_to(q))
	return best

static func shape_contains(shape: Dictionary, p: Vector2, tol: float) -> bool:
	match shape["kind"]:
		"circle":
			return p.distance_to(shape["center"]) <= float(shape["radius"]) + tol
		"point":
			return p.distance_to(shape["center"]) <= tol
		"rect":
			return (shape["rect"] as Rect2).abs().grow(tol).has_point(p)
		"polyline":
			return _dist_to_polyline(shape["points"], p, false) <= float(shape["width"]) * 0.5 + tol
		"polygon":
			var pts: PackedVector2Array = shape["points"]
			if pts.size() >= 3 and Geometry2D.is_point_in_polygon(p, pts):
				return true
			return _dist_to_polyline(pts, p, true) <= tol
	return false

static func _shape_area(shape: Dictionary) -> float:
	match shape["kind"]:
		"circle":
			return PI * float(shape["radius"]) * float(shape["radius"])
		"rect":
			var s: Vector2 = (shape["rect"] as Rect2).abs().size
			return s.x * s.y
		"polyline":
			var pts: PackedVector2Array = shape["points"]
			var length := 0.0
			for i: int in pts.size() - 1:
				length += pts[i].distance_to(pts[i + 1])
			var w: float = shape["width"]
			return length * w + PI * w * w * 0.25
		"polygon":
			var pts: PackedVector2Array = shape["points"]
			var a := 0.0
			for i: int in pts.size():
				var q := pts[(i + 1) % pts.size()]
				a += pts[i].x * q.y - q.x * pts[i].y
			return absf(a) * 0.5
	return 0.0

## The item whose smallest containing shape is smallest at `p` (later items win ties), or null.
static func hit_item(data: Dictionary, p: Vector2, tol: float) -> Variant:
	var best: Variant = null
	var best_area := INF
	for ip: Array in item_paths(data):
		for s: Dictionary in shapes(data, ip):
			if shape_contains(s, p, tol):
				var a := _shape_area(s)
				if a <= best_area:
					best_area = a
					best = ip
	return best

# --- handles ---------------------------------------------------------------------------

static func handles(shape: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match shape["kind"]:
		"circle":
			out.append({"role": "center", "index": 0, "pos": shape["center"]})
			if shape["radius_key"] != "":
				out.append({"role": "radius", "index": 0, "pos": shape["center"] + Vector2(float(shape["radius"]), 0.0)})
		"point":
			out.append({"role": "center", "index": 0, "pos": shape["center"]})
		"rect":
			var r: Rect2 = shape["rect"]
			var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
			for i: int in 4:
				out.append({"role": "corner", "index": i, "pos": corners[i]})
		"polyline", "polygon":
			var pts: PackedVector2Array = shape["points"]
			for i: int in pts.size():
				out.append({"role": "point", "index": i, "pos": pts[i]})
	return out

## The nearest handle within `tol` over all the item's shapes, or {}.
static func hit_handle(data: Dictionary, item_path: Array, p: Vector2, tol: float) -> Dictionary:
	var best := {}
	var best_d := INF
	var shp := shapes(data, item_path)
	for si: int in shp.size():
		for h: Dictionary in handles(shp[si]):
			var d := p.distance_to(h["pos"])
			if d > tol:
				continue
			var better := d < best_d - 0.0001
			if not better and absf(d - best_d) <= 0.0001 and not best.is_empty():
				better = best["role"] == "center" and h["role"] != "center"
			if better:
				best_d = d
				best = {"shape": si, "role": h["role"], "index": h["index"], "pos": h["pos"]}
	return best

# --- edits -----------------------------------------------------------------------------

static func _vec_arr(v: Vector2) -> Array:
	return [roundi(v.x), roundi(v.y)]

static func _rect_arr(r: Rect2) -> Array:
	return [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]

static func _points_arr(pts: PackedVector2Array) -> Array:
	var out: Array = []
	for p: Vector2 in pts:
		out.append(_vec_arr(p))
	return out

## A deep copy of the item, and the dictionary in it that holds `shape`'s keys.
static func _copy_item(data: Dictionary, item_path: Array) -> Variant:
	var item: Variant = lookup(data, item_path)
	return item.duplicate(true) if item is Dictionary else null

static func _sub(item: Dictionary, item_path: Array, shape: Dictionary) -> Variant:
	return lookup(item, (shape["path"] as Array).slice(item_path.size()))

static func _translate(sub: Dictionary, s: Dictionary, delta: Vector2) -> void:
	match s["kind"]:
		"circle", "point":
			sub[s["center_key"]] = _vec_arr(s["center"] + delta)
		"rect":
			var r: Rect2 = s["rect"]
			sub["rect"] = _rect_arr(Rect2(r.position + delta, r.size))
		"polyline", "polygon":
			var pts := PackedVector2Array()
			for p: Vector2 in s["points"]:
				pts.append(p + delta)
			sub["points"] = _points_arr(pts)

## Every shape of the item translated by `delta`.
static func moved(data: Dictionary, item_path: Array, delta: Vector2) -> Dictionary:
	var item: Variant = _copy_item(data, item_path)
	if item == null:
		return {}
	for s: Dictionary in shapes(data, item_path):
		var sub: Variant = _sub(item, item_path, s)
		if sub is Dictionary:
			_translate(sub, s, delta)
	return item

## The item after dragging `handle` (from hit_handle) to `to`.
static func dragged(data: Dictionary, item_path: Array, handle: Dictionary, to: Vector2) -> Dictionary:
	var item: Variant = _copy_item(data, item_path)
	if item == null:
		return {}
	var shp := shapes(data, item_path)
	var si: int = handle.get("shape", -1)
	if si < 0 or si >= shp.size():
		return item
	var s := shp[si]
	var sub: Variant = _sub(item, item_path, s)
	if not sub is Dictionary:
		return item
	var index: int = handle.get("index", 0)
	match handle.get("role"):
		"center":
			if s["kind"] == "circle" or s["kind"] == "point":
				sub[s["center_key"]] = _vec_arr(s["center"] + (to - handle["pos"]))
		"radius":
			if s["kind"] == "circle" and s["radius_key"] != "":
				sub[s["radius_key"]] = maxi(1, roundi((s["center"] as Vector2).distance_to(to)))
		"corner":
			if s["kind"] == "rect" and index >= 0 and index < 4:
				var hs := handles(s)
				var opposite: Vector2 = hs[(index + 2) % 4]["pos"]
				var lo := Vector2(minf(to.x, opposite.x), minf(to.y, opposite.y))
				var size := Vector2(maxf(absf(to.x - opposite.x), 1.0), maxf(absf(to.y - opposite.y), 1.0))
				sub["rect"] = [roundi(lo.x), roundi(lo.y), maxi(1, roundi(size.x)), maxi(1, roundi(size.y))]
		"point":
			if (s["kind"] == "polyline" or s["kind"] == "polygon") and index >= 0 and index < (s["points"] as PackedVector2Array).size():
				var pts: PackedVector2Array = s["points"]
				pts[index] = to
				sub["points"] = _points_arr(pts)
	return item

## The item with `p` inserted into the nearest segment of a polyline/polygon shape, or {}.
static func with_point_inserted(data: Dictionary, item_path: Array, shape_index: int, p: Vector2) -> Dictionary:
	var shp := shapes(data, item_path)
	if shape_index < 0 or shape_index >= shp.size():
		return {}
	var s := shp[shape_index]
	if s["kind"] != "polyline" and s["kind"] != "polygon":
		return {}
	var item: Variant = _copy_item(data, item_path)
	var sub: Variant = _sub(item, item_path, s) if item != null else null
	if not sub is Dictionary:
		return {}
	var pts: PackedVector2Array = s["points"]
	var closed: bool = s["kind"] == "polygon"
	var at := pts.size()
	if pts.size() >= 2:
		var best := INF
		var n := pts.size() if closed else pts.size() - 1
		for i: int in n:
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % pts.size()])
			var d := p.distance_to(q)
			if d < best:
				best = d
				at = i + 1
	pts.insert(at, p)
	sub["points"] = _points_arr(pts)
	return item

## The item without point `index` of a polyline/polygon shape, or {} when that leaves too few.
static func with_point_removed(data: Dictionary, item_path: Array, shape_index: int, index: int) -> Dictionary:
	var shp := shapes(data, item_path)
	if shape_index < 0 or shape_index >= shp.size():
		return {}
	var s := shp[shape_index]
	if s["kind"] != "polyline" and s["kind"] != "polygon":
		return {}
	var pts: PackedVector2Array = s["points"]
	var least := 3 if s["kind"] == "polygon" else 2
	if index < 0 or index >= pts.size() or pts.size() - 1 < least:
		return {}
	var item: Variant = _copy_item(data, item_path)
	var sub: Variant = _sub(item, item_path, s) if item != null else null
	if not sub is Dictionary:
		return {}
	pts.remove_at(index)
	sub["points"] = _points_arr(pts)
	return item

static func snap(p: Vector2, grid: float) -> Vector2:
	if grid <= 0.0:
		return p
	return (p / grid).round() * grid
