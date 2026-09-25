class_name GroundMap
extends RefCounted
## What the surface ground is made of: a low-res grid of material weights
## (TEXEL world units per cell) built from a scenario's "ground" entry. Render
## only: it has its own noise seeds (never the Simulation's `rng`), is not
## hashed and does not change movement.
##
##   "ground": {
##     "base": "soil",                       material everywhere to start with
##     "regions": [                          painted in order, later over earlier
##       {"material": "sand", "shape": "circle", "center": [x, y], "radius": r, "soft": 60},
##       {"material": "moss", "shape": "rect", "rect": [x, y, w, h]},
##       {"material": "gravel", "shape": "polygon", "points": [[x, y], ...]},
##       {"material": "litter", "noise": {"scale": 300, "cover": 0.3}},
##       ...
##     ]
##   }
##   ("ground": "sand" is short for {"base": "sand"}.)
##
## Region keys: "soft" (edge width, world units, default 40), "ragged" (how far
## noise pushes the edge in and out, default soft * 0.8), "strength" (0-1, how
## much it covers what was there, default 1), "noise" ({"scale": world units,
## "cover": fraction of the region covered, "soft": 0-1 edge width in noise
## terms}) to paint only patches. A region without "shape" covers the world.
##
## Renderers read two textures: material_a() (RGBA = sand, gravel, moss,
## litter) and material_b() (R = dry clay); soil is what is left over.

const TEXEL := 8.0
const MATERIALS: Array[String] = ["soil", "sand", "gravel", "moss", "litter", "dry"]

var size: Vector2i
var world_size: Vector2
var seed_value: int = 0
## weights[m][cell]: weight of MATERIALS[m] per cell; the weights of a cell sum to 1.
var weights: Array[PackedFloat32Array] = []
## Bumped when the map changes, for renderers.
var version: int = 0
var _regions: int = 0

func _init(world_size_units: Vector2, scenario_seed: int = 0) -> void:
	world_size = world_size_units
	seed_value = scenario_seed
	size = Vector2i(ceili(world_size.x / TEXEL), ceili(world_size.y / TEXEL))
	for m in MATERIALS.size():
		var w := PackedFloat32Array()
		w.resize(size.x * size.y)
		w.fill(1.0 if m == 0 else 0.0)
		weights.append(w)

## Builds a map from a scenario's "ground" entry (a Dictionary or a material name).
static func from_data(data: Variant, world_size_units: Vector2, scenario_seed: int) -> GroundMap:
	var map := GroundMap.new(world_size_units, scenario_seed)
	var spec: Dictionary = {"base": data} if data is String else data
	map.set_base(str(spec.get("base", "soil")))
	for region: Dictionary in spec.get("regions", []):
		map.paint(region)
	return map

static func material_index(material: String) -> int:
	return MATERIALS.find(material)

## Fills the whole map with one material.
func set_base(material: String) -> void:
	var m := material_index(material)
	if m < 0:
		push_error("Unknown ground material '%s'" % material)
		return
	for k in MATERIALS.size():
		weights[k].fill(1.0 if k == m else 0.0)
	version += 1

## Paints one region (see the class notes) over what is there.
func paint(region: Dictionary) -> void:
	var m := material_index(str(region.get("material", "")))
	if m < 0:
		push_error("Unknown ground material '%s'" % region.get("material", ""))
		return
	_regions += 1
	var cover := coverage(region, _regions)
	for i in cover.size():
		var c := cover[i]
		if c <= 0.0:
			continue
		for k in MATERIALS.size():
			weights[k][i] *= 1.0 - c
		weights[m][i] += c
	version += 1

