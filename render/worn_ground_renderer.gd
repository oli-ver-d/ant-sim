class_name WornGroundRenderer
extends Sprite2D
## Ground worn by the ants walking over it: the surface's TrafficMap (which
## this turns on, SimLayer.enable_traffic; render use only, it is not hashed
## and draws no random numbers) drawn as packed, darker soil: an apron round
## each entrance and faint paths out along the busiest routes. The map is
## uploaded as a float texture, one texel per cell, every UPLOAD_EVERY
## frames; worn_ground.gdshader smooths it and multiplies the ground below,
## so the ground keeps its own colour and grain.

const UPLOAD_EVERY := 10
## Half-life of the surface traffic when this view turns it on (a nest with
## highways turns it on first, with its own).
const HALF_LIFE := 240.0
## Traffic (ant-seconds in a cell) at which ground is about 63% worn.
const WEAR_TRAFFIC := 30.0

var layer: SimLayer
var _image: Image
var _frame: int = 0

func bind(sim: Simulation) -> void:
	layer = sim.layers[0]
	layer.enable_traffic(HALF_LIFE, sim.dt)
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scale = Vector2.ONE * layer.world.cell_size
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/worn_ground.gdshader")
	material = mat

func _process(_delta: float) -> void:
	if layer == null:
		return
	_frame -= 1
	if _frame > 0:
		return
	_frame = UPLOAD_EVERY
	var tm := layer.traffic
	var bytes := tm.values.to_byte_array()
	if _image == null:
		_image = Image.create_from_data(tm.width, tm.height, false, Image.FORMAT_RF, bytes)
		texture = ImageTexture.create_from_image(_image)
	else:
		_image.set_data(tm.width, tm.height, false, Image.FORMAT_RF, bytes)
		(texture as ImageTexture).update(_image)
	(material as ShaderMaterial).set_shader_parameter("traffic_scale", tm.scale / WEAR_TRAFFIC)
