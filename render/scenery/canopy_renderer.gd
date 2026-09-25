class_name CanopyRenderer
extends Node2D
## Draws the plants' canopies over the ants: every blade of every plant
## (PlantProp's detail "blades") in one static mesh, shaded by canopy.gdshader
## (veins, fold, light through the thin edges, alpha thinning to the tips,
## slow per-blade sway), with their shadow drawn first as a second mesh, cast
## away from the light as far as each part of a blade is high, so the canopy
## darkens the ground and the ants under it.
##
## Readability: the canopy and its shadow fade out round nest entrances, food
## sources and the ant the camera follows (clear spots, a uniform array).
## Wind picks up while it rains.

## Sway amplitude (world units at the plant's reach) per plant kind.
const FLEX := {"grass": 1.8, "fern": 1.4, "clover": 0.9, "rosette": 0.45, "seedling": 0.35}
## Shadow blades are this much wider (plus SHADOW_PAD) and drawn soft.
const SHADOW_WIDEN := 1.3
const SHADOW_PAD := 1.2
## Blades are drawn this far past their edge so the shader can anti-alias them.
const PAD := 0.7
## Shadow cast per unit of height (as PropBaker's shadows).
const CAST := 0.75
const MAX_SPOTS := 16
## Clear radius round an entrance (plus the nest's radius), a food source and the followed ant.
const ENTRANCE_CLEAR := 22.0
const FOOD_CLEAR := 45.0
const FOLLOW_CLEAR := 30.0
## Extra wind strength at full rain.
const RAIN_GUST := 1.6

const SHADER := preload("res://render/scenery/canopy.gdshader")

var sim: Simulation
var _version: int = -1
var _shadow := MeshInstance2D.new()
var _blades := MeshInstance2D.new()
var _wind: float = 1.0

func bind(simulation: Simulation) -> void:
	sim = simulation
	var mottle := ImageTexture.create_from_image(_mottle_image())
	for mi: MeshInstance2D in [_shadow, _blades]:
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("shadow_pass", mi == _shadow)
		mat.set_shader_parameter("mottle", mottle)
		mat.set_shader_parameter("light_dir", PropBaker.LIGHT_DIR)
		mi.material = mat
		add_child(mi)

func _process(delta: float) -> void:
	if sim == null:
		return
	if sim.scenery.version != _version:
		_version = sim.scenery.version
		_shadow.mesh = build_mesh(sim.scenery.props, true)
		_blades.mesh = build_mesh(sim.scenery.props, false)
	if _blades.mesh == null:
		return
	var follow := -1
	var cam := get_viewport().get_camera_2d()
	if cam != null and "follow_ant" in cam:
		follow = int(cam.get("follow_ant"))
	var spots := clear_spots(sim, follow)
	# Wind strengthens smoothly while it rains.
	_wind = lerpf(_wind, 1.0 + RAIN_GUST * _rain_now(), clampf(delta * 0.8, 0.0, 1.0))
	for mi: MeshInstance2D in [_shadow, _blades]:
		var mat := mi.material as ShaderMaterial
		mat.set_shader_parameter("clear_spots", spots)
		mat.set_shader_parameter("clear_count", spots.size())
		mat.set_shader_parameter("wind", _wind)

## Places the canopy is kept thin over, as (x, y, radius, 0): the followed ant
## first, then nest entrances, then food sources, at most MAX_SPOTS.
static func clear_spots(simulation: Simulation, follow_ant: int = -1) -> PackedVector4Array:
	var out := PackedVector4Array()
	if follow_ant >= 0 and follow_ant < simulation.alive.size() and simulation.alive[follow_ant] != 0 \
			and simulation.layer[follow_ant] == 0:
		var at := simulation.shown_pos[follow_ant]
		out.append(Vector4(at.x, at.y, FOLLOW_CLEAR, 0.0))
	for colony in simulation.colonies:
		var nest := colony.nest
		var r := nest.radius + ENTRANCE_CLEAR
		var ents := nest.entrances()
		if ents.is_empty():
			ents = PackedVector2Array([nest.position])
		for e in ents:
			if out.size() < MAX_SPOTS:
				out.append(Vector4(e.x, e.y, r, 0.0))
	for src in simulation.food_sources:
		if out.size() < MAX_SPOTS and not src.is_depleted():
			out.append(Vector4(src.position.x, src.position.y, FOOD_CLEAR, 0.0))
	return out

## Strength of the rain now (0..1), the strongest shower's.
func _rain_now() -> float:
	var now := sim.time()
	var most := 0.0
	for shower in sim.rain:
		var start := float(shower["start"])
		var until := float(shower["until"])
		most = maxf(most, clampf(now - start, 0.0, 1.0) * clampf(1.0 - (now - until) / 1.5, 0.0, 1.0))
	return most

## One mesh of every plant's blades, in the order they are listed (lowest
## first), or null if there are none. `shadow`: the blades' shadow on the
## ground instead (each point shifted away from the light by its height).
## Per vertex: UV (across -1..1 at the blade's edge, along 0..1), COLOR tint,
## CUSTOM0 (plant centre, sway phase, sway per unit distance squared),
## CUSTOM1 (style, teeth, blade length, which side faces the light).
static func build_mesh(props: Array[Prop], shadow: bool) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()
	var light := PropBaker.LIGHT_DIR.normalized()
	var cast := -light * CAST
	for prop in props:
		if not prop.detail.has("blades"):
			continue
		var reach := maxf(float(prop.detail.get("reach", 40.0)), 1.0)
		var sway := float(FLEX.get(str(prop.detail.get("kind", "")), 1.0)) / (reach * reach)
		for b: Dictionary in prop.detail["blades"]:
			var pts: PackedVector2Array = b["points"]
			var widths: PackedFloat32Array = b["widths"]
			var heights: PackedFloat32Array = b["heights"]
			var n := pts.size()
			if n < 2:
				continue
			var length := 0.0
			for k in n - 1:
				length += pts[k].distance_to(pts[k + 1])
			var tint: Color = b["tint"]
			var first := verts.size() / 2
			for k in n:
				var d := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)]).normalized()
				var nrm := d.orthogonal()
				var hw := widths[k] * 0.5
				var drawn := hw * SHADOW_WIDEN + SHADOW_PAD if shadow else hw + PAD
				var u := drawn / maxf(hw, 0.15)
				var shift := cast * heights[k] if shadow else Vector2.ZERO
				var t := float(k) / (n - 1)
				for s: float in [1.0, -1.0]:
					verts.append(pts[k] + nrm * drawn * s + shift)
					uvs.append(Vector2(u * s, t))
					colors.append(tint)
					c0.append_array([prop.position.x + shift.x, prop.position.y + shift.y, float(b["phase"]), sway])
					c1.append_array([float(b["style"]), float(b["teeth"]), length, nrm.dot(light)])
			for k in n - 1:
				var i := (first + k) * 2
				idx.append_array([i, i + 1, i + 2, i + 1, i + 3, i + 2])
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = c0
	arrays[Mesh.ARRAY_CUSTOM1] = c1
	arrays[Mesh.ARRAY_INDEX] = idx
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	return mesh

## Tileable soft noise for blotches on the blades.
static func _mottle_image() -> Image:
	var nz := FastNoiseLite.new()
	nz.seed = 4242
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 1.0 / 16.0
	nz.fractal_octaves = 3
	var img := nz.get_seamless_image(128, 128)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	return img
