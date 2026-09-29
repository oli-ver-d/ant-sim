class_name CanvasEditor
extends RefCounted
## Canvas editing in the scenario editor's preview (M16e): what a click, drag
## or key does to the document, with no GUI of its own so tests can drive it
## with world positions. ScenarioEditor feeds it the preview's mouse and key
## events; GizmoLayer draws its state. Geometry (shapes, handles, hit tests,
## the edited item) comes from GizmoGeometry.
##
## Select tool: a click selects the item under the cursor (the smallest shape
## there), dragging it moves it, dragging one of the selected item's handles
## moves that point, corner, centre or radius. Alt-click on a polyline or
## polygon of the selected item inserts a point there. Delete removes the
## last clicked point handle (if the shape keeps enough points) or the item,
## Ctrl+D duplicates it. A drag changes nothing until the mouse is released
## (`drag_item` is what it would write); then it is one doc command.
##
## Place tools (TOOLS): a click puts a new item there (a drag spans a circle's
## radius or a rect); polyline and polygon tools take a point per click and
## finish on Enter or a double click (Esc cancels). The new item is selected
## and the select tool comes back.

## Asks the editor to select an item path (null: nothing).
signal select_requested(path: Variant)
## Something the overlay draws changed.
signal redraw_requested

## id, label, list the item goes in, how it is placed ("click", "circle",
## "rect", "polyline", "polygon").
const TOOLS: Array[Array] = [
	["select", "Select", [], ""],
	["colony", "Colony", ["colonies"], "click"],
	["food", "Food", ["food"], "circle"],
	["wall_rect", "Wall rect", ["obstacles"], "rect"],
	["wall_circle", "Wall circle", ["obstacles"], "circle"],
	["wall_line", "Wall line", ["obstacles"], "polyline"],
	["water", "Water", ["obstacles"], "polygon"],
	["bridge", "Bridge", ["obstacles"], "polyline"],
	["region_circle", "Region circle", ["ground", "regions"], "circle"],
	["region_rect", "Region rect", ["ground", "regions"], "rect"],
	["region_polygon", "Region polygon", ["ground", "regions"], "polygon"],
	["rock", "Rock", ["scenery"], "circle"],
	["plant", "Plant", ["scenery"], "click"],
	["grass", "Grass", ["scenery"], "click"],
	["log", "Log", ["scenery"], "polyline"],
	["scatter", "Scatter", ["scenery"], "rect"],
	["twig", "Twig", ["debris"], "click"],
	["pebble", "Pebble", ["debris"], "click"],
	["rain", "Rain", ["events"], "circle"],
	["camera_key", "Camera key", ["camera"], "click"],
]
## A press that moves less than this (in handle tolerances) is a click.
const DRAG_START := 0.5
const DUPLICATE_OFFSET := Vector2(20, 20)

var doc: ScenarioDoc
var schema: ScenarioSchema
## The selected item path (from GizmoGeometry.item_paths) or null.
var item: Variant = null
var tool := "select"
var snap := false
var grid := 10.0
## The last handle pressed on the selected item ({} if none), for Delete.
var active_handle: Dictionary = {}
## During a drag: the item as it would be written (null otherwise).
var drag_item: Variant = null
## Points of a polyline/polygon being placed.
var poly_points := PackedVector2Array()
## Where the mouse is (world), for the placing preview.
var hover := Vector2.ZERO
## A rect or circle being spanned by a place tool: [from, to] (empty if none).
var span: Array = []

## {"mode": "move" | "handle", "start", "anchor", "handle", "moved"}.
var _drag: Dictionary = {}

func _init(scenario_doc: ScenarioDoc = null, scenario_schema: ScenarioSchema = null) -> void:
	doc = scenario_doc
	schema = scenario_schema

static func tool_spec(id: String) -> Array:
	for t: Array in TOOLS:
		if t[0] == id:
			return t
	return TOOLS[0]

