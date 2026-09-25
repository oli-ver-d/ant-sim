class_name GroundCoverRenderer
extends MultiMeshInstance2D
## Flat decals lying on the surface ground: dried plant fragments, bark bits,
## seed husks, twiglets, straws and crumbs. Scattered once from the ground's
## material map (GroundMap): thick on litter, sparse elsewhere. Render only:
## not items, no clutter, no effect on the ants, its own RNG (never sim.rng).
##
## The sprites are baked procedurally into one atlas image and drawn with one
## MultiMesh (ground_cover.gdshader: tint and contact shadow).

enum Kind { FRAGMENT, BROKEN, BARK, HUSK, TWIGLET, STRAW, CRUMBS }

## Atlas: CELLS x CELLS sprites of CELL_PX pixels. Each entry is the kind drawn in that cell.
const CELLS := 4
const CELL_PX := 48
const ATLAS: Array[Kind] = [
	Kind.FRAGMENT, Kind.FRAGMENT, Kind.FRAGMENT, Kind.FRAGMENT,
	Kind.FRAGMENT, Kind.BROKEN, Kind.BROKEN, Kind.BARK,
	Kind.BARK, Kind.HUSK, Kind.HUSK, Kind.TWIGLET,
	Kind.TWIGLET, Kind.STRAW, Kind.STRAW, Kind.CRUMBS,
]
## Candidate spacing (world units): one candidate per cell of this jittered grid.
const SPACING := 5.0
## Chance of a decal per candidate on each material (GroundMap.MATERIALS order:
## soil, sand, gravel, moss, litter, dry).
const DENSITY: Array[float] = [0.05, 0.025, 0.03, 0.06, 1.0, 0.03]
## Relative odds of each kind on each material (rows as DENSITY, columns as Kind).
const KIND_ODDS: Array = [
	[1.0, 0.6, 0.8, 1.2, 1.4, 0.6, 1.2],   # soil
	[0.3, 0.2, 0.2, 1.4, 0.6, 1.4, 0.2],   # sand
	[0.4, 0.3, 0.4, 0.8, 1.0, 0.6, 0.2],   # gravel
	[1.0, 0.8, 0.8, 0.3, 1.2, 0.3, 0.2],   # moss
	[4.0, 2.0, 1.0, 0.6, 1.0, 0.5, 0.3],   # litter
	[0.8, 0.4, 0.2, 0.6, 0.6, 1.4, 0.2],   # dry
]
## Size range per kind (world units across the quad; the sprite fills ~80% of it).
const SIZES: Array[Vector2] = [
	Vector2(6.0, 11.0), Vector2(5.0, 9.0), Vector2(4.0, 7.5), Vector2(2.6, 4.0),
	Vector2(7.0, 14.0), Vector2(8.0, 16.0), Vector2(3.0, 5.0),
]
const STRIDE := 16

var sim: Simulation
var _version: int = -1

func bind(simulation: Simulation) -> void:
	sim = simulation
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = AntRenderer._unit_quad()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/scenery/ground_cover.gdshader")
	var atlas := bake_atlas(sim.ground.seed_value if sim.ground != null else 0)
	atlas.generate_mipmaps()
	mat.set_shader_parameter("atlas", ImageTexture.create_from_image(atlas))
	mat.set_shader_parameter("cells", float(CELLS))
	material = mat

func _process(_delta: float) -> void:
	if sim == null or sim.ground == null or sim.ground.version == _version:
		return
	_version = sim.ground.version
	var buffer := scatter(sim.ground)
	multimesh.instance_count = buffer.size() / STRIDE
	if not buffer.is_empty():
		multimesh.buffer = buffer
	queue_redraw()

## Instance buffer (STRIDE floats each) for every decal on `ground`.
static func scatter(ground: GroundMap) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = (ground.seed_value * 48271 + 911) & 0x7FFFFFFF
	var out := PackedFloat32Array()
	var nx := int(ground.world_size.x / SPACING)
	var ny := int(ground.world_size.y / SPACING)
	var mat_weights := PackedFloat32Array()
	mat_weights.resize(GroundMap.MATERIALS.size())
	var odds := PackedFloat32Array()
	odds.resize(Kind.size())
	# Atlas cells of each kind.
	var by_kind: Array[Array] = []
	for k in Kind.size():
		by_kind.append([] as Array[int])
	for c in ATLAS.size():
		by_kind[ATLAS[c]].append(c)
	for gy in ny:
		for gx in nx:
			var at := Vector2(gx + rng.randf(), gy + rng.randf()) * SPACING
			var roll := rng.randf()
			var pick := rng.randf()
			var ci := clampi(int(at.y / GroundMap.TEXEL), 0, ground.size.y - 1) * ground.size.x \
					+ clampi(int(at.x / GroundMap.TEXEL), 0, ground.size.x - 1)
			var density := 0.0
			for m in mat_weights.size():
				mat_weights[m] = ground.weights[m][ci]
				density += mat_weights[m] * DENSITY[m]
			if roll >= density:
				continue
			# Kind: the odds of every material blended by weight.
			odds.fill(0.0)
			var total := 0.0
			for m in mat_weights.size():
				if mat_weights[m] <= 0.0:
					continue
				for k in Kind.size():
					odds[k] += mat_weights[m] * KIND_ODDS[m][k]
			for k in Kind.size():
				total += odds[k]
			var kind := 0
			var acc := pick * total
			for k in Kind.size():
				acc -= odds[k]
				if acc <= 0.0:
					kind = k
					break
			var cells: Array[int] = by_kind[kind]
			var cell: int = cells[rng.randi() % cells.size()]
			var s := rng.randf_range(SIZES[kind].x, SIZES[kind].y)
			var rot := rng.randf() * TAU
			# Tint: brightness and a little warm/grey variation.
			var b := rng.randf_range(0.72, 1.08)
			var warm := rng.randf_range(-0.06, 0.06)
			var c := cos(rot) * s
			var sn := sin(rot) * s
			out.append_array([c, -sn, 0.0, at.x, sn, c, 0.0, at.y,
				b * (1.0 + warm), b, b * (1.0 - warm), 1.0,
				float(cell), rot, s, 0.0])
	return out

