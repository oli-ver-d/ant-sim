class_name TrafficMap
extends RefCounted
## How busy each cell of a layer is: a decaying count of the ant-seconds
## spent there (SimLayer.traffic, enabled per layer by whoever needs it, e.g.
## a nest that widens its busy tunnels, see Highways; renderers may read it).
##
## Every SAMPLE_EVERY ticks each agent on the layer adds SAMPLE_EVERY * dt to
## its cell (Simulation.end_step), and every value halves every `half_life`
## seconds. Decay is lazy, as in PheromoneField: values are stored divided by
## `scale`, which shrinks each tick, and renormalised now and then; so a
## decay costs nothing per cell. A steady stream of ants through a cell
## settles at (ant-seconds per second in the cell) * half_life / ln 2.

const SAMPLE_EVERY := 3

var width: int
var height: int
var cell_size: int
var inv_cell: float
## Stored values; the real value of a cell is values[c] * scale.
var values: PackedFloat32Array = []
var scale: float = 1.0
var half_life: float = 60.0
## Incremented whenever values change (renderers re-upload).
var version: int = 0
var _decay: float = 1.0

func _init(world: World, half_life_seconds: float, dt: float) -> void:
	width = world.width
	height = world.height
	cell_size = world.cell_size
	inv_cell = world.inv_cell
	values.resize(width * height)
	half_life = half_life_seconds
	_decay = pow(0.5, dt / half_life)

## Real traffic in cell c.
func at_cell(c: int) -> float:
	return values[c] * scale

## Real traffic at a point (0 outside the layer).
func at(pos: Vector2) -> float:
	if pos.x < 0.0 or pos.y < 0.0:
		return 0.0
	var cx := int(pos.x * inv_cell)
	var cy := int(pos.y * inv_cell)
	if cx >= width or cy >= height:
		return 0.0
	return values[cy * width + cx] * scale

## Sum of the traffic over the cells within `radius` of the segment a-b.
func sum_along(a: Vector2, b: Vector2, radius: float) -> float:
	var total := 0.0
	var r2 := radius * radius
	var x0 := maxi(0, int((minf(a.x, b.x) - radius) * inv_cell))
	var x1 := mini(width - 1, int((maxf(a.x, b.x) + radius) * inv_cell))
	var y0 := maxi(0, int((minf(a.y, b.y) - radius) * inv_cell))
	var y1 := mini(height - 1, int((maxf(a.y, b.y) + radius) * inv_cell))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var c := Vector2((cx + 0.5) * cell_size, (cy + 0.5) * cell_size)
			if Geometry2D.get_closest_point_to_segment(c, a, b).distance_squared_to(c) <= r2:
				total += values[cy * width + cx]
	return total * scale

## One tick of decay (lazy).
func decay() -> void:
	scale *= _decay
	if scale < 1e-4:
		for c in values.size():
			values[c] *= scale
		scale = 1.0

## The stored amount one sample of one ant adds (see Simulation.end_step).
func sample_add(dt: float) -> float:
	return SAMPLE_EVERY * dt / scale

## Sum of the traffic over the cells within `radius` of a polyline, each
## cell counted once.
func sum_path(points: PackedVector2Array, radius: float) -> float:
	var seen: Dictionary[int, bool] = {}
	var total := 0.0
	var r2 := radius * radius
	for k in points.size() - 1:
		var a := points[k]
		var b := points[k + 1]
		var x0 := maxi(0, int((minf(a.x, b.x) - radius) * inv_cell))
		var x1 := mini(width - 1, int((maxf(a.x, b.x) + radius) * inv_cell))
		var y0 := maxi(0, int((minf(a.y, b.y) - radius) * inv_cell))
		var y1 := mini(height - 1, int((maxf(a.y, b.y) + radius) * inv_cell))
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				var c := cy * width + cx
				if seen.has(c):
					continue
				var at := Vector2((cx + 0.5) * cell_size, (cy + 0.5) * cell_size)
				if Geometry2D.get_closest_point_to_segment(at, a, b).distance_squared_to(at) <= r2:
					seen[c] = true
					total += values[c]
	return total * scale
