class_name RockLook
extends RefCounted
## Paints a rock (RockProp) for PropBaker: a dome rising from the outline with
## a flattish top, broken into facets, lit from PropBaker.LIGHT_DIR; mineral
## grain and specks per stone, a few hairline cracks, lichen rosettes on the
## upper faces, and moss on the shaded side when the rock stands on moss
## (GroundMap) or its "moss" says so. Registered as the renderer "prop:rock".

## Base colour, grain strength, speck odds (dark, light) per stone.
const STONES := {
	"granite": {"color": Color(0.45, 0.43, 0.4), "grain": 0.09, "dark": 0.07, "light": 0.05, "warm": Color(0.53, 0.45, 0.4)},
	"sandstone": {"color": Color(0.6, 0.49, 0.35), "grain": 0.06, "dark": 0.015, "light": 0.02, "warm": Color(0.66, 0.46, 0.31)},
	"basalt": {"color": Color(0.3, 0.29, 0.28), "grain": 0.05, "dark": 0.03, "light": 0.01, "warm": Color(0.38, 0.34, 0.31)},
}
const LICHENS: Array[Color] = [Color(0.74, 0.77, 0.62), Color(0.68, 0.72, 0.56), Color(0.82, 0.66, 0.3)]
const MOSS := Color(0.27, 0.4, 0.13)
const MOSS_LIGHT := Color(0.45, 0.56, 0.2)