## The item path that `path` (an outline row path) lies in, or null.
static func item_of(data: Dictionary, path: Variant) -> Variant:
	if not path is Array:
		return null
	for ip: Array in GizmoGeometry.item_paths(data):
		if (path as Array).size() >= ip.size() and (path as Array).slice(0, ip.size()) == ip:
			return ip
	return null

func set_selection(path: Variant) -> void:
	var ip: Variant = item_of(doc.data, path)
	if ip != item:
		active_handle = {}
	item = ip
	redraw_requested.emit()

func set_tool(id: String) -> void:
	cancel()
	tool = tool_spec(id)[0]
	redraw_requested.emit()

func snap_point(p: Vector2) -> Vector2:
	return GizmoGeometry.snap(p, grid) if snap else p

# --- mouse -----------------------------------------------------------------------

## Left button pressed at world point `at`; `tol` is the handle tolerance in
## world units. `alt` inserts a point, `double` finishes a polyline/polygon.
func press(at: Vector2, tol: float, alt: bool = false, double: bool = false) -> void:
	hover = at
	var spec := tool_spec(tool)
	var how: String = spec[3]
	if tool != "select":
		if how == "polyline" or how == "polygon":
			if double:
				finish_poly()
			elif poly_points.is_empty() or poly_points[-1].distance_to(snap_point(at)) > tol:
				poly_points.append(snap_point(at))
		else:
			span = [snap_point(at), snap_point(at)]
		redraw_requested.emit()
		return
	if item != null and doc.has_at(item):
		if alt and _insert_point(at, tol):
			return
		var h := GizmoGeometry.hit_handle(doc.data, item, at, tol)
		if not h.is_empty():
			active_handle = h
			_drag = {"mode": "handle", "start": at, "anchor": h["pos"], "handle": h, "moved": false}
			redraw_requested.emit()
			return
	var hit: Variant = GizmoGeometry.hit_item(doc.data, at, tol)
	active_handle = {}
	if hit == null:
		if item != null:
			select_requested.emit(null)
		return
	if hit != item:
		select_requested.emit(hit)
		item = hit
	var shapes := GizmoGeometry.shapes(doc.data, hit)
	var anchor: Vector2 = at
	if not shapes.is_empty():
		var hs := GizmoGeometry.handles(shapes[0])
		if not hs.is_empty():
			anchor = hs[0]["pos"]
	_drag = {"mode": "move", "start": at, "anchor": anchor, "moved": false}
	redraw_requested.emit()

func motion(at: Vector2, tol: float) -> void:
	hover = at
	if not span.is_empty():
		span[1] = snap_point(at)
		redraw_requested.emit()
		return
	if _drag.is_empty() or item == null:
		if not poly_points.is_empty():
			redraw_requested.emit()
		return
	if not _drag["moved"] and at.distance_to(_drag["start"]) < tol * DRAG_START:
		return
	_drag["moved"] = true
	var to: Vector2 = snap_point(_drag["anchor"] + (at - _drag["start"]))
	if _drag["mode"] == "move":
		drag_item = GizmoGeometry.moved(doc.data, item, to - _drag["anchor"])
	else:
		drag_item = GizmoGeometry.dragged(doc.data, item, _drag["handle"], to)
	redraw_requested.emit()

func release(at: Vector2, tol: float) -> void:
	hover = at
	if not span.is_empty():
		var from: Vector2 = span[0]
		var to: Vector2 = snap_point(at)
		span = []
		_place(from, to if from.distance_to(to) >= tol else from)
		return
	if _drag.is_empty():
		return
	var mode: String = _drag["mode"]
	_drag = {}
	var new_item: Variant = drag_item
	drag_item = null
	if new_item is Dictionary and not (new_item as Dictionary).is_empty() and item != null \
			and new_item != doc.get_at(item):
		doc.set_at(item, new_item, ("Move " if mode == "move" else "Edit ") + _name(item))
	redraw_requested.emit()

