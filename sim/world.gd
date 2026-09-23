class_name World
extends RefCounted
## Static environment: world bounds and the obstacle grid (walls, water).
## The grid uses the same cells as the PheromoneField.

enum Cell { FREE = 0, WALL = 1, WATER = 2 }

var size: Vector2i
var cell_size: int
var width: int
var height: int
var obstacles: PackedByteArray = []
## Incremented on every change so renderers and caches know to refresh.
var version: int = 0
## 1 for cells within `near_radius` of a blocked cell or the world edge.
## Steering only runs its (costly) obstacle probes on these cells.
var near_blocked: PackedByteArray = []
var near_radius: float = 0.0
var _near_version: int = -1
var inv_cell: float
var _inv_cell: float

func _init(world_size: Vector2i, cell: int) -> void:
	size = world_size
	cell_size = cell
	_inv_cell = 1.0 / cell
	inv_cell = _inv_cell
	@warning_ignore("integer_division")
	width = world_size.x / cell
	@warning_ignore("integer_division")
	height = world_size.y / cell
	obstacles.resize(width * height)
	clutter.resize(width * height)

## Flat cell index, or -1 outside the world.
func cell_at(pos: Vector2) -> int:
	if pos.x < 0.0 or pos.y < 0.0:
		return -1
	var cx := int(pos.x * _inv_cell)
	var cy := int(pos.y * _inv_cell)
	if cx >= width or cy >= height:
		return -1
	return cy * width + cx

## True outside the world or on a wall/water cell. Ants may never be here.
func is_blocked(pos: Vector2) -> bool:
	var cell := cell_at(pos)
	return cell < 0 or obstacles[cell] != Cell.FREE

## Rebuilds near_blocked if the obstacles changed. `radius` in world units.
## Dilates the blocked cells by a square of r cells using per-row then
## per-column prefix counts, so the cost is O(cells) regardless of radius.
func ensure_near_blocked(radius: float) -> void:
	if _near_version == version and is_equal_approx(radius, near_radius):
		return
	_near_version = version
	near_radius = radius
	var r := int(ceil(radius * _inv_cell)) + 1
	var horiz := PackedByteArray()
	horiz.resize(width * height)
	var prefix := PackedInt32Array()
	# Rows: horiz[x] = any blocked in [x - r, x + r] (outside the world counts as blocked).
	prefix.resize(width + 1)
	for y in height:
		var row := y * width
		for x in width:
			prefix[x + 1] = prefix[x] + (1 if obstacles[row + x] != Cell.FREE else 0)
		for x in width:
			var a := x - r
			var b := x + r
			if a < 0 or b >= width or prefix[b + 1] - prefix[a] > 0:
				horiz[row + x] = 1
	# Columns: near[y] = any horiz in [y - r, y + r].
	near_blocked.resize(width * height)
	prefix.resize(height + 1)
	for x in width:
		for y in height:
			prefix[y + 1] = prefix[y] + horiz[y * width + x]
		for y in height:
			var a := y - r
			var b := y + r
			near_blocked[y * width + x] = 1 if (a < 0 or b >= height or prefix[b + 1] - prefix[a] > 0) else 0

func cell_center(cell: int) -> Vector2:
	@warning_ignore("integer_division")
	return Vector2((cell % width + 0.5) * cell_size, (cell / width + 0.5) * cell_size)

## True if the straight segment a->b crosses no blocked cell (sampled every half cell).
func line_clear(a: Vector2, b: Vector2) -> bool:
	var steps := int(a.distance_to(b) / (cell_size * 0.5)) + 1
	for s in steps + 1:
		if is_blocked(a.lerp(b, float(s) / steps)):
			return false
	return true

func set_cell(cx: int, cy: int, kind: int) -> void:
	if cx >= 0 and cy >= 0 and cx < width and cy < height:
		obstacles[cy * width + cx] = kind

## Marks every cell whose centre is within `radius` of `center`.
func fill_circle(center: Vector2, radius: float, kind: int) -> void:
	var r2 := radius * radius
	var x0 := int((center.x - radius) * _inv_cell)
	var x1 := int((center.x + radius) * _inv_cell)
	var y0 := int((center.y - radius) * _inv_cell)
	var y1 := int((center.y + radius) * _inv_cell)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var c := Vector2((cx + 0.5) * cell_size, (cy + 0.5) * cell_size)
			if c.distance_squared_to(center) <= r2:
				set_cell(cx, cy, kind)
	version += 1

func fill_rect(rect: Rect2, kind: int) -> void:
	for cy in range(int(rect.position.y * _inv_cell), int(ceil(rect.end.y * _inv_cell))):
		for cx in range(int(rect.position.x * _inv_cell), int(ceil(rect.end.x * _inv_cell))):
			set_cell(cx, cy, kind)
	version += 1

## Fills the cells of a closed polygon.
func fill_polygon(points: PackedVector2Array, kind: int) -> void:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	for cy in range(int(bounds.position.y * _inv_cell), int(ceil(bounds.end.y * _inv_cell))):
		for cx in range(int(bounds.position.x * _inv_cell), int(ceil(bounds.end.x * _inv_cell))):
			if Geometry2D.is_point_in_polygon(Vector2((cx + 0.5) * cell_size, (cy + 0.5) * cell_size), points):
				set_cell(cx, cy, kind)
	version += 1

## Thick polyline (a wall drawn as connected segments with round joints).
func draw_polyline(points: PackedVector2Array, thickness: float, kind: int) -> void:
	var r := thickness * 0.5
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var steps := int(a.distance_to(b) / (cell_size * 0.5)) + 1
		for s in steps + 1:
			_stamp(a.lerp(b, float(s) / steps), r, kind)
	if points.size() == 1:
		_stamp(points[0], r, kind)
	version += 1

## Ground clutter (debris lying on the ground): number of clutter items
## covering each cell. Ants crossing cluttered cells are slowed.
var clutter: PackedByteArray = []

## Adds (delta = +1) or removes (-1) a clutter footprint.
func add_clutter(center: Vector2, radius: float, delta: int) -> void:
	if clutter.is_empty():
		clutter.resize(width * height)
	var r2 := radius * radius
	for cy in range(maxi(0, int((center.y - radius) * _inv_cell)), mini(height, int((center.y + radius) * _inv_cell) + 1)):
		for cx in range(maxi(0, int((center.x - radius) * _inv_cell)), mini(width, int((center.x + radius) * _inv_cell) + 1)):
			var c := Vector2((cx + 0.5) * cell_size, (cy + 0.5) * cell_size)
			if c.distance_squared_to(center) <= r2:
				var i := cy * width + cx
				clutter[i] = clampi(clutter[i] + delta, 0, 255)

func clear_all() -> void:
	obstacles.fill(Cell.FREE)
	version += 1

## Indices of every non-free cell.
func blocked_cells() -> PackedInt32Array:
	var out: PackedInt32Array = []
	for i in obstacles.size():
		if obstacles[i] != Cell.FREE:
			out.append(i)
	return out

func _stamp(center: Vector2, radius: float, kind: int) -> void:
	var r2 := radius * radius
	var rc := int(ceil(radius * _inv_cell))
	var cc := Vector2i(int(center.x * _inv_cell), int(center.y * _inv_cell))
	for cy in range(cc.y - rc, cc.y + rc + 1):
		for cx in range(cc.x - rc, cc.x + rc + 1):
			var c := Vector2((cx + 0.5) * cell_size, (cy + 0.5) * cell_size)
			if c.distance_squared_to(center) <= r2 + cell_size * cell_size * 0.25:
				set_cell(cx, cy, kind)