func paint(c: PropBaker.Canvas, prop: Prop, ground: GroundMap) -> void:
	var d := prop.detail
	var half := maxf(float(d.get("half", 20.0)), 3.0)
	var top := float(d.get("height", half * 0.7))
	var stone: Dictionary = STONES.get(str(d.get("stone", "granite")), STONES["granite"])
	var lichen := float(d.get("lichen", 0.3))
	var moss := float(d["moss"]) if d.has("moss") else _moss_under(prop, ground)
	var sandstone := str(d.get("stone", "")) == "sandstone"
	var base: Color = stone["color"]
	var warm: Color = stone["warm"]
	var L := PropBaker.light3()
	var L2 := PropBaker.LIGHT_DIR.normalized()

	var shape_nz := PropBaker.noise(prop, 1, 1.0 / (half * 0.55), FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	var fine := PropBaker.noise(prop, 2, 1.0 / 2.5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)
	var tone := PropBaker.noise(prop, 3, 1.0 / (half * 0.8), FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)
	var facets := PropBaker.cells(prop, 4, 1.0 / maxf(half * 0.45, 5.0), FastNoiseLite.RETURN_CELL_VALUE)
	var cracks := PropBaker.cells(prop, 5, 1.0 / maxf(half * 0.7, 8.0), FastNoiseLite.RETURN_DISTANCE2_SUB)
	var crack_mask := PropBaker.noise(prop, 6, 1.0 / (half * 0.5))
	var spots := PropBaker.cells(prop, 7, 1.0 / 4.5, FastNoiseLite.RETURN_DISTANCE)
	var spot_kind := PropBaker.cells(prop, 7, 1.0 / 4.5, FastNoiseLite.RETURN_CELL_VALUE)
	var patches := PropBaker.noise(prop, 8, 1.0 / (half * 0.6), FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)
	var layers := PropBaker.noise(prop, 9, 1.0 / 3.0)
	var layer_dir := Vector2.from_angle(prop.rotation + 0.4)

	# Height: a quarter-round rise over the first `rise` units in, then a
	# gently bumpy top.
	var w := c.width
	var n := w * c.height
	var rise := half * 0.75
	var h := PackedFloat32Array()
	h.resize(n)
	for y in c.height:
		for x in w:
			var i := y * w + x
			if c.cover[i] <= 0.0:
				continue
			var p := c.world_at(x, y)
			var t := clampf(c.depth[i] / rise, 0.0, 1.0)
			var dome := sqrt(1.0 - (1.0 - t) * (1.0 - t))
			h[i] = top * dome * (1.0 + 0.32 * shape_nz.get_noise_2d(p.x, p.y) * t) + 0.35 * fine.get_noise_2d(p.x, p.y)
	c.heights = h

	var step := 2.0 / PropBaker.RES
	for y in c.height:
		for x in w:
			var i := y * w + x
			if c.cover[i] <= 0.0:
				continue
			var p := c.world_at(x, y)
			var hl := h[i - 1] if x > 0 else 0.0
			var hr := h[i + 1] if x < w - 1 else 0.0
			var hu := h[i - w] if y > 0 else 0.0
			var hd := h[i + w] if y < c.height - 1 else 0.0
			var slope := Vector2(hr - hl, hd - hu) / step
			# Facets: each Voronoi cell of the rock tilts a little its own way.
			var tilt := Vector2.from_angle(facets.get_noise_2d(p.x, p.y) * PI) * 0.22 * clampf(c.depth[i] / rise, 0.2, 1.0)
			var nrm := Vector3(-slope.x + tilt.x, -slope.y + tilt.y, 1.0).normalized()
			var lit := maxf(nrm.dot(L), 0.0)
			var shade := 0.34 + 0.86 * lit
			# Mineral colour: grain, broad tone, specks.
			var col := base.lerp(warm, clampf(0.5 + 0.6 * tone.get_noise_2d(p.x, p.y), 0.0, 1.0) * 0.5)
			col = col * (1.0 + float(stone["grain"]) * fine.get_noise_2d(p.x * 1.7, p.y * 1.7))
			if sandstone:
				# Bedding: faint bands across the stone.
				var band := layers.get_noise_2d(p.dot(layer_dir) * 0.4, p.dot(layer_dir.orthogonal()) * 0.05)
				col = col * (1.0 + 0.08 * band)
			var hx := PropBaker.hash01(x, y, prop.id)
			if hx < float(stone["dark"]):
				col = col.darkened(0.35)
			elif hx > 1.0 - float(stone["light"]):
				col = col.lightened(0.25)
			# Hairline cracks, in places only.
			var crack := cracks.get_noise_2d(p.x, p.y)
			if crack < -0.975 and crack_mask.get_noise_2d(p.x, p.y) > 0.3 and c.depth[i] > 3.0:
				shade *= 0.68
			# Lichen rosettes on the upper faces.
			var up := clampf(h[i] / maxf(top, 0.1), 0.0, 1.0)
			if lichen > 0.0 and patches.get_noise_2d(p.x, p.y) > 1.0 - 1.4 * lichen - 0.3 * up:
				var r := spots.get_noise_2d(p.x, p.y)
				if r < -0.72:
					var k := int((spot_kind.get_noise_2d(p.x, p.y) * 0.5 + 0.5) * LICHENS.size()) % LICHENS.size()
					col = col.lerp(LICHENS[k], 0.75 * clampf((-0.72 - r) * 8.0, 0.0, 1.0))
			# Moss on the shaded side and round the foot.
			if moss > 0.0:
				var away := -Vector2(nrm.x, nrm.y).dot(L2) * 2.0
				var foot := 1.0 - clampf(c.depth[i] / (rise * 0.6), 0.0, 1.0)
				var m := moss * (0.8 * clampf(away + 0.2, 0.0, 1.0) + 0.6 * foot) + 0.35 * patches.get_noise_2d(p.x + 50.0, p.y)
				if m > 0.45:
					var cushion := 0.5 + 0.5 * fine.get_noise_2d(p.x * 2.2 + 9.0, p.y * 2.2)
					col = col.lerp(MOSS.lerp(MOSS_LIGHT, cushion), clampf((m - 0.45) * 5.0, 0.0, 0.95))
			# Ground contact: the lowest rim is dark.
			shade *= lerpf(0.6, 1.0, clampf(c.depth[i] / 2.5, 0.0, 1.0))
			c.set_rgb(i, col * shade)

## Moss weight of the ground under the rock (0 without a material map).
static func _moss_under(prop: Prop, ground: GroundMap) -> float:
	if ground == null:
		return 0.0
	var m := ground.weight_at("moss", prop.position)
	for q in prop.outline:
		m = maxf(m, ground.weight_at("moss", q))
	return m