## Esc: drops a drag, a span or the points placed so far.
func cancel() -> void:
	_drag = {}
	drag_item = null
	span = []
	poly_points = PackedVector2Array()
	redraw_requested.emit()

func dragging() -> bool:
	return drag_item != null

# --- keys ------------------------------------------------------------------------

## Delete: the active point handle if its shape keeps enough points, else the
## selected item. True if something was removed.
func delete_selected() -> bool:
	if item == null or not doc.has_at(item):
		return false
	if active_handle.get("role", "") == "point":
		var fewer := GizmoGeometry.with_point_removed(doc.data, item, active_handle["shape"], active_handle["index"])
		active_handle = {}
		if not fewer.is_empty():
			doc.set_at(item, fewer, "Remove point of " + _name(item))
			return true
	var path: Array = item
	item = null
	active_handle = {}
	doc.remove_at(path, "Delete " + _name(path))
	select_requested.emit(null)
	return true

## Ctrl+D: a copy of the selected item, moved a little, after it. True if made.
func duplicate_selected() -> bool:
	if item == null or not doc.has_at(item):
		return false
	var path: Array = item
	var copy: Variant = GizmoGeometry.moved(doc.data, path, DUPLICATE_OFFSET)
	if not copy is Dictionary or (copy as Dictionary).is_empty():
		copy = doc.get_at(path)
	var at: Array = path.slice(0, -1) + [int(path[-1]) + 1]
	doc.insert_at(at, copy, "Duplicate " + _name(path))
	item = at
	active_handle = {}
	select_requested.emit(at)
	return true

## Enter or a double click: ends the polyline/polygon being placed.
func finish_poly() -> bool:
	var how: String = tool_spec(tool)[3]
	var need := 3 if how == "polygon" else 2
	if poly_points.size() < need:
		return false
	var pts: Array = []
	for p: Vector2 in poly_points:
		pts.append([roundi(p.x), roundi(p.y)])
	poly_points = PackedVector2Array()
	_create(new_item(tool, doc.data, schema, pts[0], pts))
	return true

# --- placing ---------------------------------------------------------------------

## Places the current tool's item from a click at `from` (a drag to `to`
## spans a circle's radius or a rect).
func _place(from: Vector2, to: Vector2) -> void:
	var how: String = tool_spec(tool)[3]
	var extent: Variant = null
	if from != to:
		if how == "circle":
			extent = from.distance_to(to)
		elif how == "rect":
			var r := Rect2(from, Vector2.ZERO).expand(to)
			extent = [roundi(r.position.x), roundi(r.position.y), maxi(roundi(r.size.x), 1), maxi(roundi(r.size.y), 1)]
	_create(new_item(tool, doc.data, schema, [roundi(from.x), roundi(from.y)], extent))

func _create(value: Variant) -> void:
	if value == null:
		return
	var list: Array = tool_spec(tool)[2]
	if list == ["camera"] and doc.data.get("camera") is Dictionary:
		list = ["camera", "surface"]
	var path := insert_new(doc, list, value, "Add " + tool_spec(tool)[1].to_lower())
	tool = "select"
	item = path
	active_handle = {}
	select_requested.emit(path)
	redraw_requested.emit()

## Appends `value` to the list at `list` (a plain ground material becomes the
## base of a ground with regions). Returns the new item's path.
static func insert_new(scenario_doc: ScenarioDoc, list: Array, value: Variant, action: String) -> Array:
	if list == ["ground", "regions"] and not scenario_doc.data.get("ground") is Dictionary:
		var base: Variant = scenario_doc.data.get("ground", "soil")
		scenario_doc.set_at(["ground"], {"base": base if base is String else "soil", "regions": [value]}, action)
		return list + [0]
	var existing: Variant = scenario_doc.get_at(list)
	var index: int = existing.size() if existing is Array else 0
	scenario_doc.insert_at(list + [index], value, action)
	return list + [index]

