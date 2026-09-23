class_name FungusCutaway
extends Control
## Cutaway view of a FungusNest for CutawayPanel: a side section through the
## nest with its chambers (dug one by one as the garden grows), and the fungus
## garden filling them as soft off-white lumps (fungus_garden.gdshader). Green
## flecks show fresh leaf not yet digested. The colony's size is shown top right.
##
## The level of detail depends on the view's size:
## - small (an inset): a few tiny ants walk the tunnels, more of them in a
##   bigger colony.
## - large (DETAIL_WIDTH wide or more, e.g. the underground half of
##   SplitLayout): bigger chambers with room above the garden, and
##   NestLifeView draws the queen, the brood, nurses and leaf carriers. The
##   entrance lines up with `entrance_x` (set by SplitLayout), the labels
##   stay inside `safe_rect`, and each new worker is named in `highlight_ant`.
##
## Everything here only reads the nest; animation (digging, garden growth,
## the ants) runs on render time so it never touches the simulation.

## Chamber layout: centre and radii as fractions of the view width/height.
const CHAMBERS: Array[Rect2] = [
	Rect2(0.5, 0.42, 0.17, 0.12),
	Rect2(0.24, 0.62, 0.15, 0.1),
	Rect2(0.76, 0.6, 0.15, 0.1),
	Rect2(0.36, 0.85, 0.15, 0.09),
	Rect2(0.68, 0.86, 0.14, 0.09),
]
## Detailed layout (for a view about 1080 wide and 1000 tall): the royal
## chamber and the two brood chambers sit high, clear of the bottom caption
## area of a vertical video; the deeper chambers only hold garden.
const DETAIL_CHAMBERS: Array[Rect2] = [
	Rect2(0.5, 0.29, 0.29, 0.155),
	Rect2(0.2, 0.555, 0.175, 0.11),
	Rect2(0.74, 0.555, 0.16, 0.11),
	Rect2(0.33, 0.84, 0.16, 0.085),
	Rect2(0.7, 0.86, 0.15, 0.085),
]
## Tunnel k leads to chamber k: from the surface for chamber 0, otherwise
## from the chamber it branches off.
const TUNNEL_FROM: PackedInt32Array = [-1, 0, 0, 1, 2]
const SURFACE := 0.14
const DETAIL_SURFACE := 0.03
## Views at least this wide get the detailed view.
const DETAIL_WIDTH := 700.0
## Garden lumps per chamber; they appear bottom-up as the chamber fills.
const LUMPS_PER_CHAMBER := 16
## Video seconds to dig a new chamber, and to ease garden changes.
const DIG_TIME := 1.5
const GROW_TIME := 0.6
const ANT_COLOR := Color(0.55, 0.22, 0.1)

## Screen x of the nest entrance on the surface (view pixels); < 0 = centre.
var entrance_x: float = -1.0
## The part of the view not covered by app UI; empty = the whole view.
var safe_rect: Rect2 = Rect2()
## The ant that last came out of the nest (-1 = none), for SplitLayout to
## highlight on the surface.
var highlight_ant: int = -1
## Video seconds at the start during which the detailed view spotlights the
## queen (0 = none); set from the layout's "view" options.
var intro_spotlight: float = 0.0:
	set(v):
		intro_spotlight = v
		if _life != null:
			_life.spotlight_time = v
var detailed: bool = false

var sim: Simulation
var nest: FungusNest
var _view: ColorRect
var _life: NestLifeView
var _overlay: Control  # ants and text, drawn over the shader view
var _mat: ShaderMaterial
var _dig: PackedFloat32Array = [0, 0, 0, 0, 0]  # dig progress per chamber, 0-1
var _shown_fungus: float = -1.0
var _slots: Array[Vector3] = []  # lump slots: position (chamber-relative), max radius
var _clock: float = 0.0
var _shown_entrance: float = -1.0

