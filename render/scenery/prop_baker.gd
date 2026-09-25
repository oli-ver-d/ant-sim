class_name PropBaker
extends RefCounted
## Bakes a scenery prop's look into images once, when it is placed: its body
## (drawn over exactly its footprint, PropType.footprint_contains, so what is
## drawn is what blocks) and its shadow on the ground (a cast shadow away from
## the light, as long as the prop is tall, plus a soft contact shadow round it).
##
## The look itself is painted by a per-type painter, looked up in the Registry's
## renderers as "prop:<type id>" (e.g. RockLook, LogLook): an object with
## paint(canvas: PropBaker.Canvas, prop: Prop, ground: GroundMap) that fills
## canvas colours for the covered pixels. Painters see the shared light
## direction and the canvas's inside distance (depth), and seed their noise
## from prop.prop_seed, never the simulation's RNG.

## Pixels per world unit of baked images.
const RES := 2.0
## Pixels per world unit of shadow images (they are blurred anyway).
const SHADOW_RES := 1.0
## Direction the light comes FROM (world, y down), as in the shaders.
const LIGHT_DIR := Vector2(-0.55, -0.85)
## Height of the light above the ground, for 3D shading (z up).
const LIGHT_Z := 0.85
## Edge wobble of drawn outlines, world units (well within a cell).
const WOBBLE := 1.0

## The pixels a painter works on: one per 1 / RES world units over the body's rect.
class Canvas:
	var rect: Rect2
	var width: int
	var height: int
	## Coverage (alpha) of each pixel, 0..1.
	var cover: PackedFloat32Array = []
	## Distance from each covered pixel to the outline, world units (0 outside).
	var depth: PackedFloat32Array = []
	## Colours the painter writes (RGB, 0..1 each), row by row.
	var rgb: PackedFloat32Array = []
	## Painters may set a height per pixel (world units) for the cast shadow;
	## left empty, the shadow uses the prop's detail "height" everywhere.
	var heights: PackedFloat32Array = []

	func world_at(x: int, y: int) -> Vector2:
		return rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) / RES

	func set_rgb(i: int, c: Color) -> void:
		rgb[i * 3] = c.r
		rgb[i * 3 + 1] = c.g
		rgb[i * 3 + 2] = c.b

## Light as a unit 3D vector (x, y world, z up).
static func light3() -> Vector3:
	return Vector3(LIGHT_DIR.x, LIGHT_DIR.y, LIGHT_Z).normalized()

## Bakes `prop` with `painter`. Returns {"body": Image, "body_rect": Rect2,
## "shadow": Image, "shadow_rect": Rect2} (rects in world units), or {} for a
## prop without a footprint.
static func bake(prop: Prop, painter: Object, cell_size: float, ground: GroundMap = null) -> Dictionary:
	if prop.footprint.is_empty():
		return {}
	var canvas := rasterize(prop, cell_size)
	painter.call("paint", canvas, prop, ground)
	var body := _body_image(canvas)
	var shadow := _shadow(canvas, prop)
	return {"body": body, "body_rect": canvas.rect, "shadow": shadow["image"], "shadow_rect": shadow["rect"]}

