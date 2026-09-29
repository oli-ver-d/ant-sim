class_name GroundSwatches
extends RefCounted
## Editor colours for the ground materials: dropdown icons and the flat
## "materials" overview image. Slightly more separated than the shader's colours.

const COLORS: Dictionary = {
	"soil": Color(0.36, 0.23, 0.13),
	"sand": Color(0.86, 0.73, 0.45),
	"gravel": Color(0.58, 0.58, 0.60),
	"moss": Color(0.30, 0.55, 0.16),
	"litter": Color(0.62, 0.32, 0.12),
	"dry": Color(0.72, 0.62, 0.50),
}

static var _icons: Dictionary = {}

static func color(material: String) -> Color:
	return COLORS.get(material, Color(1.0, 0.0, 1.0))

## A filled square swatch with a 1 px darker border (cached per material/size).
static func icon(material: String, px: int = 14) -> ImageTexture:
	var key := "%s:%d" % [material, px]
	if _icons.has(key):
		return _icons[key]
	var c := color(material)
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(c)
	var border := c.darkened(0.45)
	for i: int in px:
		img.set_pixel(i, 0, border)
		img.set_pixel(i, px - 1, border)
		img.set_pixel(0, i, border)
		img.set_pixel(px - 1, i, border)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex

## One pixel per ground cell: the weight-blended swatch colours.
static func image(ground: GroundMap) -> Image:
	var n := ground.size.x * ground.size.y
	var mats: Array[String] = GroundMap.MATERIALS
	var r := PackedFloat32Array()
	var g := PackedFloat32Array()
	var b := PackedFloat32Array()
	r.resize(n)
	g.resize(n)
	b.resize(n)
	for m: int in mats.size():
		var c := color(mats[m])
		var w: PackedFloat32Array = ground.weights[m]
		for i: int in n:
			var wi: float = w[i]
			r[i] += wi * c.r
			g[i] += wi * c.g
			b[i] += wi * c.b
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for i: int in n:
		bytes[i * 4] = clampi(roundi(r[i] * 255.0), 0, 255)
		bytes[i * 4 + 1] = clampi(roundi(g[i] * 255.0), 0, 255)
		bytes[i * 4 + 2] = clampi(roundi(b[i] * 255.0), 0, 255)
		bytes[i * 4 + 3] = 255
	return Image.create_from_data(ground.size.x, ground.size.y, false, Image.FORMAT_RGBA8, bytes)

## True when `choices` are exactly the ground materials (any order).
static func is_material_choice(choices: PackedStringArray) -> bool:
	if choices.size() != GroundMap.MATERIALS.size():
		return false
	for m: String in GroundMap.MATERIALS:
		if not choices.has(m):
			return false
	return true