func bind(simulation: Simulation, target: Object) -> void:
	sim = simulation
	nest = target as FungusNest
	detailed = size.x >= DETAIL_WIDTH
	_view = ColorRect.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://species/leafcutter/fungus_garden.gdshader")
	_view.material = _mat
	add_child(_view)
	if detailed:
		_life = NestLifeView.new()
		_life.set_anchors_preset(Control.PRESET_FULL_RECT)
		_life.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_life)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	# Chambers that already exist are shown fully dug.
	for k in nest.chambers:
		_dig[k] = 1.0
	# Lump slots, filling each chamber from the floor up: slot j sits at
	# height t = j / LUMPS_PER_CHAMBER, spread across the chamber's width there.
	# The detailed view keeps the top of each chamber clear for the ants.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for j in LUMPS_PER_CHAMBER:
		var t := (j + 0.5) / LUMPS_PER_CHAMBER
		var y := (0.84 - 0.78 * t) if detailed else (0.75 - 1.1 * t)
		var half := sqrt(maxf(0.0, 1.0 - y * y)) * (0.84 if detailed else 0.8)
		var x := rng.randf_range(-half, half)
		_slots.append(Vector3(x, y, rng.randf_range(0.2, 0.28) if detailed else rng.randf_range(0.26, 0.38)))
	if _life != null:
		_life.bind(sim, nest, self)
		_life.spotlight_time = intro_spotlight

func _process(delta: float) -> void:
	if nest == null or size.x < 1.0:
		return
	_clock += delta
	for k in nest.chambers:
		_dig[k] = minf(1.0, _dig[k] + delta / DIG_TIME)
	# Ease toward the nest's fungus so timelapse jumps look like growth.
	if _shown_fungus < 0.0:
		_shown_fungus = nest.fungus
	_shown_fungus = lerpf(_shown_fungus, nest.fungus, 1.0 - exp(-delta / GROW_TIME))
	var want := clampf(entrance_x if entrance_x >= 0.0 else size.x * 0.5, size.x * 0.25, size.x * 0.75)
	_shown_entrance = want if _shown_entrance < 0.0 else lerpf(_shown_entrance, want, 1.0 - exp(-delta / 0.3))
	_update_shader()
	_overlay.queue_redraw()

# --- Geometry (view pixels), shared with NestLifeView ---------------------------

func chamber_count() -> int:
	return nest.chambers

## Centre (position) and radii (size) of chamber k; radii grow while it's dug.
func chamber_rect(k: int) -> Rect2:
	var c := (DETAIL_CHAMBERS if detailed else CHAMBERS)[k]
	var dig := _dig[k]
	return Rect2(c.position * size, Vector2(c.size.x * size.x, c.size.y * size.y) * (0.25 + 0.75 * dig))

func surface_y() -> float:
	return size.y * (DETAIL_SURFACE if detailed else SURFACE)

## Where the entrance tunnel meets the surface.
func entrance() -> Vector2:
	var x := _shown_entrance if _shown_entrance >= 0.0 else size.x * 0.5
	return Vector2(x, surface_y() - 4.0)

## Share of chamber k filled with garden (0-1), eased like the drawing.
func fill(k: int) -> float:
	return clampf((_shown_fungus - k * nest.chamber_capacity) / nest.chamber_capacity, 0.0, 1.0) * _dig[k]

## Height of the garden's top in chamber k, where ants walk (detailed view).
func floor_y(k: int) -> float:
	var r := chamber_rect(k)
	return r.position.y + r.size.y * _floor_frac(k)

## Half the walkable width of chamber k's floor.
func floor_half(k: int) -> float:
	var f := _floor_frac(k)
	return chamber_rect(k).size.x * sqrt(maxf(0.0, 1.0 - f * f)) * 0.9

## A point on chamber k's floor, u from -1 (left end) to 1 (right end).
func floor_point(k: int, u: float) -> Vector2:
	return Vector2(chamber_rect(k).position.x + floor_half(k) * clampf(u, -1.0, 1.0), floor_y(k))

## Floor height as a fraction of the chamber's radius below its centre:
## near the bottom when empty, a little above the centre when full.
func _floor_frac(k: int) -> float:
	return 0.8 - 0.92 * fill(k)

## A walking route from `from` in chamber a to `to` in chamber b (-1 = the
## surface): along chamber floors and walls and through the tunnels.
func path(from: Vector2, a: int, to: Vector2, b: int) -> PackedVector2Array:
	var up := _chain(a)
	var down := _chain(b)
	var common := -1
	for k in up:
		if down.has(k):
			common = k
			break
	var out: PackedVector2Array = [from]
	var at := from
	# Climb from a up to the common chamber (through each tunnel to its parent)...
	var k := a
	while k != common:
		_walk_in(out, k, at, _mouth(k, true))
		at = _mouth(k, false)
		out.append(at)
		k = TUNNEL_FROM[k]
	# ...then down to b.
	for i in range(down.find(common) - 1, -1, -1):
		var next := down[i]
		_walk_in(out, k, at, _mouth(next, false))
		at = _mouth(next, true)
		out.append(at)
		k = next
	_walk_in(out, k, at, to)
	return out

