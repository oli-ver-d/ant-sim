class_name LogProp
extends PropType
## A fallen branch or log lying along a polyline; blocks ants.
##   {"type": "log", "points": [[x, y], ...], "width": 30, "taper": 0.6, "blocks": true,
##    "stubs": 0.. (side branch stubs; random 0-2 if absent), "peel": 0..1 (bare patches)}
## "taper" is the width at the last point over the width at the first. The first
## point is the sawn end, the last the broken one.

func build(prop: Prop, rng: RandomNumberGenerator) -> void:
	var p := prop.params
	var pts := params_points(p["points"])
	prop.position = pts[0]
	prop.rotation = (pts[pts.size() - 1] - pts[0]).angle() if pts.size() > 1 else rotation_of(p, rng)
	var w := float(p.get("width", 30.0))
	var taper := float(p.get("taper", 0.6))
	var widths: PackedFloat32Array = []
	for i in pts.size():
		widths.append(w * lerpf(1.0, taper, float(i) / maxi(pts.size() - 1, 1)))
	prop.outline = strip_outline(pts, widths)
	prop.blocks = bool(p.get("blocks", true))
	var axes: Array[Dictionary] = [{"points": pts, "widths": widths}]
	# Side branch stubs, sticking out of the log a little way.
	var stub_count := rng.randi_range(0, 2)
	if p.has("stubs"):
		stub_count = int(p["stubs"])
	if pts.size() > 1:
		var length := 0.0
		for i in pts.size() - 1:
			length += pts[i].distance_to(pts[i + 1])
		for k in stub_count:
			var at := _along(pts, widths, length * rng.randf_range(0.25, 0.8))
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var dir := (at["dir"] as Vector2).rotated(side * deg_to_rad(rng.randf_range(35.0, 70.0)))
			var sw := float(at["width"]) * rng.randf_range(0.3, 0.45)
			var reach := float(at["width"]) * 0.5 + w * rng.randf_range(0.6, 1.2)
			var start: Vector2 = at["point"]
			axes.append({"points": PackedVector2Array([start, start + dir * reach]),
					"widths": PackedFloat32Array([sw, sw * 0.75])})
	var parts: Array[Dictionary] = []
	for axis in axes:
		parts.append_array(_axis_parts(axis["points"], axis["widths"]))
	prop.footprint = {"shape": "multi", "parts": parts}
	prop.detail = {
		"axes": axes,
		"height": w * 0.8,
		"peel": float(p.get("peel", rng.randf_range(0.1, 0.5))),
		"tint": rng.randf(),
	}

## Point, direction and width at `dist` along the polyline.
static func _along(pts: PackedVector2Array, widths: PackedFloat32Array, dist: float) -> Dictionary:
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if dist <= seg or i == pts.size() - 2:
			var t := clampf(dist / maxf(seg, 0.001), 0.0, 1.0)
			return {"point": pts[i].lerp(pts[i + 1], t), "dir": (pts[i + 1] - pts[i]).normalized(),
					"width": lerpf(widths[i], widths[i + 1], t)}
		dist -= seg
	return {"point": pts[0], "dir": Vector2.RIGHT, "width": widths[0]}

## Footprint of a tapered strip: a quad per segment (flat ends) and a disc at
## each bend, so the drawn log and its blocked cells have the same shape.
static func _axis_parts(pts: PackedVector2Array, widths: PackedFloat32Array) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	for i in pts.size() - 1:
		var n := (pts[i + 1] - pts[i]).normalized().orthogonal()
		var a := n * widths[i] * 0.5
		var b := n * widths[i + 1] * 0.5
		parts.append({"shape": "polygon", "points": PackedVector2Array([
				pts[i] + a, pts[i + 1] + b, pts[i + 1] - b, pts[i] - a])})
		if i > 0:
			parts.append({"shape": "circle", "center": pts[i], "radius": widths[i] * 0.5})
	return parts
