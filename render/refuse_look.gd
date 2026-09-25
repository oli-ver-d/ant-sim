class_name RefuseLook
extends RefCounted
## How a kind of refuse looks on a midden (MiddenRenderer): VARIANTS small
## sprites painted once into an atlas, lit from PropBaker.LIGHT_DIR. A look is
## registered as the renderer "refuse:<kind id>" (Registry); subclasses
## override paint() and use the helpers here (lit blobs, strokes, specks).
## Kinds without a registered look are drawn as "refuse:remnant".
##
## A sprite's cell is PX pixels square; the body is painted within BODY * PX
## of the middle, leaving room for the shadow refuse.gdshader casts from it.
## The renderer sizes a cell so that the body's radius is the deposit's
## radius. Looks that are `tinted` are painted in greys and multiplied by a
## colour per deposit (a dead worker's caste colour).

const PX := 32
const VARIANTS := 16
## Radius of the painted body in cells.
const BODY := 0.36

## True if the renderer multiplies the sprite by a colour per deposit.
var tinted: bool = false

## Paints variant `v` into `img` in the cell whose top-left pixel is `at`.
## The rng is seeded per kind and variant.
func paint(_img: Image, _at: Vector2i, _v: int, _rng: RandomNumberGenerator) -> void:
	pass

## The atlas: VARIANTS cells in a row, with mipmaps.
func bake(kind_id: String) -> Image:
	var img := Image.create_empty(PX * VARIANTS, PX, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	for v in VARIANTS:
		rng.seed = hash(kind_id) + v * 7919
		paint(img, Vector2i(v * PX, 0), v, rng)
		_bleed(img, Vector2i(v * PX, 0))
	img.generate_mipmaps()
	return img

## Gives the clear pixels of a cell the body's mean colour, so smaller mip
## levels don't darken toward the clear pixels' black.
static func _bleed(img: Image, at: Vector2i) -> void:
	var sum := Color(0, 0, 0, 0)
	for y in PX:
		for x in PX:
			var c := img.get_pixel(at.x + x, at.y + y)
			sum += Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a)
	if sum.a <= 0.0:
		return
	var mean := Color(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a, 0.0)
	for y in PX:
		for x in PX:
			var c := img.get_pixel(at.x + x, at.y + y)
			if c.a < 0.5:
				img.set_pixel(at.x + x, at.y + y, Color(mean.lerp(c, c.a * 2.0), c.a))

# --- Painting helpers (coordinates in cell pixels, the middle at PX / 2) ---------------

## An ellipse of radii `radii` turned by `angle`, domed to `relief` (0 flat,
## 1 round) and lit: composited over what is there.
static func blob(img: Image, at: Vector2i, centre: Vector2, radii: Vector2, angle: float, color: Color,
		relief: float = 0.8) -> void:
	var L := PropBaker.light3()
	var reach := maxf(radii.x, radii.y) + 1.0
	var ax := Vector2.from_angle(angle)
	var ay := ax.orthogonal()
	for y in range(maxi(0, int(centre.y - reach)), mini(PX, int(centre.y + reach) + 1)):
		for x in range(maxi(0, int(centre.x - reach)), mini(PX, int(centre.x + reach) + 1)):
			var p := Vector2(x + 0.5, y + 0.5) - centre
			var l := Vector2(p.dot(ax) / radii.x, p.dot(ay) / radii.y)
			var d := l.length()
			if d >= 1.0 + 1.0 / minf(radii.x, radii.y):
				continue
			var cover := clampf((1.0 - d) * minf(radii.x, radii.y) + 0.5, 0.0, 1.0)
			var z := sqrt(maxf(1.0 - d * d, 0.0)) * relief + (1.0 - relief)
			var nl := ax * l.x * relief + ay * l.y * relief
			var n := Vector3(nl.x, nl.y, z).normalized()
			var lit := 0.55 + 0.6 * maxf(n.dot(L), 0.0)
			over(img, at + Vector2i(x, y), Color(color.r * lit, color.g * lit, color.b * lit, cover * color.a))

## A line of width `width` from a to b (legs, cracks, fuzz).
static func stroke(img: Image, at: Vector2i, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (width + 1.0)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (width + 1.0)
	for y in range(maxi(0, int(lo.y)), mini(PX, int(hi.y) + 1)):
		for x in range(maxi(0, int(lo.x)), mini(PX, int(hi.x) + 1)):
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
			var cover := clampf(width * 0.5 - d + 0.5, 0.0, 1.0)
			if cover > 0.0:
				over(img, at + Vector2i(x, y), Color(color, cover * color.a))

## Darkens or lightens covered pixels near `centre` by `amount` (grain).
static func speck(img: Image, at: Vector2i, centre: Vector2, radius: float, amount: float) -> void:
	for y in range(maxi(0, int(centre.y - radius)), mini(PX, int(centre.y + radius) + 1)):
		for x in range(maxi(0, int(centre.x - radius)), mini(PX, int(centre.x + radius) + 1)):
			if Vector2(x + 0.5, y + 0.5).distance_to(centre) > radius:
				continue
			var c := img.get_pixelv(at + Vector2i(x, y))
			if c.a <= 0.0:
				continue
			img.set_pixelv(at + Vector2i(x, y), c.lightened(amount) if amount > 0.0 else c.darkened(-amount))

## `c` composited over the pixel at `p`.
static func over(img: Image, p: Vector2i, c: Color) -> void:
	var under := img.get_pixelv(p)
	var a := c.a + under.a * (1.0 - c.a)
	if a <= 0.0:
		return
	var rgb := (Vector3(c.r, c.g, c.b) * c.a + Vector3(under.r, under.g, under.b) * under.a * (1.0 - c.a)) / a
	img.set_pixelv(p, Color(rgb.x, rgb.y, rgb.z, a))

## The middle of a cell, and the body's radius, in cell pixels.
static func mid() -> Vector2:
	return Vector2(PX, PX) * 0.5

static func body() -> float:
	return PX * BODY

## Baked atlases by kind id: [ImageTexture, tinted], shared by every renderer.
static var _atlases: Dictionary = {}

## The atlas and tint flag of refuse kind `kind`'s look ("refuse:remnant" if
## it has none), baked on first use.
static func atlas_for(registry: Registry, kind: String) -> Array:
	if not _atlases.has(kind):
		var script: Script = registry.renderers.get("refuse:" + kind)
		if script == null:
			script = registry.renderers.get("refuse:remnant", RefuseLooks.Remnant)
		var painter: RefuseLook = script.new()
		_atlases[kind] = [ImageTexture.create_from_image(painter.bake(kind)), painter.tinted]
	return _atlases[kind]

## A dead worker's colour: its caste's, dulled.
static func corpse_tint(color: Color) -> Color:
	return color.darkened(0.2)