## The canvas of a prop's footprint: coverage (with a slightly wobbly,
## anti-aliased edge) and inside distance.
static func rasterize(prop: Prop, cell_size: float) -> Canvas:
	var c := Canvas.new()
	var b := PropType.footprint_bounds(prop.footprint).grow(WOBBLE + 2.0)
	c.width = int(ceil(b.size.x * RES))
	c.height = int(ceil(b.size.y * RES))
	c.rect = Rect2(b.position, Vector2(c.width, c.height) / RES)
	var n := c.width * c.height
	c.cover.resize(n)
	c.depth.resize(n)
	c.rgb.resize(n * 3)
	var wobble := FastNoiseLite.new()
	wobble.seed = prop.prop_seed & 0x7FFFFFFF
	wobble.frequency = 1.0 / 7.0
	var fp := prop.footprint
	var inside := PackedByteArray()
	inside.resize(n)
	for y in c.height:
		for x in c.width:
			var p := c.world_at(x, y)
			if _inside(fp, p, wobble, cell_size):
				inside[y * c.width + x] = 1
	# Anti-alias: supersample pixels on the edge.
	for y in c.height:
		for x in c.width:
			var i := y * c.width + x
			var v := inside[i]
			var edge := (x > 0 and inside[i - 1] != v) or (x < c.width - 1 and inside[i + 1] != v) \
					or (y > 0 and inside[i - c.width] != v) or (y < c.height - 1 and inside[i + c.width] != v)
			if not edge:
				c.cover[i] = float(v)
				continue
			var p := c.world_at(x, y)
			var hits := 0
			for o: Vector2 in [Vector2(-0.25, -0.25), Vector2(0.25, -0.25), Vector2(-0.25, 0.25), Vector2(0.25, 0.25)]:
				if _inside(fp, p + o / RES, wobble, cell_size):
					hits += 1
			c.cover[i] = hits * 0.25
	c.depth = _chamfer(inside, c.width, c.height)
	return c

static func _inside(fp: Dictionary, p: Vector2, wobble: FastNoiseLite, cell_size: float) -> bool:
	var off := Vector2(wobble.get_noise_2d(p.x, p.y), wobble.get_noise_2d(p.x + 71.3, p.y - 33.1)) * WOBBLE
	return PropType.footprint_contains(fp, p + off, cell_size)

## Distance (world units) from each inside pixel to the nearest outside one
## (two-pass chamfer, 1 / sqrt 2 weights).
static func _chamfer(inside: PackedByteArray, w: int, h: int) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(w * h)
	const BIG := 1.0e9
	const DIAG := 1.41421
	for i in w * h:
		d[i] = BIG if inside[i] != 0 else 0.0
	for y in h:
		for x in w:
			var i := y * w + x
			if d[i] == 0.0:
				continue
			var m := d[i]
			if x > 0: m = minf(m, d[i - 1] + 1.0)
			if y > 0:
				m = minf(m, d[i - w] + 1.0)
				if x > 0: m = minf(m, d[i - w - 1] + DIAG)
				if x < w - 1: m = minf(m, d[i - w + 1] + DIAG)
			# The canvas border counts as outside.
			if x == 0 or y == 0: m = minf(m, 1.0)
			d[i] = m
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if d[i] == 0.0:
				continue
			var m := d[i]
			if x < w - 1: m = minf(m, d[i + 1] + 1.0)
			if y < h - 1:
				m = minf(m, d[i + w] + 1.0)
				if x < w - 1: m = minf(m, d[i + w + 1] + DIAG)
				if x > 0: m = minf(m, d[i + w - 1] + DIAG)
			if x == w - 1 or y == h - 1: m = minf(m, 1.0)
			d[i] = m
	for i in w * h:
		# Pixel centres: an edge pixel is about half a pixel in.
		d[i] = maxf(d[i] - 0.5, 0.0) / RES if d[i] > 0.0 else 0.0
	return d

