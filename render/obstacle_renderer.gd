class_name ObstacleRenderer
extends Sprite2D
## Draws the obstacle grid (walls, water) as a texture, rebuilt when the
## world's version changes.

const WALL_COLOR := Color(0.36, 0.3, 0.24)
const WATER_COLOR := Color(0.13, 0.28, 0.42)

var sim: Simulation
var _version: int = -1

func bind(simulation: Simulation) -> void:
	sim = simulation
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scale = Vector2(sim.world.cell_size, sim.world.cell_size)

func _process(_delta: float) -> void:
	if sim == null or sim.world.version == _version:
		return
	_version = sim.world.version
	var world := sim.world
	var img := Image.create_empty(world.width, world.height, false, Image.FORMAT_RGBA8)
	for i in world.obstacles.size():
		var kind := world.obstacles[i]
		if kind != World.Cell.FREE:
			@warning_ignore("integer_division")
			img.set_pixel(i % world.width, i / world.width, WATER_COLOR if kind == World.Cell.WATER else WALL_COLOR)
	texture = ImageTexture.create_from_image(img)
