class_name ObstacleRenderer
extends Sprite2D
## Draws the obstacle grid (walls, water) with obstacle.gdshader. The grid is
## uploaded as a three-channel mask texture (R wall, G water, B scenery prop),
## rebuilt when the world's version changes. Cells under a bridge keep their
## water (or wall) look; BridgeRenderer draws the bridge on top. Cells blocked
## by a scenery prop are not drawn as stone (R stays 0): SceneryRenderer draws
## the prop there.

var sim: Simulation
## Layer whose obstacles are drawn.
var layer: int = 0
var _version: int = -1

func bind(simulation: Simulation) -> void:
	sim = simulation
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scale = Vector2(sim.layers[layer].world.cell_size, sim.layers[layer].world.cell_size)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/obstacle.gdshader")
	mat.set_shader_parameter("world_size", Vector2(sim.layers[layer].world.size))
	material = mat

func _process(_delta: float) -> void:
	if sim == null or sim.layers[layer].world.version == _version:
		return
	_version = sim.layers[layer].world.version
	var world := sim.layers[layer].world
	texture = ImageTexture.create_from_image(Image.create_from_data(world.width, world.height, false, Image.FORMAT_RGB8, mask_bytes(world)))

## The RGB8 mask for a world: R wall, G water, B scenery prop (one texel per cell).
static func mask_bytes(world: World) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(world.obstacles.size() * 3)
	var props := not world.prop_mask.is_empty()
	for i in world.obstacles.size():
		var kind := world.obstacles[i]
		if kind == World.Cell.FREE:
			kind = world.bridged.get(i, kind)
		if props and world.prop_mask[i] > 0:
			bytes[i * 3 + 2] = 255
		elif kind == World.Cell.WALL:
			bytes[i * 3] = 255
		elif kind == World.Cell.WATER:
			bytes[i * 3 + 1] = 255
	return bytes