## How much a region covers each cell (0-1). `salt` varies the noise per region.
func coverage(region: Dictionary, salt: int = 0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(size.x * size.y)
	var soft := maxf(float(region.get("soft", 40.0)), 1.0)
	var ragged := float(region.get("ragged", soft * 0.8))
	var strength := clampf(float(region.get("strength", 1.0)), 0.0, 1.0)
	var shape := str(region.get("shape", ""))
	var edge_noise := _noise(salt * 2 + 1, maxf(soft * 2.5, 60.0))
	var patches: FastNoiseLite = null
	var threshold := 0.0
	var band := 0.0
	var noise_spec: Dictionary = region.get("noise", {})
	if not noise_spec.is_empty():
		patches = _noise(salt * 2 + 2, float(noise_spec.get("scale", 300.0)))
		var cover := clampf(float(noise_spec.get("cover", 0.5)), 0.0, 1.0)
		threshold = _quantile(patches, 1.0 - cover)
		band = float(noise_spec.get("soft", 0.15))
	var points := PackedVector2Array()
	if shape == "polygon":
		points = ScenarioEvents.points(region["points"])
	var rect := Rect2()
	if shape == "rect":
		rect = ScenarioEvents.rect2(region["rect"])
	var center := ScenarioEvents.vec2(region.get("center", [0, 0]))
	var radius := float(region.get("radius", 0.0))
	for y in size.y:
		for x in size.x:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) * TEXEL
			var c := strength
			if shape != "":
				# Signed distance inside the shape, its edge pushed in and out by noise.
				var sd := 0.0
				match shape:
					"circle":
						sd = radius - p.distance_to(center)
					"rect":
						var d := Vector2(maxf(rect.position.x - p.x, p.x - rect.end.x), maxf(rect.position.y - p.y, p.y - rect.end.y))
						sd = -(maxf(d.x, d.y) if d.x <= 0.0 or d.y <= 0.0 else d.length())
					"polygon":
						sd = _polygon_distance(points, p)
					_:
						push_error("Unknown ground region shape '%s'" % shape)
						return out
				sd += edge_noise.get_noise_2dv(p) * ragged
				c *= smoothstep(-soft * 0.5, soft * 0.5, sd)
			if patches != null and c > 0.0:
				c *= smoothstep(threshold - band * 0.5, threshold + band * 0.5, patches.get_noise_2dv(p))
			out[y * size.x + x] = c
	return out

## Weight of `material` at a world position (nearest cell).
func weight_at(material: String, at: Vector2) -> float:
	var m := material_index(material)
	if m < 0:
		return 0.0
	var x := clampi(int(at.x / TEXEL), 0, size.x - 1)
	var y := clampi(int(at.y / TEXEL), 0, size.y - 1)
	return weights[m][y * size.x + x]

## Every material's weight at a world position, by name.
func weights_at(at: Vector2) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	for m in MATERIALS:
		out[m] = weight_at(m, at)
	return out

## RGBA8 image: sand, gravel, moss, litter weights.
func material_a() -> Image:
	return _pack([1, 2, 3, 4], Image.FORMAT_RGBA8)

## R8 image: dry clay weight.
func material_b() -> Image:
	return _pack([5], Image.FORMAT_R8)

func _pack(materials: Array[int], format: Image.Format) -> Image:
	var n := size.x * size.y
	var channels := materials.size()
	var bytes := PackedByteArray()
	bytes.resize(n * channels)
	for i in n:
		for k in channels:
			bytes[i * channels + k] = clampi(roundi(weights[materials[k]][i] * 255.0), 0, 255)
	return Image.create_from_data(size.x, size.y, false, format, bytes)

func _noise(salt: int, scale: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = (seed_value * 7919 + salt * 104729) & 0x7FFFFFFF
	n.frequency = 1.0 / maxf(scale, 1.0)
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	return n

## The noise value below which a fraction `q` of the map's cells lie.
func _quantile(noise: FastNoiseLite, q: float) -> float:
	var values := PackedFloat32Array()
	values.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			values[y * size.x + x] = noise.get_noise_2d((x + 0.5) * TEXEL, (y + 0.5) * TEXEL)
	values.sort()
	if q <= 0.0:
		return values[0] - 1.0
	if q >= 1.0:
		return values[values.size() - 1] + 1.0
	return values[int(q * (values.size() - 1))]

## Distance to the polygon's edge, positive inside.
static func _polygon_distance(points: PackedVector2Array, p: Vector2) -> float:
	var d := INF
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return d if Geometry2D.is_point_in_polygon(p, points) else -d
