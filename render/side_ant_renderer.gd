class_name SideAntRenderer
extends MultiMeshInstance2D
## Draws ants seen from the side (cutaway views) with side_ant.gdshader, one
## MultiMesh instance each. The owner rebuilds the list every frame:
## clear(), add() per ant, then commit().
##
## Each ant is placed by where its feet touch the ground, the direction it
## faces and which way the ground is; the body is tilted to that direction
## and mirrored as needed so the legs are on the ground side, so ants can walk
## along chamber floors, up tunnels and around walls and ceilings.

## Floats per instance: Transform2D (8) + color (4) + custom data (4).
const STRIDE := 16
## Must match QUAD and FOOT in side_ant.gdshader.
const QUAD := 2.0
const FOOT := 0.17

var _buffer: PackedFloat32Array = []
var _count: int = 0

func _init() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = AntRenderer._unit_quad()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/side_ant.gdshader")
	material = mat

func clear() -> void:
	_count = 0

## Adds an ant standing at `feet`, `length` pixels long, facing `dir` (any
## length), with its legs toward `ground` (e.g. Vector2.DOWN on a floor, the
## outward normal on a wall). look: head, thorax, gaster length and
## gaster height scales (1 = a worker). fold: 0 walking, 1 legs and antennae
## tucked like a pupa. phase: walk cycle in radians. color.a is the mandible size.
func add(feet: Vector2, length: float, dir: Vector2, ground: Vector2, color: Color, look: Vector4,
		fold: float, phase: float) -> void:
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector2.RIGHT
	var down := down_for(d, ground)
	var s := length * QUAD
	var x := d * s
	var y := down * s
	var at := feet - down * FOOT * length
	if (_count + 1) * STRIDE > _buffer.size():
		_buffer.resize(maxi(64, (_count + 1) * 2) * STRIDE)
	var o := _count * STRIDE
	# Transform2D rows: [x.x, y.x, 0, origin.x], [x.y, y.y, 0, origin.y]
	_buffer[o] = x.x
	_buffer[o + 1] = y.x
	_buffer[o + 2] = 0.0
	_buffer[o + 3] = at.x
	_buffer[o + 4] = x.y
	_buffer[o + 5] = y.y
	_buffer[o + 6] = 0.0
	_buffer[o + 7] = at.y
	_buffer[o + 8] = color.r
	_buffer[o + 9] = color.g
	_buffer[o + 10] = color.b
	_buffer[o + 11] = color.a
	_buffer[o + 12] = floorf(look.x * 100.0) + clampf(look.y * 0.5, 0.0, 1.0) * 0.99
	_buffer[o + 13] = look.z
	_buffer[o + 14] = floorf(look.w * 100.0) + clampf(fold, 0.0, 1.0) * 0.99
	_buffer[o + 15] = fposmod(phase, TAU) / TAU * 0.999
	_count += 1

## The side of `dir` (a unit vector) the legs go on: the perpendicular
## closest to `ground`.
static func down_for(dir: Vector2, ground: Vector2) -> Vector2:
	var perp := Vector2(-dir.y, dir.x)
	return perp if perp.dot(ground) >= 0.0 else -perp

func commit() -> void:
	if _count > multimesh.instance_count:
		# Changing instance_count discards the old buffer, so grow in chunks.
		multimesh.instance_count = _buffer.size() / STRIDE
	multimesh.visible_instance_count = _count
	if multimesh.instance_count > 0:
		multimesh.buffer = _buffer.slice(0, multimesh.instance_count * STRIDE)
