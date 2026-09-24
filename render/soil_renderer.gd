class_name SoilRenderer
extends Sprite2D
## Draws an underground layer's soil and dug space with soil.gdshader. The
## layer's cells are uploaded as a two-channel mask (R soil, G work left in
## the cell); digging updates just the cells it touched (World.dig_log), so
## a growing nest costs a few pixels per frame, not a full rebuild. Any other
## change to the world rebuilds the whole mask.

var world: World
var _image: Image
var _log_read: int = 0
var _edit_version: int = -1

func bind(target_world: World, ground_seed: float = 0.0) -> void:
	world = target_world
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scale = Vector2(world.cell_size, world.cell_size)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/soil.gdshader")
	mat.set_shader_parameter("world_size", Vector2(world.size))
	mat.set_shader_parameter("seed", ground_seed)
	material = mat
	_rebuild()

func _process(_delta: float) -> void:
	if world == null:
		return
	if world.edit_version != _edit_version:
		_rebuild()
		return
	var log := world.dig_log
	if _log_read == log.size():
		return
	for k in range(_log_read, log.size()):
		var cell := log[k]
		@warning_ignore("integer_division")
		_image.set_pixel(cell % world.width, cell / world.width, _texel(cell))
	_log_read = log.size()
	(texture as ImageTexture).update(_image)

func _rebuild() -> void:
	_edit_version = world.edit_version
	_log_read = world.dig_log.size()
	var bytes := PackedByteArray()
	bytes.resize(world.obstacles.size() * 2)
	var has_soil := world.soil.size() == world.obstacles.size()
	for i in world.obstacles.size():
		if world.obstacles[i] != World.Cell.FREE:
			bytes[i * 2] = 255
			bytes[i * 2 + 1] = int(clampf(world.soil[i] / world.soil_hardness, 0.0, 1.0) * 255.0) if has_soil else 255
	_image = Image.create_from_data(world.width, world.height, false, Image.FORMAT_RG8, bytes)
	texture = ImageTexture.create_from_image(_image)

func _texel(cell: int) -> Color:
	if world.obstacles[cell] == World.Cell.FREE:
		return Color(0, 0, 0)
	return Color(1.0, clampf(world.soil_left(cell) / world.soil_hardness, 0.0, 1.0), 0.0)
