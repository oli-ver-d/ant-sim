class_name LeafSource
extends FoodSource
@warning_ignore_start("integer_division")
## A procedurally generated leaf lying on the ground that leafcutters cut
## apart bite by bite.
##
## Shape: a bitmap mask in the leaf's own frame (x along the midrib from base
## to tip, y across), CELL world units per cell. The outline comes from a
## half-width profile (elliptic or lanceolate) with forward-pointing serrations
## and a gentle random wobble, plus a short stem at the base.
##
## Cutting: take() removes the tissue cells within the caste's bite radius of
## the edge cell nearest the ant. The centre is on the edge, so the bite is
## roughly a semicircle. The removed cells become the fragment Item's shape
## (anti-aliased, coloured with the same veins), so the carried piece matches
## the hole.
##
## Rendering: leaf.gdshader draws the mask (mask_rg) smoothly and computes the
## colour procedurally; color_at() is the CPU twin used for fragments.
##
## params: pos, rotation (deg), length, width, shape ("elliptic" | "lanceolate"),
##         teeth (serration count), seed, mass_per_cell, sense_radius
## species tunable: bite_radius (world units at carry_capacity 1)

const CELL := 3
const TISSUE := 1
const STEM := 2
## Fragment images are drawn at this many pixels per world unit.
const FRAGMENT_RES := 2

const BASE := Color(0.2, 0.56, 0.15)
const VEIN := Color(0.5, 0.76, 0.3)
const STEM_COLOR := Color(0.38, 0.5, 0.2)

var length: float = 360.0
var width: float = 160.0
var mass_per_cell: float = 0.15

## Grid size and cell contents (0 empty, TISSUE, STEM).
var nx: int
var ny: int
var mask: PackedByteArray = []
## The same mask as two bytes per cell (tissue 255/0, stem 255/0), kept in
## sync with `mask` so the renderer can upload it without a per-cell loop.
var mask_rg: PackedByteArray = []
var tissue_left: int = 0
var initial_tissue: int = 0
## Local position of the grid's (0, 0) corner relative to the leaf centre.
var origin: Vector2

# Vein pattern and mottling seed, shared with the shader.
var vein_count: int
var vein_dir: Vector2
var noise_seed: float

var _xf: Transform2D
var _inv_xf: Transform2D
var _edges: PackedInt32Array = []
var _edge_pos: PackedVector2Array = []
var _edges_dirty := true

func setup(sim: Simulation, params: Dictionary) -> void:
	super.setup(sim, params)
	length = params.get("length", length)
	width = params.get("width", width)
	mass_per_cell = params.get("mass_per_cell", mass_per_cell)
	var seed_value: int = int(params.get("seed", sim.rng.randi()))
	_xf = Transform2D(rotation, position)
	_inv_xf = _xf.affine_inverse()
	_generate(seed_value, params.get("shape", "elliptic"), int(params.get("teeth", 26)))

# --- Generation ------------------------------------------------------------------

## Half-width of the blade at t in [0, 1] (base -> tip), before serration.
func _profile(t: float, shape: String) -> float:
	if t <= 0.0 or t >= 1.0:
		return 0.0
	if shape == "lanceolate":
		# Widest near the base, long tapering tip.
		return 0.5 * width * pow(sin(PI * pow(t, 0.6)), 1.1)
	# Elliptic: widest just below the middle, rounded base, slightly pointed tip.
	return 0.5 * width * pow(sin(PI * pow(t, 0.85)), 0.75)

