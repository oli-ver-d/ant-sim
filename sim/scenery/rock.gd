class_name RockProp
extends PropType
## A boulder: a lumpy ellipse that blocks ants.
##   {"type": "rock", "center": [x, y], "radius": 40, "flat": 0.8, "lumpy": 0.25,
##    "rotation": degrees (random if absent), "scale": 1, "blocks": true,
##    "height": 1, "lichen": 0..1 (random if absent), "moss": 0..1 (from the ground if absent),
##    "stone": "granite" | "sandstone" | "basalt" (random if absent)}
## "flat" is the short radius over the long one, "height" scales how tall it
## stands (its shadow). A scenario wall with "look": "rock" becomes a rock prop
## with {"wall": <the obstacle>} whose footprint is the wall's own cells.

const STONES: Array[String] = ["granite", "sandstone", "basalt"]

func build(prop: Prop, rng: RandomNumberGenerator) -> void:
	var p := prop.params
	if p.has("wall"):
		_build_wall(prop, rng)
		return
	prop.position = params_vec2(p["center"])
	prop.rotation = rotation_of(p, rng)
	prop.scale = float(p.get("scale", 1.0))
	var r := float(p.get("radius", 40.0)) * prop.scale
	var flat := clampf(float(p.get("flat", 0.8)), 0.2, 1.0)
	prop.outline = blob(prop.position, r, r * flat, prop.rotation, float(p.get("lumpy", 0.25)), rng)
	prop.blocks = bool(p.get("blocks", true))
	prop.footprint = {"shape": "polygon", "points": prop.outline}
	_detail(prop, r * flat, rng)

func _build_wall(prop: Prop, rng: RandomNumberGenerator) -> void:
	var fp := obstacle_footprint(prop.params["wall"])
	prop.footprint = fp
	prop.blocks = true
	var b := footprint_bounds(fp)
	prop.position = b.get_center()
	# Half the wall's thickness: a long thin wall is a low ridge.
	var half := minf(b.size.x, b.size.y) * 0.5
	match fp["shape"]:
		"polygon":
			prop.outline = fp["points"]
		"rect":
			var r: Rect2 = fp["rect"]
			prop.outline = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		"circle":
			prop.outline = blob(fp["center"], fp["radius"], fp["radius"], 0.0, 0.0, rng)
		"polyline":
			var widths: PackedFloat32Array = []
			widths.resize(fp["points"].size())
			widths.fill(float(fp["width"]))
			prop.outline = strip_outline(fp["points"], widths)
			half = float(fp["width"]) * 0.5
	_detail(prop, minf(half, 40.0), rng)

## The look's parameters: `half` is roughly the rock's half-width (world units).
func _detail(prop: Prop, half: float, rng: RandomNumberGenerator) -> void:
	var p := prop.params
	var stone_pick := rng.randi() % STONES.size()
	var lichen := rng.randf_range(0.1, 0.8)
	prop.detail = {
		"half": half,
		"height": half * 0.7 * float(p.get("height", 1.0)),
		"stone": str(p.get("stone", STONES[stone_pick])),
		"lichen": float(p.get("lichen", lichen)),
	}
	if p.has("moss"):
		prop.detail["moss"] = float(p["moss"])