## Chamber k and its ancestors up to the surface (-1).
func _chain(k: int) -> PackedInt32Array:
	var out: PackedInt32Array = []
	while k >= 0:
		out.append(k)
		k = TUNNEL_FROM[k]
	out.append(-1)
	return out

## Where tunnel k opens: into chamber k (inner = true) or into the chamber it
## branches off / the surface (inner = false).
func _mouth(k: int, inner: bool) -> Vector2:
	var parent := TUNNEL_FROM[k]
	var child_c := chamber_rect(k).position
	var parent_c := entrance() if parent < 0 else chamber_rect(parent).position
	if inner:
		return _wall_toward(k, parent_c)
	return entrance() if parent < 0 else _wall_toward(parent, child_c)

## The point on chamber k's wall (just inside) in the direction of `toward`.
func _wall_toward(k: int, toward: Vector2) -> Vector2:
	var r := chamber_rect(k)
	var d := (toward - r.position) / r.size
	return r.position + d.normalized() * r.size * 0.95

## Appends a walk inside chamber k (or on the surface for -1) from p to q:
## points on the wall (tunnel mouths) are reached along the wall from the
## floor, not through the air or across the garden.
func _walk_in(out: PackedVector2Array, k: int, p: Vector2, q: Vector2) -> void:
	if k < 0:
		out.append(q)
		return
	if _on_wall(k, p):
		out.append_array(_wall_arc(k, p, _descend_right(k, p, q)))
	if _on_wall(k, q):
		var arc := _wall_arc(k, q, _descend_right(k, q, p))
		arc.reverse()
		out.append_array(arc)
	out.append(q)

func _on_wall(k: int, p: Vector2) -> bool:
	var r := chamber_rect(k)
	return ((p - r.position) / r.size).length() > 0.93

## Which side of chamber k to walk down from wall point p: its own side, or
## toward `other` if p is near the top or bottom of the chamber.
func _descend_right(k: int, p: Vector2, other: Vector2) -> bool:
	var r := chamber_rect(k)
	if absf(p.x - r.position.x) < r.size.x * 0.15:
		return other.x > p.x
	return p.x > r.position.x

## Points along chamber k's wall from p (a point on the wall) to the end of
## the floor on the right (right = true) or left side, excluding p.
func _wall_arc(k: int, p: Vector2, right: bool) -> PackedVector2Array:
	var r := chamber_rect(k)
	var rel := (p - r.position) / r.size
	var a0 := atan2(rel.y, rel.x)
	var f := clampf(_floor_frac(k), -0.95, 0.95)
	var a1 := atan2(f, sqrt(1.0 - f * f) * (1.0 if right else -1.0))
	# Go the short way round the top.
	var da := wrapf(a1 - a0, -PI, PI)
	var out: PackedVector2Array = []
	var steps := maxi(2, int(absf(da) / 0.25))
	for s in range(1, steps + 1):
		var a := a0 + da * s / steps
		out.append(r.position + Vector2(cos(a), sin(a)) * r.size * 0.93)
	return out

# --- Drawing -----------------------------------------------------------------------