func _generate(seed_value: int, shape: String, teeth: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	noise_seed = rng.randf() * 100.0
	var stem_len := length * 0.12
	var stem_half := maxf(CELL * 0.8, width * 0.02)
	nx = int(ceil((length + stem_len) / CELL)) + 2
	ny = int(ceil(width / CELL)) + 2
	origin = Vector2(-length * 0.5 - stem_len - CELL, -ny * CELL * 0.5)
	mask.resize(nx * ny)
	mask_rg.resize(nx * ny * 2)

	var tooth_depth := rng.randf_range(0.04, 0.08)
	var wobble_amp := rng.randf_range(0.02, 0.05)
	var wobble_freq := rng.randf_range(4.0, 8.0)
	var wobble_phase := rng.randf() * TAU
	vein_count = int(clampf(length / 32.0, 5, 14))
	var vein_angle := deg_to_rad(rng.randf_range(45.0, 60.0))
	vein_dir = Vector2(cos(vein_angle), sin(vein_angle))

	for cy in ny:
		for cx in nx:
			var p := _cell_local(cx, cy)
			var t := (p.x + length * 0.5) / length
			var hw := _profile(t, shape)
			if hw > 0.0:
				# Forward-pointing saw teeth and a slow wobble along the margin.
				var tooth := fposmod(t * teeth, 1.0)
				hw *= (1.0 - tooth_depth * tooth) * (1.0 + wobble_amp * sin(t * wobble_freq + wobble_phase))
			var i := cy * nx + cx
			if absf(p.y) <= hw:
				mask[i] = TISSUE
				mask_rg[i * 2] = 255
				tissue_left += 1
			elif p.x < -length * 0.5 + length * 0.04 and p.x > -length * 0.5 - stem_len and absf(p.y) <= stem_half:
				mask[i] = STEM
				mask_rg[i * 2 + 1] = 255
	initial_tissue = tissue_left

func _cell_local(cx: int, cy: int) -> Vector2:
	return origin + Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)

## Leaf colour at a local position (no rim or mottling). Mirrors leaf.gdshader.
func color_at(p: Vector2) -> Color:
	var t := (p.x + length * 0.5) / length
	var mid_w := CELL * (0.35 + 0.45 * (1.0 - t))
	var v := 1.0 - smoothstep(mid_w - 0.5, mid_w + 0.5, absf(p.y))
	var d := Vector2(vein_dir.x, vein_dir.y * signf(p.y))
	for k in range(1, vein_count + 1):
		var rel := p - Vector2(-length * 0.5 + length * k / (vein_count + 1.0), 0.0)
		var along := rel.dot(d)
		if along > 0.0:
			var w := CELL * 0.35 * (1.0 - clampf(along / (width * 0.6), 0.0, 0.7))
			v = maxf(v, (1.0 - smoothstep(w - 0.5, w + 0.5, absf(rel.cross(d)))) * 0.85)
	return BASE.lerp(VEIN, v)

# --- FoodSource interface ------------------------------------------------------

func to_local(world_pos: Vector2) -> Vector2:
	return _inv_xf * world_pos

func to_world(local_pos: Vector2) -> Vector2:
	return _xf * local_pos

## Cheap test: inside an ellipse around the blade grown by sense_radius.
func is_sensed_at(pos: Vector2, _colony: Colony) -> bool:
	if is_depleted():
		return false
	var p := to_local(pos)
	var a := length * 0.5 + sense_radius
	var b := width * 0.5 + sense_radius
	return (p.x * p.x) / (a * a) + (p.y * p.y) / (b * b) <= 1.0

## The sensing ellipse fits in a circle of its larger semi-axis.
func sense_bound() -> float:
	return maxf(length, width) * 0.5 + sense_radius + 1.0

## World centre of the edge cell closest to pos (or the leaf centre if none).
func nearest_access_point(pos: Vector2) -> Vector2:
	var cell := _nearest_edge_cell(to_local(pos))
	if cell < 0:
		return position
	return to_world(_cell_local(cell % nx, cell / nx))

func is_depleted() -> bool:
	return tissue_left <= 0

func remaining_mass() -> float:
	return tissue_left * mass_per_cell

