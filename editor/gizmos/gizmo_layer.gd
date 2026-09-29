class_name GizmoLayer
extends Node2D
## Draws the canvas editing state over the editor's preview (world space, in
## the preview's SubViewport): faint outlines of what the renderer doesn't
## show (ground regions, event areas, scatter areas and clear shapes, camera
## keys), the selected item's shapes and handles (the dragged version while a
## drag is on), a selected scatter's keep-clear zones (hard: red, reserve:
## orange) from the built sim, a selected camera key's output frame, and the
## item a place tool is putting down.

const FAINT := Color(1, 1, 1, 0.28)
const SHAPE := Color(1.0, 0.85, 0.2, 1.0)
const SOFT := Color(1.0, 0.85, 0.2, 0.45)
const HANDLE := Color(1, 1, 1, 1)
const HANDLE_EDGE := Color(0.1, 0.1, 0.1, 1)
const ACTIVE := Color(1.0, 0.55, 0.1, 1)
const HARD_ZONE := Color(1.0, 0.25, 0.25, 0.7)
const RESERVE_ZONE := Color(1.0, 0.6, 0.15, 0.6)
const PLACING := Color(0.4, 1.0, 0.5, 0.9)
const CAMERA := Color(0.35, 0.8, 1.0, 0.8)
const HANDLE_PX := 5.0

var preview: EditorPreview
var canvas: CanvasEditor

func _draw() -> void:
	if preview == null or canvas == null or canvas.doc == null:
		return
	var px := 1.0 / preview.camera.zoom.x
	var data := canvas.doc.data
	for path: Array in GizmoGeometry.item_paths(data):
		if path == canvas.item:
			continue
		for s: Dictionary in GizmoGeometry.shapes(data, path):
			if s["role"] != "body" or path[0] in ["ground", "events", "camera"]:
				_shape(s, FAINT, px, false)
	if canvas.item != null and canvas.doc.has_at(canvas.item):
		_selected(data, canvas.item, px)
	_placing(px)

func _selected(data: Dictionary, path: Array, px: float) -> void:
	var shown := data
	if canvas.drag_item != null:
		shown = with_value(data, path, canvas.drag_item)
	else:
		_scatter_zones(data, path, px)
	var shapes := GizmoGeometry.shapes(shown, path)
	for s: Dictionary in shapes:
		_shape(s, SHAPE, px, true)
		if path[0] == "camera" and s["kind"] == "point":
			var key: Variant = canvas.doc.get_at(path)
			var zoom: Variant = key.get("zoom") if key is Dictionary else null
			var z := maxf(float(zoom), 0.01) if zoom is float or zoom is int else 1.0
			var size := preview.frame.size_f() / z
			draw_rect(Rect2(s["center"] - size / 2.0, size), CAMERA, false, 1.5 * px)
	for i: int in shapes.size():
		for h: Dictionary in GizmoGeometry.handles(shapes[i]):
			var active: bool = canvas.active_handle.get("shape", -1) == i and canvas.active_handle.get("role") == h["role"] \
					and canvas.active_handle.get("index") == h["index"]
			var r := Rect2(h["pos"] - Vector2.ONE * HANDLE_PX * px, Vector2.ONE * HANDLE_PX * 2.0 * px)
			draw_rect(r, ACTIVE if active else HANDLE)
			draw_rect(r, HANDLE_EDGE, false, px)

## A copy of `data` with `value` at `path`, copying only the containers on the way.
static func with_value(data: Dictionary, path: Array, value: Variant) -> Dictionary:
	var root := data.duplicate()
	var parent: Variant = root
	for i: int in path.size() - 1:
		var child: Variant = parent[path[i]]
		child = child.duplicate() if child is Dictionary or child is Array else child
		parent[path[i]] = child
		parent = child
	parent[path[-1]] = value
	return root

func _scatter_zones(data: Dictionary, path: Array, px: float) -> void:
	if path[0] != "scenery" or preview.sim == null:
		return
	var it: Variant = canvas.doc.get_at(path)
	if not it is Dictionary or not it.get("scatter") is Dictionary:
		return
	var s: Dictionary = it["scatter"]
	var margin: Variant = s.get("keep_clear", Scatter.KEEP_CLEAR)
	for z: Scatter.Zone in Scatter.keep_clear_zones(preview.sim, s, float(margin) if margin is float or margin is int else Scatter.KEEP_CLEAR):
		var c := HARD_ZONE if z.hard else RESERVE_ZONE
		match z.shape:
			"circle":
				draw_arc(z.center, z.radius, 0.0, TAU, 64, c, 1.5 * px)
			"rect":
				draw_rect(z.rect, c, false, 1.5 * px)
			_:
				if z.points.size() >= 2:
					draw_polyline(z.points, Color(c, c.a * 0.4), maxf(z.width, px))

func _shape(s: Dictionary, color: Color, px: float, selected: bool) -> void:
	var w := (2.0 if selected else 1.0) * px
	match s["kind"]:
		"circle":
			draw_arc(s["center"], s["radius"], 0.0, TAU, 64, color, w)
			if s.has("soft") and selected:
				draw_arc(s["center"], s["radius"] + float(s["soft"]), 0.0, TAU, 64, SOFT, px)
		"rect":
			draw_rect(s["rect"], color, false, w)
			if s.has("soft") and selected:
				draw_rect((s["rect"] as Rect2).grow(float(s["soft"])), SOFT, false, px)
		"polyline":
			var pts: PackedVector2Array = s["points"]
			if pts.size() >= 2:
				if selected:
					draw_polyline(pts, Color(color, 0.25), maxf(float(s.get("width", 1.0)), px))
				draw_polyline(pts, color, w)
		"polygon":
			var pts: PackedVector2Array = s["points"]
			if pts.size() >= 2:
				var closed := pts.duplicate()
				closed.append(pts[0])
				draw_polyline(closed, color, w)
		"point":
			var c: Vector2 = s["center"]
			var d := 8.0 * px
			draw_line(c - Vector2(d, 0), c + Vector2(d, 0), color, w)
			draw_line(c - Vector2(0, d), c + Vector2(0, d), color, w)

func _placing(px: float) -> void:
	var how: String = CanvasEditor.tool_spec(canvas.tool)[3]
	if not canvas.poly_points.is_empty():
		var pts := canvas.poly_points.duplicate()
		pts.append(canvas.snap_point(canvas.hover))
		if how == "polygon" and pts.size() >= 3:
			pts.append(pts[0])
		draw_polyline(pts, PLACING, 2.0 * px)
		for p: Vector2 in canvas.poly_points:
			draw_circle(p, 3.0 * px, PLACING)
	elif not canvas.span.is_empty():
		var a: Vector2 = canvas.span[0]
		var b: Vector2 = canvas.span[1]
		if how == "circle":
			draw_arc(a, maxf(a.distance_to(b), px), 0.0, TAU, 64, PLACING, 2.0 * px)
		elif how == "rect":
			draw_rect(Rect2(a, Vector2.ZERO).expand(b), PLACING, false, 2.0 * px)
		else:
			draw_circle(a, 4.0 * px, PLACING)
