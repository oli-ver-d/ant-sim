class_name AntRenderer
extends MultiMeshInstance2D
## Draws every ant as one MultiMesh instance with ant.gdshader. All look data
## (colour, size, body proportions, leg length, mandibles) comes from the
## ant's CasteDef; heading and walk phase from the simulation (interpolated
## between the last two completed ticks). The instance buffer is rebuilt in
## one pass each frame.
##
## Instances are axis-aligned squares; the heading is packed into custom data
## so the shader can light and shadow in world space (see ant.gdshader for the
## packing).

## Floats per instance: Transform2D (8) + color (4) + custom data (4).
const STRIDE := 16
## Must match QUAD in ant.gdshader.
const QUAD_SCALE := 2.4
const HEADING_STEPS := 1023.0

var sim: Simulation
## Fraction of the way from the previous tick to the current one (set by WorldView).
var alpha: float = 1.0
## True for the layer that draws only ants riding on items (above the items).
var riders_only: bool = false
var _buffer: PackedFloat32Array = []
# Per [colony][caste] look data, flattened: index = colony_base[colony] + caste.
var _colony_base: PackedInt32Array = []
var _look_size: PackedFloat32Array = []
var _look_color: PackedColorArray = []
var _look_custom: PackedVector3Array = []

func bind(simulation: Simulation) -> void:
	sim = simulation
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _unit_quad()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/ant.gdshader")
	material = mat

## A 1x1 quad centred on the origin whose UVs run in the same direction as
## world axes (y down), so the shader can work in world orientation.
static func _unit_quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _cache_looks() -> void:
	_colony_base.clear()
	_look_size.clear()
	_look_color.clear()
	_look_custom.clear()
	for colony in sim.colonies:
		_colony_base.append(_look_size.size())
		for caste in colony.species.castes:
			_look_size.append(caste.size * QUAD_SCALE)
			var c := caste.color
			c.a = clampf(caste.mandible_size, 0.0, 1.0)
			_look_color.append(c)
			var packed := floorf(caste.thorax_scale * 100.0) + clampf(caste.leg_length / 4.0, 0.0, 0.999)
			_look_custom.append(Vector3(caste.head_scale, caste.abdomen_scale, packed))

func _process(_delta: float) -> void:
	if sim == null:
		return
	if _colony_base.size() != sim.colonies.size():
		_cache_looks()
	# The main layer draws every ant except riders; the rider layer (drawn
	# above carried items) draws only ants riding on items.
	var list: PackedInt32Array = _collect_riders() if riders_only else PackedInt32Array()
	var n := list.size() if riders_only else sim.high_water
	if n > multimesh.instance_count:
		# Grow in chunks; changing instance_count discards the old buffer.
		multimesh.instance_count = maxi(maxi(n, multimesh.instance_count * 2), 256)
		_buffer.resize(multimesh.instance_count * STRIDE)
		_buffer.fill(0.0)
	multimesh.visible_instance_count = n

	var alive := sim.alive
	var riding := sim.riding
	var pos := sim.shown_pos
	var prev_pos := sim.prev_pos
	var heading := sim.shown_heading
	var prev_heading := sim.prev_heading
	var colony_id := sim.colony_id
	var caste_id := sim.caste_id
	var phase := sim.anim_phase
	var a := alpha
	var o := 0
	for k in n:
		var i := list[k] if riders_only else k
		if alive[i] == 0 or (not riders_only and riding[i] >= 0):
			# Zero-scale transform hides the slot.
			_buffer[o] = 0.0
			_buffer[o + 5] = 0.0
			o += STRIDE
			continue
		var look := _colony_base[colony_id[i]] + caste_id[i]
		var s := _look_size[look]
		var p := prev_pos[i].lerp(pos[i], a)
		var h := lerp_angle(prev_heading[i], heading[i], a)
		# Transform2D rows: [x.x, y.x, 0, origin.x], [x.y, y.y, 0, origin.y]
		_buffer[o] = s
		_buffer[o + 1] = 0.0
		_buffer[o + 2] = 0.0
		_buffer[o + 3] = p.x
		_buffer[o + 4] = 0.0
		_buffer[o + 5] = s
		_buffer[o + 6] = 0.0
		_buffer[o + 7] = p.y
		var col := _look_color[look]
		_buffer[o + 8] = col.r
		_buffer[o + 9] = col.g
		_buffer[o + 10] = col.b
		_buffer[o + 11] = col.a
		var cu := _look_custom[look]
		_buffer[o + 12] = cu.x
		_buffer[o + 13] = cu.y
		_buffer[o + 14] = cu.z
		# Heading quantised to 1023 steps (0.35 deg) plus walk phase as the fraction.
		var hq := roundf((wrapf(h, -PI, PI) + PI) / TAU * HEADING_STEPS)
		_buffer[o + 15] = hq + fposmod(phase[i], TAU) / TAU * 0.999
		o += STRIDE
	multimesh.buffer = _buffer

func _collect_riders() -> PackedInt32Array:
	var out: PackedInt32Array = []
	for id: int in sim.items:
		out.append_array(sim.items[id].riders)
	return out
