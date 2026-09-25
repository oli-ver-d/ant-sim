class_name PlantLook
extends RefCounted
## Paints a plant's stem crown (PlantProp) for PropBaker: the few units where
## its blades or stalks gather and go into the ground, over exactly the
## blocking stem, under the ants. A low dome of packed blade bases, pale where
## they are sheathed, darker between them and at the soil line. The blades
## themselves are the canopy (CanopyRenderer). Registered as "prop:plant" and
## "prop:grass" (grass has no stem unless its "stem" is set).

const SHEATH := Color(0.62, 0.6, 0.36)
const SOIL_LINE := Color(0.2, 0.15, 0.08)

func paint(c: PropBaker.Canvas, prop: Prop, _ground: GroundMap) -> void:
	var blades: Array = prop.detail.get("blades", [])
	var green := Color(0.28, 0.44, 0.16)
	if not blades.is_empty():
		green = blades[blades.size() - 1]["tint"]
	var fp := prop.footprint
	var centre: Vector2 = fp.get("center", prop.position)
	var r := maxf(float(fp.get("radius", 4.0)), 1.0)
	var top := float(prop.detail.get("height", 4.0))
	var L := PropBaker.light3()
	var ribs := maxi(blades.size(), 5)
	var twist := PropBaker.noise(prop, 11, 1.0 / 3.0)
	var heights := PackedFloat32Array()
	heights.resize(c.width * c.height)
	for y in c.height:
		for x in c.width:
			var i := y * c.width + x
			if c.cover[i] <= 0.0:
				continue
			var p := c.world_at(x, y) - centre
			var t := clampf(p.length() / r, 0.0, 1.0)
			# Dome: the crown rises toward its middle.
			var h := sqrt(maxf(1.0 - t * t, 0.0))
			heights[i] = top * (0.3 + 0.7 * h)
			var slope := p.normalized() * t / maxf(h, 0.2)
			var nrm := Vector3(slope.x, slope.y, 1.0).normalized()
			var shade := 0.45 + 0.7 * maxf(nrm.dot(L), 0.0)
			# Blade bases round the centre: ridges, pale sheaths, dark creases.
			var a := p.angle() * ribs / TAU + twist.get_noise_2d(p.x, p.y) * 0.4 + t * 0.6
			var rib := absf(fposmod(a, 1.0) - 0.5) * 2.0
			var col := green.lerp(SHEATH, 0.45 * (1.0 - t))
			col = col.darkened(0.35 * smoothstep(0.6, 1.0, rib))
			col = col.lerp(SOIL_LINE, 0.55 * smoothstep(0.7, 1.0, t))
			c.set_rgb(i, col * shade)
	c.heights = heights