## The sprite atlas: CELLS x CELLS cells of CELL_PX pixels, each sprite within
## the middle ~80% of its cell (room for its shadow).
static func bake_atlas(seed_value: int) -> Image:
	var img := Image.create_empty(CELLS * CELL_PX, CELLS * CELL_PX, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value * 16807 + 77) & 0x7FFFFFFF
	for i in ATLAS.size():
		var ox := (i % CELLS) * CELL_PX
		var oy := (i / CELLS) * CELL_PX
		var look := _look(ATLAS[i], rng)
		for y in CELL_PX:
			for x in CELL_PX:
				# Sprite space: -1..1 over the middle 80% of the cell, +x along the sprite.
				var p := (Vector2(x + 0.5, y + 0.5) / CELL_PX - Vector2(0.5, 0.5)) * 2.5
				var col: Color = look.call(p)
				img.set_pixel(ox + x, oy + y, col)
	return img

## A function of sprite-space position returning the sprite's colour (alpha = coverage).
static func _look(kind: Kind, rng: RandomNumberGenerator) -> Callable:
	var aa := 2.5 * 1.5 / CELL_PX
	match kind:
		Kind.FRAGMENT:
			# A dried plant fragment: pointed oval, midrib, side veins, curled edges, a tear.
			var width := rng.randf_range(0.28, 0.5)
			var base := Color(0.46, 0.3, 0.14).lerp(Color(0.38, 0.33, 0.24), rng.randf())
			base = base.lerp(Color(0.55, 0.38, 0.16), rng.randf() * 0.5)
			var bend := rng.randf_range(-0.25, 0.25)
			var tear := Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(0.2, 0.5) * (1 if rng.randf() < 0.5 else -1))
			var tear_r := rng.randf_range(0.0, 0.25)
			var wobble := rng.randf() * 10.0
			return func(p: Vector2) -> Color:
				var y := p.y - bend * (1.0 - p.x * p.x)
				var half := width * sqrt(maxf(1.0 - p.x * p.x, 0.0)) * (1.0 - 0.3 * maxf(p.x, 0.0))
				half *= 1.0 + 0.08 * sin(p.x * 17.0 + wobble)
				var d := absf(y) - half
				if p.distance_to(tear) < tear_r:
					d = maxf(d, tear_r - p.distance_to(tear))
				var a := clampf(0.5 - d / aa, 0.0, 1.0)
				if a <= 0.0:
					return Color(0, 0, 0, 0)
				var t := clampf(y / maxf(half, 0.01), -1.0, 1.0)
				# Curled: the edges lift and catch light on one side.
				var shade := 0.85 + 0.22 * t * absf(t)
				var vein := 1.0 - smoothstep(0.0, 0.06, absf(y))
				var side := 1.0 - smoothstep(0.0, 0.08, absf(fposmod(p.x * 3.0 - absf(y) * 3.5, 1.0) - 0.5) * 0.4)
				var c := base * shade
				c = c.lerp(base.lightened(0.25), vein * 0.6).lerp(base.darkened(0.2), side * 0.35)
				c = c.darkened(0.3 * smoothstep(0.7, 1.0, absf(t)))
				return Color(c, a)
		Kind.BROKEN:
			# A torn piece: an irregular lobed chunk.
			var base := Color(0.4, 0.26, 0.12).lerp(Color(0.33, 0.27, 0.2), rng.randf())
			var lobes: Array[float] = []
			for k in 6:
				lobes.append(rng.randf_range(0.45, 0.85))
			var phase := rng.randf() * TAU
			return func(p: Vector2) -> Color:
				var ang := fposmod(p.angle() + phase, TAU) / TAU * 6.0
				var k0 := int(ang) % 6
				var r := lerpf(lobes[k0], lobes[(k0 + 1) % 6], smoothstep(0.0, 1.0, fposmod(ang, 1.0))) * 0.8
				var d := p.length() - r
				var a := clampf(0.5 - d / aa, 0.0, 1.0)
				if a <= 0.0:
					return Color(0, 0, 0, 0)
				var vein := 1.0 - smoothstep(0.0, 0.05, absf(p.y + p.x * 0.3))
				var c := base * (0.9 + 0.15 * p.normalized().dot(Vector2(-0.55, -0.85)) * smoothstep(0.0, r, p.length()))
				return Color(c.lerp(base.lightened(0.2), vein * 0.5), a)
		Kind.BARK:
			# A flake of bark: rough rectangle, dark ridged outer face.
			var base := Color(0.25, 0.17, 0.1).lerp(Color(0.3, 0.26, 0.2), rng.randf())
			var w := rng.randf_range(0.35, 0.55)
			var skew := rng.randf_range(-0.3, 0.3)
			return func(p: Vector2) -> Color:
				var q := Vector2(p.x + p.y * skew, p.y)
				var rough := 0.06 * sin(q.y * 23.0) + 0.05 * sin(q.x * 31.0 + 1.0)
				var d := maxf(absf(q.x) - 0.85 - rough, absf(q.y) - w - rough)
				var a := clampf(0.5 - d / aa, 0.0, 1.0)
				if a <= 0.0:
					return Color(0, 0, 0, 0)
				var ridge := 0.5 + 0.5 * sin(q.y * 26.0 + sin(q.x * 5.0) * 1.5)
				var c := base * (0.75 + 0.4 * ridge)
				# A paler broken edge.
				c = c.lerp(Color(0.5, 0.36, 0.22), smoothstep(-0.12, 0.0, d) * 0.6)
				return Color(c, a)
		Kind.HUSK:
			# An empty seed husk: two pale split halves.
			var base := Color(0.62, 0.52, 0.36).lerp(Color(0.5, 0.4, 0.26), rng.randf())
			var gap := rng.randf_range(0.04, 0.16)
			return func(p: Vector2) -> Color:
				var e := Vector2(p.x / 0.85, (absf(p.y) - gap) / 0.45)
				var d := (e.length() - 1.0) * 0.45
				var a := clampf(0.5 - d / aa, 0.0, 1.0)
				if a <= 0.0 or absf(p.y) < gap:
					return Color(0, 0, 0, 0)
				var rim := smoothstep(0.6, 1.0, e.length())
				# Hollow inside: darker in the middle of each half.
				var c := base.darkened(0.35 * (1.0 - rim))
				return Color(c, a)
		Kind.TWIGLET:
			# A thin bent twig with a node.
			var base := Color(0.36, 0.25, 0.15).lerp(Color(0.3, 0.27, 0.22), rng.randf())
			var bend := rng.randf_range(-0.2, 0.2)
			var thick := rng.randf_range(0.05, 0.09)
			var node := rng.randf_range(-0.4, 0.4)
			return func(p: Vector2) -> Color:
				var y := p.y - bend * (1.0 - p.x * p.x)
				var half := thick * (1.0 + 0.6 * (1.0 - smoothstep(0.0, 0.08, absf(p.x - node))))
				var d := maxf(absf(y) - half, absf(p.x) - 0.95)
				var a := clampf(0.5 - d / aa, 0.0, 1.0)
				if a <= 0.0:
					return Color(0, 0, 0, 0)
				var c := base * (1.05 - 0.35 * clampf(y / half, -1.0, 1.0) * 0.5 - 0.1)
				return Color(c, a)
		Kind.STRAW:
			# A bleached dry grass stem: long pale strip.
			var base := Color(0.62, 0.55, 0.38).lerp(Color(0.5, 0.42, 0.28), rng.randf())
			var bend := rng.randf_range(-0.1, 0.1)
			var w := rng.randf_range(0.035, 0.06)
			return func(p: Vector2) -> Color:
				var y := p.y - bend * (1.0 - p.x * p.x)
				var half := w * (1.0 - 0.5 * maxf(p.x, 0.0))
				var d := maxf(absf(y) - half, absf(p.x) - 0.97)
				var a := clampf(0.5 - d / aa, 0.0, 1.0)
				if a <= 0.0:
					return Color(0, 0, 0, 0)
				var c := base * (1.0 - 0.25 * absf(y) / maxf(half, 0.01))
				return Color(c, a)
		_:
			# Crumbs: a few small soil pellets.
			var dots: Array[Vector3] = []
			for k in rng.randi_range(3, 5):
				dots.append(Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6), rng.randf_range(0.15, 0.3)))
			var base := Color(0.2, 0.14, 0.09).lerp(Color(0.3, 0.22, 0.14), rng.randf())
			return func(p: Vector2) -> Color:
				var best := 9.0
				var lit := 0.0
				for dot in dots:
					var d := p.distance_to(Vector2(dot.x, dot.y)) - dot.z
					if d < best:
						best = d
						lit = (p - Vector2(dot.x, dot.y)).dot(Vector2(-0.55, -0.85)) / dot.z
				var a := clampf(0.5 - best / aa, 0.0, 1.0)
				if a <= 0.0:
					return Color(0, 0, 0, 0)
				return Color(base * (0.9 + 0.35 * lit), a)
