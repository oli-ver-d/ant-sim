class_name ObstacleRenderer
extends Sprite2D
## Draws the obstacle grid (walls, water) with obstacle.gdshader. The grid is
## uploaded as a two-channel mask texture (R wall, G water), rebuilt when the
## world's version changes. Cells under a bridge keep their water (or wall)
## look; BridgeRenderer draws the bridge on top.

var sim: Simulation
var _version: int = -1

func bind(simulation: Simulation) -> void:
	sim = simulation
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scale = Vector2(sim.world.cell_size, sim.world.cell_size)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/obstacle.gdshader")
	mat.set_shader_parameter("world_size", Vector2(sim.world.size))
	material = mat

func _process(_delta: float) -> void:
	if sim == null or sim.world.version == _version:
		return
	_version = sim.world.version
	var world := sim.world
	var bytes := PackedByteArray()
	bytes.resize(world.obstacles.size() * 2)
	for i in world.obstacles.size():
		var kind := world.obstacles[i]
		if kind == World.Cell.FREE:
			kind = world.bridged.get(i, kind)
		if kind == World.Cell.WALL:
			bytes[i * 2] = 255
		elif kind == World.Cell.WATER:
			bytes[i * 2 + 1] = 255
	texture = ImageTexture.create_from_image(Image.create_from_data(world.width, world.height, false, Image.FORMAT_RG8, bytes))