func _update_shader() -> void:
	var chambers: Array[Vector4] = []
	var tunnels: Array[Vector4] = []
	var lumps: Array[Vector4] = []
	var gate := entrance()
	for k in CHAMBERS.size():
		if k >= nest.chambers:
			chambers.append(Vector4.ZERO)
			continue
		var r := chamber_rect(k)
		chambers.append(Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		# The tunnel grows toward the new chamber while it's being dug.
		var from := gate if TUNNEL_FROM[k] < 0 else chamber_rect(TUNNEL_FROM[k]).position
		var to := from.lerp(r.position, minf(1.0, _dig[k] * 1.5))
		tunnels.append(Vector4(from.x, from.y, to.x, to.y))
		# Garden: this chamber's share of the fungus, in lump slots.
		var fill_k := fill(k)
		for j in LUMPS_PER_CHAMBER:
			var grow := clampf(fill_k * LUMPS_PER_CHAMBER - j, 0.0, 1.0)
			if grow <= 0.0:
				break
			var s := _slots[j]
			var at := r.position + Vector2(s.x * r.size.x, s.y * r.size.y)
			lumps.append(Vector4(at.x, at.y, s.z * r.size.y * sqrt(grow), 0.0))
	_mat.set_shader_parameter("view_size", size)
	_mat.set_shader_parameter("surface_y", surface_y())
	_mat.set_shader_parameter("entrance_x", gate.x)
	_mat.set_shader_parameter("mound_height", size.y * (0.03 + 0.008 * nest.chambers) * (0.4 if detailed else 1.0))
	_mat.set_shader_parameter("chambers", chambers)
	_mat.set_shader_parameter("chamber_count", chambers.size())
	_mat.set_shader_parameter("tunnels", tunnels)
	_mat.set_shader_parameter("tunnel_count", tunnels.size())
	_mat.set_shader_parameter("tunnel_width", size.x * 0.04 if detailed else maxf(5.0, size.x * 0.016))
	_mat.set_shader_parameter("lumps", lumps)
	_mat.set_shader_parameter("lump_count", lumps.size())
	_mat.set_shader_parameter("detailed", detailed)
	var total := nest.fungus + nest.substrate
	_mat.set_shader_parameter("fresh", nest.substrate / total if total > 0.0 else 0.0)

func _draw_overlay() -> void:
	var colony := sim.colonies[nest.colony_id]
	if detailed:
		_draw_detailed_labels(colony)
		return
	# Tiny ants walking the tunnels, back and forth; more for a bigger colony.
	var count := clampi(int(colony.population / 60.0), 2, 16)
	var gate := entrance()
	var ant_len := maxf(3.0, size.x * 0.012)
	for n in count:
		var k := n % nest.chambers
		if _dig[k] < 1.0:
			continue
		var from := gate if TUNNEL_FROM[k] < 0 else chamber_rect(TUNNEL_FROM[k]).position
		var to := chamber_rect(k).position
		# Each ant has its own speed and phase (fixed per index, render-only).
		var speed := 0.12 + 0.05 * fmod(n * 0.618, 1.0)
		var phase := fmod(_clock * speed + n * 0.37, 2.0)
		var t := phase if phase < 1.0 else 2.0 - phase
		var at := from.lerp(to, t)
		var dir := (to - from).normalized() * (1.0 if phase < 1.0 else -1.0)
		_overlay.draw_circle(at - dir * ant_len * 0.45, ant_len * 0.32, ANT_COLOR)
		_overlay.draw_circle(at, ant_len * 0.22, ANT_COLOR)
		_overlay.draw_circle(at + dir * ant_len * 0.4, ant_len * 0.25, ANT_COLOR.darkened(0.2))
	# Colony size, top right, in the strip above ground.
	var font := ThemeDB.fallback_font
	var fs := int(size.y * 0.07)
	var text := "%d ants" % colony.population
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_overlay.draw_string(font, Vector2(size.x - w - size.x * 0.03, size.y * SURFACE * 0.72), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85))

## Colony size and brood counts, top left inside the safe area.
func _draw_detailed_labels(colony: Colony) -> void:
	var safe := safe_rect if safe_rect.has_area() else Rect2(Vector2.ZERO, size)
	var font := ThemeDB.fallback_font
	var s := size.x / 1080.0
	var at := safe.position + Vector2(28, 30 + surface_y()) * s
	var lines: Array[String] = ["%d ants" % colony.population]
	if nest.brood != null:
		var b := nest.brood
		lines.append("%d eggs  ·  %d larvae  ·  %d pupae" % [b.count_stage(LeafcutterBrood.Stage.EGG),
				b.count_stage(LeafcutterBrood.Stage.LARVA),
				b.count_stage(LeafcutterBrood.Stage.PUPA) + b.count_stage(LeafcutterBrood.Stage.CALLOW)])
	var sizes: PackedInt32Array = [int(46 * s), int(28 * s)]
	for n in lines.size():
		var fs := sizes[mini(n, 1)]
		at.y += fs
		_overlay.draw_string_outline(font, at, lines[n], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(7 * s),
				Color(0.05, 0.03, 0.02, 0.8))
		_overlay.draw_string(font, at, lines[n], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.97, 0.9, 0.95))
		at.y += 10 * s
