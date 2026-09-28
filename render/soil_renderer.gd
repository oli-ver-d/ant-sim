class_name SoilRenderer
extends Sprite2D
## Draws an underground layer's soil and dug space with soil.gdshader. The
## layer's cells are uploaded as a mask, one texel per cell:
##   R  soil or stone (1) or dug (0)
##   G  work left in a soil cell, as a share of a full cell (the digging face)
##   B  soil kind (World.Soil: plain 0, clay 1/3, root 2/3, stone 1)
##   A  how fresh a dug cell is: 1 when just dug, fading to 0 over FRESH_SECONDS
## Digging updates just the cells it touched (World.dig_log), and fresh cells
## are re-aged every AGE_EVERY seconds until they are old, so a growing nest
## costs a few pixels per frame, not a full rebuild. Any other change to the
## world rebuilds the whole mask.
##
## With the layer counting traffic (SimLayer.traffic) its map goes to the
## shader too (a float texture, re-uploaded every TRAFFIC_EVERY frames): busy
## floors are worn smooth and dark (see soil.gdshader).
##
## A nest on this layer with nurseries (ColonyNest.nursery) gets their floors
## marked in a second mask, one texel per cell (R eggs, G larvae, B pupae),
## rebuilt when the nest's nursery_version changes: the shader lines each
## nursery's floor with its own tone.

## Simulated seconds for a dug cell's floor to dry and darken fully.
const FRESH_SECONDS := 1200.0
const AGE_EVERY := 1.0
const TRAFFIC_EVERY := 10
## Traffic (ant-seconds in a cell) at which a floor is about 63% worn.
const WEAR_TRAFFIC := 6.0

var world: World
var sim: Simulation
var layer: SimLayer
var _image: Image
var _log_read: int = 0
var _edit_version: int = -1
## Dug cells still drying, and when each was dug (simulated seconds).
var _fresh: PackedInt32Array = []
var _dug_at: Dictionary[int, float] = {}
var _aged_at: float = -INF
var _traffic_image: Image
var _traffic_frame: int = 0
## Nests with brood care on this layer, and their nurseries' versions as uploaded.
var _nests: Array[ColonyNest] = []
var _nursery_versions: PackedInt32Array = []

## `on_layer` and `simulation` (optional) give dig times and traffic.
func bind(target_world: World, ground_seed: float = 0.0, simulation: Simulation = null, on_layer: SimLayer = null) -> void:
	world = target_world
	sim = simulation
	layer = on_layer
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scale = Vector2(world.cell_size, world.cell_size)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/soil.gdshader")
	mat.set_shader_parameter("world_size", Vector2(world.size))
	mat.set_shader_parameter("seed", ground_seed)
	material = mat
	if sim != null and layer != null:
		for colony in sim.colonies:
			var nest := colony.nest as ColonyNest
			if nest != null and nest.chambers_layout != null and nest.underground_layer >= 0 \
					and sim.layers[nest.underground_layer] == layer:
				_nests.append(nest)
				_nursery_versions.append(-1)
	_rebuild()

func _process(_delta: float) -> void:
	if world == null:
		return
	_update_traffic()
	_update_nurseries()
	if world.edit_version != _edit_version:
		_rebuild()
		return
	var changed := false
	var now := sim.time() if sim != null else 0.0
	var log := world.dig_log
	if _log_read != log.size():
		for k in range(_log_read, log.size()):
			var cell := log[k]
			if world.obstacles[cell] == World.Cell.FREE and not _dug_at.has(cell):
				_dug_at[cell] = now
				_fresh.append(cell)
			@warning_ignore("integer_division")
			_image.set_pixel(cell % world.width, cell / world.width, _texel(cell, now))
		_log_read = log.size()
		changed = true
	# Fresh floors dry and darken.
	if now - _aged_at >= AGE_EVERY and not _fresh.is_empty():
		_aged_at = now
		var keep: PackedInt32Array = []
		for cell in _fresh:
			@warning_ignore("integer_division")
			_image.set_pixel(cell % world.width, cell / world.width, _texel(cell, now))
			if now - _dug_at[cell] < FRESH_SECONDS:
				keep.append(cell)
		_fresh = keep
		changed = true
	if changed:
		(texture as ImageTexture).update(_image)

func _rebuild() -> void:
	_edit_version = world.edit_version
	_log_read = world.dig_log.size()
	var now := sim.time() if sim != null else 0.0
	var bytes := PackedByteArray()
	bytes.resize(world.obstacles.size() * 4)
	for i in world.obstacles.size():
		var c := _texel(i, now)
		bytes[i * 4] = int(c.r * 255.0)
		bytes[i * 4 + 1] = int(c.g * 255.0)
		bytes[i * 4 + 2] = int(c.b * 255.0)
		bytes[i * 4 + 3] = int(c.a * 255.0)
	_image = Image.create_from_data(world.width, world.height, false, Image.FORMAT_RGBA8, bytes)
	texture = ImageTexture.create_from_image(_image)

func _texel(cell: int, now: float) -> Color:
	var kind := float(world.soil_kind[cell]) / 3.0 if not world.soil_kind.is_empty() else 0.0
	if world.obstacles[cell] == World.Cell.FREE:
		var fresh := 0.0
		if _dug_at.has(cell):
			fresh = clampf(1.0 - (now - _dug_at[cell]) / FRESH_SECONDS, 0.0, 1.0)
		return Color(0.0, 0.0, kind, fresh)
	var left := clampf(world.soil_left(cell) / world.soil_hardness, 0.0, 1.0) if world.obstacles[cell] == World.Cell.SOIL else 1.0
	return Color(1.0, left, kind, 0.0)

## Marks the nurseries' floors (R eggs, G larvae, B pupae) when they change.
func _update_nurseries() -> void:
	var changed := false
	for n in _nests.size():
		if _nests[n].nursery_version != _nursery_versions[n]:
			_nursery_versions[n] = _nests[n].nursery_version
			changed = true
	if not changed:
		return
	var img := Image.create(world.width, world.height, false, Image.FORMAT_RGBA8)
	var any := false
	for nest in _nests:
		if not nest.has_nurseries():
			continue
		for s in 3:
			var col := Color(1, 0, 0, 1) if s == 0 else (Color(0, 1, 0, 1) if s == 1 else Color(0, 0, 1, 1))
			for cell in nest.chambers_layout.list[nest.nursery[s]].cells:
				@warning_ignore("integer_division")
				img.set_pixel(cell % world.width, cell / world.width, col)
				any = true
	var mat := material as ShaderMaterial
	mat.set_shader_parameter("nursery", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("has_nursery", any)

## Uploads the layer's traffic map (raw floats; the shader scales them).
func _update_traffic() -> void:
	if layer == null or layer.traffic == null:
		return
	_traffic_frame -= 1
	if _traffic_frame > 0:
		return
	_traffic_frame = TRAFFIC_EVERY
	var tm := layer.traffic
	var bytes := tm.values.to_byte_array()
	var mat := material as ShaderMaterial
	if _traffic_image == null:
		_traffic_image = Image.create_from_data(tm.width, tm.height, false, Image.FORMAT_RF, bytes)
		mat.set_shader_parameter("traffic", ImageTexture.create_from_image(_traffic_image))
		mat.set_shader_parameter("has_traffic", true)
	else:
		_traffic_image.set_data(tm.width, tm.height, false, Image.FORMAT_RF, bytes)
		(mat.get_shader_parameter("traffic") as ImageTexture).update(_traffic_image)
	mat.set_shader_parameter("traffic_scale", tm.scale / WEAR_TRAFFIC)
