class_name LogProp
extends PropType
## A fallen branch or log lying along a polyline; blocks ants.
##   {"type": "log", "points": [[x, y], ...], "width": 30, "taper": 0.6, "blocks": true}
## "taper" is the width at the last point over the width at the first.

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
	# The footprint is the widest part all along (a little generous at the thin end).
	prop.footprint = {"shape": "polyline", "points": pts, "width": w}
