class_name GardenRenderer
extends Sprite2D
## Draws a nest's GardenGrid with garden.gdshader: one texel per garden cell
## (R fungus, G fresh pulp, B spent/age/mould, A gongylidia). The texture is
## re-encoded a slice of garden cells per frame (every cell within a few
## frames) and uploaded when the grid has changed, so a big nest's gardens
## cost about the same per frame as a small one's.

## Garden cells re-encoded per frame.
const CELLS_PER_FRAME := 6000

var nest: FungusNest
var _image: Image
var _bytes: PackedByteArray = []
var _cursor: int = 0
var _seen_version: int = -1
var _seen_cells: int = 0

func bind(target: FungusNest) -> void:
	nest = target
	var g := nest.garden
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scale = Vector2(GardenGrid.CELL, GardenGrid.CELL)
	_bytes.resize(g.width * g.height * 4)
	_image = Image.create_from_data(g.width, g.height, false, Image.FORMAT_RGBA8, _bytes)
	texture = ImageTexture.create_from_image(_image)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://species/leafcutter/garden.gdshader")
	mat.set_shader_parameter("world_size", Vector2(g.width, g.height) * GardenGrid.CELL)
	material = mat

func _process(_delta: float) -> void:
	var g := nest.garden
	if g == null or g.version == _seen_version:
		return
	_seen_version = g.version
	var n := g.cells.size()
	if n == 0:
		return
	# New chambers are drawn in full at once; otherwise a slice per frame.
	var todo := CELLS_PER_FRAME
	if n != _seen_cells:
		todo = n
		_seen_cells = n
	var cap := g.cap
	var life := g.life
	for k in mini(todo, n):
		var c := g.cells[_cursor]
		_cursor = (_cursor + 1) % n
		var f := g.fungus[c] * g.fscale / cap
		var o := c * 4
		_bytes[o] = int(clampf(f / 1.5, 0.0, 1.0) * 255.0)
		_bytes[o + 1] = int(clampf(g.substrate[c] / (cap * 2.0), 0.0, 1.0) * 255.0)
		var brown := maxf(g.spent[c] / cap, maxf(g.age[c] / life - 0.5, 0.0) * 0.8)
		if g.sick[c] != 0:
			brown = 1.0
		_bytes[o + 2] = int(clampf(brown, 0.0, 1.0) * 255.0)
		_bytes[o + 3] = int(clampf(g.gong[c], 0.0, 1.0) * 255.0)
	_image.set_data(g.width, g.height, false, Image.FORMAT_RGBA8, _bytes)
	(texture as ImageTexture).update(_image)