static func _body_image(c: Canvas) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(c.width * c.height * 4)
	for i in c.width * c.height:
		var a := c.cover[i]
		if a <= 0.0:
			continue
		bytes[i * 4] = int(clampf(c.rgb[i * 3], 0.0, 1.0) * 255.0)
		bytes[i * 4 + 1] = int(clampf(c.rgb[i * 3 + 1], 0.0, 1.0) * 255.0)
		bytes[i * 4 + 2] = int(clampf(c.rgb[i * 3 + 2], 0.0, 1.0) * 255.0)
		bytes[i * 4 + 3] = int(a * 255.0)
	var img := Image.create_from_data(c.width, c.height, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	return img

## The prop's shadow on the ground: each part of the body casts a shadow away
## from the light as long as it is high (canvas heights, else the prop's
## "height"), softened, plus a darker contact shadow hugging the outline.
static func _shadow(c: Canvas, prop: Prop) -> Dictionary:
	var top := float(prop.detail.get("height", 10.0))
	var cast := -LIGHT_DIR.normalized() * top * 0.75
	var margin := absf(cast.x) + absf(cast.y) + 10.0
	var rect := c.rect.grow(margin)
	var sw := int(ceil(rect.size.x * SHADOW_RES))
	var sh := int(ceil(rect.size.y * SHADOW_RES))
	rect.size = Vector2(sw, sh) / SHADOW_RES
	# Height of the body on the shadow grid (max over the canvas pixels in each).
	var hs := PackedFloat32Array()
	hs.resize(sw * sh)
	var per_height := not c.heights.is_empty()
	for y in c.height:
		for x in c.width:
			var i := y * c.width + x
			if c.cover[i] < 0.5:
				continue
			var p := (c.world_at(x, y) - rect.position) * SHADOW_RES
			var j := int(p.y) * sw + int(p.x)
			hs[j] = maxf(hs[j], c.heights[i] if per_height else top)
	const STEPS := 10
	var cast_px := cast * SHADOW_RES
	var cast_a := PackedByteArray()
	cast_a.resize(sw * sh)
	var contact := PackedByteArray()
	contact.resize(sw * sh)
	for y in sh:
		for x in sw:
			var j := y * sw + x
			if hs[j] > 0.0:
				contact[j] = 255
			# In shadow if some body point toward the light stands high enough.
			for k in range(1, STEPS + 1):
				var f := float(k) / STEPS
				var qx := int(x - cast_px.x * f)
				var qy := int(y - cast_px.y * f)
				if qx < 0 or qy < 0 or qx >= sw or qy >= sh:
					continue
				if hs[qy * sw + qx] >= top * f:
					cast_a[j] = 255
					break
	var soft := _blur(Image.create_from_data(sw, sh, false, Image.FORMAT_L8, cast_a), 3)
	var ring := _blur(Image.create_from_data(sw, sh, false, Image.FORMAT_L8, contact), 5)
	var sb := soft.get_data()
	var rb := ring.get_data()
	var out := PackedByteArray()
	out.resize(sw * sh * 4)
	for j in sw * sh:
		var a := maxf(sb[j] / 255.0 * 0.55, minf(rb[j] / 255.0 * 1.5, 1.0) * 0.5)
		out[j * 4] = 18
		out[j * 4 + 1] = 12
		out[j * 4 + 2] = 6
		out[j * 4 + 3] = int(a * 255.0)
	var img := Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, out)
	return {"image": img, "rect": rect}

## A cheap blur: shrink by `factor`, grow back smoothly.
static func _blur(img: Image, factor: int) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	img.resize(maxi(w / factor, 1), maxi(h / factor, 1), Image.INTERPOLATE_BILINEAR)
	img.resize(w, h, Image.INTERPOLATE_CUBIC)
	return img

# --- Helpers for painters --------------------------------------------------------------

## A FastNoiseLite seeded from a prop (salt picks another pattern).
static func noise(prop: Prop, salt: int, frequency: float, type: FastNoiseLite.NoiseType = FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
		octaves: int = 1) -> FastNoiseLite:
	var nz := FastNoiseLite.new()
	nz.seed = (prop.prop_seed + salt * 7919) & 0x7FFFFFFF
	nz.noise_type = type
	nz.frequency = frequency
	if octaves > 1:
		nz.fractal_type = FastNoiseLite.FRACTAL_FBM
		nz.fractal_octaves = octaves
	else:
		nz.fractal_type = FastNoiseLite.FRACTAL_NONE
	return nz

## A cellular FastNoiseLite (Voronoi) returning `ret`.
static func cells(prop: Prop, salt: int, frequency: float, ret: FastNoiseLite.CellularReturnType) -> FastNoiseLite:
	var nz := noise(prop, salt, frequency, FastNoiseLite.TYPE_CELLULAR)
	nz.cellular_return_type = ret
	nz.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	return nz

## Hash of a pixel to [0, 1) (grain specks; no sine).
static func hash01(x: int, y: int, salt: int) -> float:
	var h := (x * 374761393 + y * 668265263 + salt * 2147483647) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return float((h ^ (h >> 16)) & 0xFFFF) / 65536.0
