class_name FungusCutaway
extends Control
## Cutaway view of a FungusNest for CutawayPanel: a side section through the
## nest with its chambers (dug one by one as the garden grows), and the fungus
## garden filling them as soft off-white lumps (fungus_garden.gdshader). Green
## flecks show fresh leaf not yet digested. A few tiny ants walk the tunnels,
## more of them in a bigger colony, and the colony's size is shown top right.
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
## Tunnel k leads to chamber k: from the surface for chamber 0, otherwise
## from the chamber it branches off.
const TUNNEL_FROM: PackedInt32Array = [-1, 0, 0, 1, 2]
const SURFACE := 0.14
## Garden lumps per chamber; they appear bottom-up as the chamber fills.
const LUMPS_PER_CHAMBER := 16
## Video seconds to dig a new chamber, and to ease garden changes.
const DIG_TIME := 1.5
const GROW_TIME := 0.6
const ANT_COLOR := Color(0.55, 0.22, 0.1)

var sim: Simulation
var nest: FungusNest
var _view: ColorRect
var _overlay: Control  # ants and text, drawn over the shader view
var _mat: ShaderMaterial
var _dig: PackedFloat32Array = [0, 0, 0, 0, 0]  # dig progress per chamber, 0-1
var _shown_fungus: float = -1.0
var _slots: Array[Vector3] = []  # lump slots: position (chamber-relative), max radius
var _clock: float = 0.0

func bind(simulation: Simulation, target: Object) -> void:
	sim = simulation
	nest = target as FungusNest
	_view = ColorRect.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://species/leafcutter/fungus_garden.gdshader")
	_view.material = _mat
	add_child(_view)
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for j in LUMPS_PER_CHAMBER:
		var t := (j + 0.5) / LUMPS_PER_CHAMBER
		var y := 0.75 - 1.1 * t
		var half := sqrt(maxf(0.0, 1.0 - y * y)) * 0.8
		_slots.append(Vector3(rng.randf_range(-half, half), y, rng.randf_range(0.26, 0.38)))

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
	_update_shader()
	_overlay.queue_redraw()

func _chamber_rect(k: int) -> Rect2:
	# Centre and radii in pixels; radii scaled by dig progress.
	var c := CHAMBERS[k]
	var dig := _dig[k]
	return Rect2(c.position * size, Vector2(c.size.x * size.x, c.size.y * size.y) * (0.25 + 0.75 * dig))

func _update_shader() -> void:
	var chambers: Array[Vector4] = []
	var tunnels: Array[Vector4] = []
	var lumps: Array[Vector4] = []
	var entrance := Vector2(size.x * 0.5, size.y * SURFACE - 4.0)
	for k in CHAMBERS.size():
		if k >= nest.chambers:
			chambers.append(Vector4.ZERO)
			continue
		var r := _chamber_rect(k)
		chambers.append(Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		# The tunnel grows toward the new chamber while it's being dug.
		var from := entrance if TUNNEL_FROM[k] < 0 else _chamber_rect(TUNNEL_FROM[k]).position
		var to := from.lerp(r.position, minf(1.0, _dig[k] * 1.5))
		tunnels.append(Vector4(from.x, from.y, to.x, to.y))
		# Garden: this chamber's share of the fungus, in lump slots.
		var fill := clampf((_shown_fungus - k * nest.chamber_capacity) / nest.chamber_capacity, 0.0, 1.0) * _dig[k]
		for j in LUMPS_PER_CHAMBER:
			var grow := clampf(fill * LUMPS_PER_CHAMBER - j, 0.0, 1.0)
			if grow <= 0.0:
				break
			var s := _slots[j]
			var at := r.position + Vector2(s.x * r.size.x, s.y * r.size.y)
			lumps.append(Vector4(at.x, at.y, s.z * r.size.y * sqrt(grow), 0.0))
	_mat.set_shader_parameter("view_size", size)
	_mat.set_shader_parameter("surface_y", size.y * SURFACE)
	_mat.set_shader_parameter("mound_height", size.y * (0.03 + 0.008 * nest.chambers))
	_mat.set_shader_parameter("chambers", chambers)
	_mat.set_shader_parameter("chamber_count", chambers.size())
	_mat.set_shader_parameter("tunnels", tunnels)
	_mat.set_shader_parameter("tunnel_count", tunnels.size())
	_mat.set_shader_parameter("tunnel_width", maxf(5.0, size.x * 0.016))
	_mat.set_shader_parameter("lumps", lumps)
	_mat.set_shader_parameter("lump_count", lumps.size())
	var total := nest.fungus + nest.substrate
	_mat.set_shader_parameter("fresh", nest.substrate / total if total > 0.0 else 0.0)

func _draw_overlay() -> void:
	# Tiny ants walking the tunnels, back and forth; more for a bigger colony.
	var colony := sim.colonies[nest.colony_id]
	var count := clampi(int(colony.population / 60.0), 2, 16)
	var entrance := Vector2(size.x * 0.5, size.y * SURFACE - 4.0)
	var ant_len := maxf(3.0, size.x * 0.012)
	for n in count:
		var k := n % nest.chambers
		if _dig[k] < 1.0:
			continue
		var from := entrance if TUNNEL_FROM[k] < 0 else _chamber_rect(TUNNEL_FROM[k]).position
		var to := _chamber_rect(k).position
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
