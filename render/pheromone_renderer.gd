class_name PheromoneRenderer
extends Node2D
## Overlay for every pheromone channel: one float texture per channel,
## uploaded from the simulation each frame and coloured by pheromone.gdshader
## using the channel's colour. Linear filtering softens the 4 px cells.

## Real value that maps to ~63% glow.
@export var exposure_value: float = 0.9
@export var opacity: float = 0.55:
	set(v):
		opacity = v
		for s in _sprites:
			(s.material as ShaderMaterial).set_shader_parameter("opacity", v)

var sim: Simulation
## Layer whose pheromones are drawn.
var layer: int = 0
var _sprites: Array[Sprite2D] = []
var _images: Array[Image] = []

func bind(simulation: Simulation) -> void:
	sim = simulation

func _process(_delta: float) -> void:
	if sim == null or not visible:
		return
	var field := sim.layers[layer].pheromones
	while _sprites.size() < field.channel_count():
		_add_sprite(_sprites.size())
	for c in field.channel_count():
		var off := c * field.cell_count
		var bytes := field.values.slice(off, off + field.cell_count).to_byte_array()
		_images[c].set_data(field.width, field.height, false, Image.FORMAT_RF, bytes)
		(_sprites[c].texture as ImageTexture).update(_images[c])
		(_sprites[c].material as ShaderMaterial).set_shader_parameter("gain", field.scale[c] * field.render_intensity[c] / exposure_value)

func _add_sprite(c: int) -> void:
	var field := sim.layers[layer].pheromones
	var img := Image.create_empty(field.width, field.height, false, Image.FORMAT_RF)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.centered = false
	sprite.scale = Vector2(field.cell_size, field.cell_size)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/pheromone.gdshader")
	mat.set_shader_parameter("tint", field.colors[c])
	mat.set_shader_parameter("opacity", opacity)
	sprite.material = mat
	add_child(sprite)
	_sprites.append(sprite)
	_images.append(img)
