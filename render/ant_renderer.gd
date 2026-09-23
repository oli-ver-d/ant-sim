class_name AntRenderer
extends MultiMeshInstance2D
## Draws every ant as one MultiMesh instance. All look data (colour, size,
## body proportions) comes from the ant's CasteDef; the walk phase from the
## simulation. The instance buffer is rebuilt in one pass each frame.

## Floats per instance: Transform2D (8) + color (4) + custom data (4).
const STRIDE := 16
const QUAD_SCALE := 1.6

var sim: Simulation
## Fraction of the way from the previous tick to the current one (set by WorldView).
var alpha: float = 1.0
var _buffer: PackedFloat32Array = []
# Per [colony][caste] look data, flattened: index = colony_base[colony] + caste.
var _colony_base: PackedInt32Array = []
var _look_size: PackedFloat32Array = []
var _look_color: PackedColorArray = []
var _look_custom: PackedVector3Array = []

func bind(simulation: Simulation) -> void:
	sim = simulation
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/ant.gdshader")
	material = mat

func _cache_looks() -> void:
	_colony_base.clear()
	_look_size.clear()
	_look_color.clear()
	_look_custom.clear()
	for colony in sim.colonies:
		_colony_base.append(_look_size.size())
		for caste in colony.species.castes:
			_look_size.append(caste.size * QUAD_SCALE)
			_look_color.append(caste.color)
			_look_custom.append(Vector3(caste.head_scale, caste.thorax_scale, caste.abdomen_scale))

func _process(_delta: float) -> void:
	if sim == null:
		return
	if _colony_base.size() != sim.colonies.size():
		_cache_looks()
	var n := sim.high_water
	if n > multimesh.instance_count:
		# Grow in chunks; changing instance_count discards the old buffer.
		multimesh.instance_count = maxi(maxi(n, multimesh.instance_count * 2), 256)
		_buffer.resize(multimesh.instance_count * STRIDE)
		_buffer.fill(0.0)
	multimesh.visible_instance_count = n

	var alive := sim.alive
	var pos := sim.pos
	var prev_pos := sim.prev_pos
	var prev_heading := sim.prev_heading
	var a := alpha
	var heading := sim.heading
	var colony_id := sim.colony_id
	var caste_id := sim.caste_id
	var phase := sim.anim_phase
	var o := 0
	for i in n:
		if alive[i] == 0:
			# Zero-scale transform hides the slot.
			for k in 8:
				_buffer[o + k] = 0.0
			o += STRIDE
			continue
		var look := _colony_base[colony_id[i]] + caste_id[i]
		var s := _look_size[look]
		var h := lerp_angle(prev_heading[i], heading[i], a)
		var c := cos(h) * s
		var sn := sin(h) * s
		var p := prev_pos[i].lerp(pos[i], a)
		# Transform2D rows: [x.x, y.x, 0, origin.x], [x.y, y.y, 0, origin.y]
		_buffer[o] = c
		_buffer[o + 1] = -sn
		_buffer[o + 2] = 0.0
		_buffer[o + 3] = p.x
		_buffer[o + 4] = sn
		_buffer[o + 5] = c
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
		_buffer[o + 15] = phase[i]
		o += STRIDE
	multimesh.buffer = _buffer
