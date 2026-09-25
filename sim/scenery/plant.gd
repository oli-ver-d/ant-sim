class_name PlantProp
extends PropType
## A plant or grass clump: a stem on the ground (blocking if "stem" > 0) and a
## canopy of blades over the ants, which never blocks.
##   {"type": "plant", "kind": "rosette", "center": [x, y], "radius": 60, "stem": 6,
##    "blades": 8, "rotation": degrees, "scale": 1}
##   {"type": "grass", "center": [x, y], "radius": 40}   (stem 0: canopy only)
## "radius" is the canopy's reach. Kinds (rosette, clover, fern, seedling) only
## differ in their look (drawn from M15d on).

func build(prop: Prop, rng: RandomNumberGenerator) -> void:
	var p := prop.params
	prop.position = params_vec2(p["center"])
	prop.rotation = rotation_of(p, rng)
	prop.scale = float(p.get("scale", 1.0))
	var grass := prop.type_id == "grass"
	var reach := float(p.get("radius", 40.0 if grass else 60.0)) * prop.scale
	var stem := float(p.get("stem", 0.0 if grass else 6.0)) * prop.scale
	var blades := int(p.get("blades", 14 if grass else 8))
	# Canopy placeholder: a star with a point per blade, of varied lengths.
	var star: PackedVector2Array = []
	for i in blades:
		var a := prop.rotation + TAU * (i + rng.randf_range(-0.2, 0.2)) / blades
		var a_mid := prop.rotation + TAU * (i + 0.5) / blades
		star.append(prop.position + Vector2.from_angle(a) * reach * rng.randf_range(0.7, 1.0))
		star.append(prop.position + Vector2.from_angle(a_mid) * reach * 0.3)
	prop.canopy = star
	prop.blocks = stem > 0.0 and bool(p.get("blocks", true))
	if stem > 0.0:
		prop.outline = blob(prop.position, stem, stem, 0.0, 0.0, rng, 10)
		prop.footprint = {"shape": "circle", "center": prop.position, "radius": stem}
