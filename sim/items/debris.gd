class_name Debris
extends RefCounted
## Procedural debris lying on the ground: twigs and pebbles. They are Items
## (so ants can pick them up and carry them) that obstruct: ants crossing
## them are slowed until something moves them.
##
## spec: {"type": "twig", "pos": [x, y], "rotation": deg, "length": 36, "mass": 2}
##       {"type": "pebble", "pos": [x, y], "radius": 5, "mass": 2}
## Omitted values are randomised with the simulation's RNG.

## Pixels per world unit in debris images.
const RES := 2.0

static func create(sim: Simulation, spec: Dictionary) -> Item:
	var rng := sim.rng
	var kind: String = spec.get("type", "twig")
	var at := ScenarioEvents.vec2(spec["pos"])
	var rot := deg_to_rad(float(spec.get("rotation", rng.randf_range(0.0, 360.0))))
	var item: Item
	if kind == "pebble":
		var r := float(spec.get("radius", rng.randf_range(3.5, 6.5)))
		item = sim.create_item("pebble", float(spec.get("mass", r * r * 0.08)))
		item.shape = _pebble_image(r, rng)
		item.footprint = r + 3.0
	else:
		var length := float(spec.get("length", rng.randf_range(24.0, 44.0)))
		item = sim.create_item("twig", float(spec.get("mass", length * 0.05)))
		item.shape = twig_image(length, -1.0, rng)
		item.footprint = length * 0.5
	item.pixel_size = 1.0 / RES
	item.obstructs = true
	sim.place_on_ground(item, at, rot)
	return item

## A slightly bent stick along +x (`length` long, `half_width` thick at its
## base, world units) with a side sprig, bark shading and ends, at RES pixels
## per world unit. half_width < 0 picks a random twig thickness. Also used to
## draw bridges.
static func twig_image(length: float, half_width: float, rng: RandomNumberGenerator) -> Image:
	var w := int(ceil(length * RES)) + 4
	var h := int(ceil((maxf(half_width, 2.5) * 2.0 + 9.0) * RES))
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var base := Color(0.44, 0.32, 0.2).lerp(Color(0.55, 0.42, 0.28), rng.randf())
	var bend := rng.randf_range(-2.0, 2.0) * RES
	# (Random draws stay in this order so existing scenarios replay identically.)
	var thick := (half_width if half_width > 0.0 else rng.randf_range(2.2, 3.0)) * RES
	var sprig_at := rng.randf_range(0.35, 0.65)
	var sprig_dir := 1.0 if rng.randf() < 0.5 else -1.0
	var cy := h * 0.5
	for x in w:
		var t := float(x) / w
		var centre := cy + bend * sin(t * PI)
		var half := thick * (1.0 - 0.35 * t)
		for y in h:
			var d := absf(y + 0.5 - centre) / half
			# Side sprig: a short thin branch angled toward the far end.
			var sprig := 99.0
			if t > sprig_at and t < sprig_at + 0.22:
				var st := (t - sprig_at) / 0.22
				sprig = absf(y + 0.5 - (centre + sprig_dir * st * maxf(5.0 * RES, thick * 1.8))) / (thick * 0.45)
			var m := minf(d, sprig)
			if m < 1.0:
				var shade := 1.0 - 0.45 * clampf((y + 0.5 - centre) / half, -1.0, 1.0) * 0.5
				# Bark: faint grooves along the stick.
				shade *= 1.0 - 0.1 * (0.5 + 0.5 * sin((y + 0.5 - centre) / half * 9.0 + sin(x * 0.07) * 1.5))
				var c := base * shade
				if m > 0.7:
					c = c.darkened(0.3)
				c.a = clampf((1.0 - m) * half, 0.0, 1.0)
				img.set_pixel(x, y, c)
	return img

## A shaded, slightly irregular pebble.
static func _pebble_image(r: float, rng: RandomNumberGenerator) -> Image:
	var size := int(ceil(r * 2.0 * RES)) + 2
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var base := Color(0.48, 0.44, 0.38).lerp(Color(0.62, 0.57, 0.5), rng.randf())
	var squash := rng.randf_range(0.7, 0.95)
	var wobble := rng.randf() * TAU
	var c0 := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5) - c0) / RES
			var ang := p.angle()
			var rr := r * (1.0 + 0.08 * sin(ang * 3.0 + wobble))
			var d := Vector2(p.x, p.y / squash).length() / rr
			if d < 1.0:
				# Dome shading lit from the top-left.
				var n := p / rr
				var lit := clampf(0.75 - (n.x * 0.55 + n.y * 0.85) * 0.45, 0.35, 1.1)
				var c := base * lit
				c.a = clampf((1.0 - d) * rr * RES, 0.0, 1.0)
				img.set_pixel(x, y, c)
	return img
