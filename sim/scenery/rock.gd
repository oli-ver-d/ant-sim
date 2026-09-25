class_name RockProp
extends PropType
## A boulder: a lumpy ellipse that blocks ants.
##   {"type": "rock", "center": [x, y], "radius": 40, "flat": 0.8, "lumpy": 0.25,
##    "rotation": degrees (random if absent), "scale": 1, "blocks": true}
## "flat" is the short radius over the long one.

func build(prop: Prop, rng: RandomNumberGenerator) -> void:
	var p := prop.params
	prop.position = params_vec2(p["center"])
	prop.rotation = rotation_of(p, rng)
	prop.scale = float(p.get("scale", 1.0))
	var r := float(p.get("radius", 40.0)) * prop.scale
	var flat := clampf(float(p.get("flat", 0.8)), 0.2, 1.0)
	prop.outline = blob(prop.position, r, r * flat, prop.rotation, float(p.get("lumpy", 0.25)), rng)
	prop.blocks = bool(p.get("blocks", true))
	prop.footprint = {"shape": "polygon", "points": prop.outline}