## The new item of place tool `id` at `at` ([x, y] ints). `extent` is a drag's
## radius (circle tools), [x, y, w, h] (rect tools) or the points (polyline
## and polygon tools); null for a plain click.
static func new_item(id: String, data: Dictionary, scenario_schema: ScenarioSchema, at: Array, extent: Variant = null) -> Variant:
	var v := Vector2(at[0], at[1])
	var r: Variant = roundi(extent) if extent is float or extent is int else null
	var rect: Variant = extent if extent is Array and id not in ["wall_line", "water", "bridge", "region_polygon", "log"] else null
	var pts: Variant = extent if extent is Array and rect == null else null
	match id:
		"colony", "food", "scatter", "debris", "camera_key":
			var it: Dictionary = EditorDefaults.new_item(id, data, scenario_schema, v)
			if id == "food" and r != null:
				it["radius"] = maxi(r, 1)
			elif id == "scatter" and rect != null:
				it["scatter"]["rect"] = rect
			return it
		"wall_rect":
			return {"shape": "rect", "kind": "wall", "rect": rect if rect != null else [at[0] - 60, at[1] - 10, 120, 20]}
		"wall_circle":
			return {"shape": "circle", "kind": "wall", "center": at, "radius": maxi(r, 1) if r != null else 40}
		"wall_line":
			return {"shape": "polyline", "kind": "wall", "points": _pts(pts, at)}
		"water":
			return {"shape": "polygon", "kind": "water", "points": _pts(pts, at, true)}
		"bridge":
			return {"shape": "polyline", "kind": "bridge", "points": _pts(pts, at)}
		"region_circle":
			return {"material": "moss", "shape": "circle", "center": at, "radius": maxi(r, 1) if r != null else 150}
		"region_rect":
			return {"material": "moss", "shape": "rect", "rect": rect if rect != null else [at[0] - 150, at[1] - 150, 300, 300]}
		"region_polygon":
			return {"material": "moss", "shape": "polygon", "points": _pts(pts, at, true)}
		"rock":
			return {"type": "rock", "center": at, "radius": maxi(r, 1) if r != null else 40}
		"plant", "grass":
			return {"type": id, "center": at}
		"log":
			return {"type": "log", "points": _pts(pts, at)}
		"twig":
			return {"type": "twig", "pos": at, "length": 32}
		"pebble":
			return {"type": "pebble", "pos": at, "radius": 5}
		"rain":
			var it: Dictionary = EditorDefaults.new_item("event", data, scenario_schema, v)
			if r != null:
				it["area"]["radius"] = maxi(r, 1)
			return it
	return null

## The given points, or a default polyline (two points) / polygon (a triangle).
static func _pts(pts: Variant, at: Array, closed: bool = false) -> Array:
	if pts is Array and (pts as Array).size() >= (3 if closed else 2):
		return pts
	if closed:
		return [[at[0] - 60, at[1] + 40], [at[0] + 60, at[1] + 40], [at[0], at[1] - 60]]
	return [[at[0] - 60, at[1]], [at[0] + 60, at[1]]]

# --- helpers ---------------------------------------------------------------------

func _insert_point(at: Vector2, tol: float) -> bool:
	var shapes := GizmoGeometry.shapes(doc.data, item)
	for i: int in shapes.size():
		var s: Dictionary = shapes[i]
		if (s["kind"] == "polyline" or s["kind"] == "polygon") and GizmoGeometry.shape_contains(s, at, tol):
			var more := GizmoGeometry.with_point_inserted(doc.data, item, i, snap_point(at))
			if not more.is_empty():
				doc.set_at(item, more, "Insert point in " + _name(item))
				return true
	return false

static func _name(path: Array) -> String:
	return "/".join(path.map(func(k: Variant) -> String: return str(k)))