## Cuts a bite at the edge next to the ant. Bite radius scales with the
## square root of the caste's carry_capacity, so bite *area* scales with it.
func take(sim: Simulation, ant: int) -> Item:
	var local := to_local(sim.pos[ant])
	var centre_cell := _nearest_edge_cell(local)
	if centre_cell < 0:
		return null
	var centre := _cell_local(centre_cell % nx, centre_cell / nx)
	# Only bite if the ant is actually at that edge (another ant may have cut it away).
	if centre.distance_to(local) > CELL * 2.5:
		return null
	var bite_radius: float = sim.colony_of(ant).params.get(&"bite_radius", 6.0)
	var radius := bite_radius * sqrt(sim.caste_of(ant).carry_capacity)

	var rc := int(ceil(radius / CELL))
	var ccx := centre_cell % nx
	var ccy := centre_cell / nx
	var removed: PackedInt32Array = []
	for cy in range(maxi(0, ccy - rc), mini(ny, ccy + rc + 1)):
		for cx in range(maxi(0, ccx - rc), mini(nx, ccx + rc + 1)):
			if mask[cy * nx + cx] == TISSUE and _cell_local(cx, cy).distance_to(centre) <= radius:
				removed.append(cy * nx + cx)
	if removed.is_empty():
		return null

	var item := sim.create_item("leaf_fragment", removed.size() * mass_per_cell)
	item.source_id = id
	item.shape = _fragment_image(removed)
	item.pixel_size = 1.0 / FRAGMENT_RES
	item.color = BASE

	for cell in removed:
		mask[cell] = 0
		mask_rg[cell * 2] = 0
	tissue_left -= removed.size()
	taken_mass += item.mass
	_edges_dirty = true
	version += 1
	return item

## Anti-aliased image of the removed cells, coloured like the leaf. The alpha
## comes from bilinearly sampling the removed-cell mask and thresholding it
## smoothly, which matches how the shader draws the hole's outline.
func _fragment_image(cells: PackedInt32Array) -> Image:
	var in_bite := {}
	var min_c := Vector2i(nx, ny)
	var max_c := Vector2i(-1, -1)
	for cell in cells:
		var c := Vector2i(cell % nx, cell / nx)
		in_bite[c] = true
		min_c = min_c.min(c)
		max_c = max_c.max(c)
	# One cell of padding so the soft edge isn't clipped.
	min_c -= Vector2i.ONE
	max_c += Vector2i.ONE
	var local0 := origin + Vector2(min_c) * CELL
	var size_px := (max_c - min_c + Vector2i.ONE) * CELL * FRAGMENT_RES
	var img := Image.create_empty(size_px.x, size_px.y, false, Image.FORMAT_RGBA8)
	for py in size_px.y:
		for px in size_px.x:
			var p := local0 + (Vector2(px, py) + Vector2(0.5, 0.5)) / FRAGMENT_RES
			# Bilinear sample of the bite mask at p (cell centres are the samples).
			var g := (p - origin) / CELL - Vector2(0.5, 0.5)
			var g0 := Vector2i(floori(g.x), floori(g.y))
			var f := g - Vector2(g0)
			var m := lerpf(
				lerpf(1.0 if in_bite.has(g0) else 0.0, 1.0 if in_bite.has(g0 + Vector2i(1, 0)) else 0.0, f.x),
				lerpf(1.0 if in_bite.has(g0 + Vector2i(0, 1)) else 0.0, 1.0 if in_bite.has(g0 + Vector2i(1, 1)) else 0.0, f.x),
				f.y)
			var a := smoothstep(0.4, 0.6, m)
			if a > 0.0:
				var c := color_at(p).darkened(0.25 * (1.0 - smoothstep(0.5, 0.9, m)))
				c.a = a
				img.set_pixel(px, py, c)
	return img

func _nearest_edge_cell(local: Vector2) -> int:
	if _edges_dirty:
		_rebuild_edges()
	var k := NativeAnts.nearest_point(_edge_pos, local)
	return _edges[k] if k >= 0 else -1

func _tissue(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < nx and cy < ny and mask[cy * nx + cx] == TISSUE

func _rebuild_edges() -> void:
	_edges = NativeAnts.mask_edges(mask, nx, ny, TISSUE)
	_edge_pos.resize(_edges.size())
	for k in _edges.size():
		_edge_pos[k] = _cell_local(_edges[k] % nx, _edges[k] / nx)
	_edges_dirty = false
