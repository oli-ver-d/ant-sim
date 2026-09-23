class_name LeafRenderer
extends Node2D
## Draws a LeafSource with leaf.gdshader: the cell mask is uploaded as a small
## two-channel texture (only when a bite changes it) and the shader turns it
## into a smooth, veined leaf. A second pass with the same mask draws the
## drop shadow. Hidden once fully consumed.

const SHADOW_OFFSET := Vector2(3, 4)

var leaf: LeafSource
var _mask_image: Image
var _mask_texture: ImageTexture
var _leaf_material: ShaderMaterial
var _shadow_material: ShaderMaterial
var _version: int = -1

func bind(_sim: Simulation, target: Object) -> void:
	leaf = target as LeafSource
	position = leaf.position
	rotation = leaf.rotation
	_mask_image = Image.create_from_data(leaf.nx, leaf.ny, false, Image.FORMAT_RG8, leaf.mask_rg)
	_mask_texture = ImageTexture.create_from_image(_mask_image)

	var shader := preload("res://species/leafcutter/leaf.gdshader")
	_leaf_material = ShaderMaterial.new()
	_leaf_material.shader = shader
	_leaf_material.set_shader_parameter("origin", leaf.origin)
	_leaf_material.set_shader_parameter("size", Vector2(leaf.nx, leaf.ny) * LeafSource.CELL)
	_leaf_material.set_shader_parameter("leaf_length", leaf.length)
	_leaf_material.set_shader_parameter("leaf_width", leaf.width)
	_leaf_material.set_shader_parameter("cell", float(LeafSource.CELL))
	_leaf_material.set_shader_parameter("vein_count", float(leaf.vein_count))
	_leaf_material.set_shader_parameter("vein_dir", leaf.vein_dir)
	_leaf_material.set_shader_parameter("seed", leaf.noise_seed)
	_leaf_material.set_shader_parameter("base_color", LeafSource.BASE)
	_leaf_material.set_shader_parameter("vein_color", LeafSource.VEIN)
	_leaf_material.set_shader_parameter("stem_color", LeafSource.STEM_COLOR)
	_shadow_material = _leaf_material.duplicate()
	_shadow_material.set_shader_parameter("shadow", true)

	# Two child canvas items so each pass has its own material.
	add_child(_pass(_shadow_material, SHADOW_OFFSET.rotated(-leaf.rotation)))
	add_child(_pass(_leaf_material, Vector2.ZERO))

func _pass(mat: ShaderMaterial, offset: Vector2) -> Node2D:
	var sprite := Sprite2D.new()
	sprite.texture = _mask_texture
	sprite.centered = false
	sprite.position = leaf.origin + offset
	sprite.scale = Vector2(LeafSource.CELL, LeafSource.CELL)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.material = mat
	return sprite

func _process(_delta: float) -> void:
	if leaf.version == _version:
		return
	_version = leaf.version
	visible = not leaf.is_depleted()
	_mask_image.set_data(leaf.nx, leaf.ny, false, Image.FORMAT_RG8, leaf.mask_rg)
	_mask_texture.update(_mask_image)
