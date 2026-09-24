class_name PheromoneField
extends RefCounted
## Any number of named pheromone channels on a grid of cell_size cells.
##
## Storage: every channel lives in one flat PackedFloat32Array (`values`);
## channel c occupies [c * cell_count, (c + 1) * cell_count). A single flat
## array is used because a packed array nested inside an Array would be copied
## on every write from GDScript.
##
## Lazy evaporation: values are stored *raw*. The real value of a cell is
## raw * scale[c]. Evaporating the whole channel is then one multiply of
## scale[c] per tick instead of a pass over every cell. Deposits divide by the
## scale so they land at the intended real value. When the scale gets small the
## channel is renormalised (raw *= scale, scale = 1).
##
## Diffusion: a 3x3 box blur, blended in by the channel's diffusion rate. A
## full pass is expensive in GDScript, so it is spread over diffuse_every ticks:
## each tick blurs one horizontal band of rows of every channel.

const RENORMALISE_BELOW := 0.01
## Real values below this are flushed to zero during diffusion.
const FLUSH_EPSILON := 1e-4

var width: int
var height: int
var cell_size: int
var cell_count: int
var diffuse_every: int
var tick_dt: float
var inv_cell: float

var values: PackedFloat32Array = []
var scale: PackedFloat32Array = []
var decay_per_tick: PackedFloat32Array = []
var diffusion: PackedFloat32Array = []
var cap: PackedFloat32Array = []
var reinforce: PackedFloat32Array = []
var colors: PackedColorArray = []
var render_intensity: PackedFloat32Array = []
var names: PackedStringArray = []
var _index: Dictionary[StringName, int] = {}

## Row where the next diffusion band starts.
var _band_start: int = 0
## Horizontal 3-tap sums for the current band (plus one row above and below).
var _row_sums: PackedFloat32Array = []
## Per channel and grid row (index c * height + y): 1 if the row may hold
## non-zero values. Deposits set it; diffusion clears it for rows that end up
## all zero. Rows with nothing in them or their neighbours skip diffusion,
## which is most of the grid (trails cover a small part of the world).
var row_active: PackedByteArray = []

func _init(grid: Vector2i, cell: int, diffuse_every_n_ticks: int, dt: float) -> void:
	width = grid.x
	height = grid.y
	cell_size = cell
	inv_cell = 1.0 / cell
	cell_count = width * height
	diffuse_every = maxi(1, diffuse_every_n_ticks)
	tick_dt = dt

func add_channel(channel_name: StringName, def: PheromoneChannelDef) -> int:
	assert(not _index.has(channel_name), "Duplicate pheromone channel %s" % channel_name)
	var c := names.size()
	values.resize(values.size() + cell_count)  # new cells are zero
	row_active.resize(row_active.size() + height)
	scale.append(1.0)
	# (Appended one by one: packed arrays put in an Array literal are copies.)
	decay_per_tick.append(0.0)
	diffusion.append(0.0)
	cap.append(0.0)
	reinforce.append(0.0)
	render_intensity.append(0.0)
	colors.append(def.color)
	names.append(channel_name)
	_index[channel_name] = c
	configure_channel(c, def)
	return c

## Adds a channel with the same name and settings as channel c of another
## field (e.g. a new layer copying the surface's channels). Returns its index.
func add_channel_like(other: PheromoneField, c: int) -> int:
	var def := PheromoneChannelDef.new()
	def.color = other.colors[c]
	def.render_intensity = other.render_intensity[c]
	var n := add_channel(other.names[c], def)
	decay_per_tick[n] = other.decay_per_tick[c]
	diffusion[n] = other.diffusion[c]
	cap[n] = other.cap[c]
	reinforce[n] = other.reinforce[c]
	return n

## (Re)applies a channel definition's settings to channel c; values stay.
func configure_channel(c: int, def: PheromoneChannelDef) -> void:
	decay_per_tick[c] = pow(0.5, tick_dt / maxf(def.half_life, 0.001))
	# Blend fraction per diffusion pass; one pass covers diffuse_every ticks.
	diffusion[c] = clampf(def.diffusion * tick_dt * diffuse_every, 0.0, 1.0)
	cap[c] = def.cap
	reinforce[c] = def.reinforce
	colors[c] = def.color
	render_intensity[c] = def.render_intensity

func channel_count() -> int:
	return names.size()

func channel_index(channel_name: StringName) -> int:
	return _index.get(channel_name, -1)

## Flat cell index for a world position, or -1 outside the grid.
func cell_at(pos: Vector2) -> int:
	var cx := int(pos.x * inv_cell)
	var cy := int(pos.y * inv_cell)
	if pos.x < 0.0 or pos.y < 0.0 or cx >= width or cy >= height:
		return -1
	return cy * width + cx

## Deposits `amount` (real units) at pos: cell = max(cell, amount) +
## reinforce * amount, clamped to the channel cap. See PheromoneChannelDef.reinforce.
func deposit(c: int, pos: Vector2, amount: float) -> void:
	var cell := cell_at(pos)
	if cell < 0:
		return
	var i := c * cell_count + cell
	@warning_ignore("integer_division")
	row_active[c * height + cell / width] = 1
	var s := scale[c]
	var a := amount / s
	values[i] = minf(maxf(values[i], a) + a * reinforce[c], cap[c] / s)

## Real value at pos (0 outside the grid).
func sample(c: int, pos: Vector2) -> float:
	var cell := cell_at(pos)
	return 0.0 if cell < 0 else values[c * cell_count + cell] * scale[c]

## Raw (unscaled) value. Comparisons within one channel can skip the multiply.
func sample_raw(c: int, pos: Vector2) -> float:
	var cell := cell_at(pos)
	return 0.0 if cell < 0 else values[c * cell_count + cell]

## Sum of real values in a channel (for tests and stats).
func total(c: int) -> float:
	var sum := 0.0
	var off := c * cell_count
	for i in cell_count:
		sum += values[off + i]
	return sum * scale[c]

## Scales all channels inside a circle by `keep` (0 clears them; rain uses a
## per-tick factor so trails wash out over a moment instead of vanishing).
func wipe_circle(center: Vector2, radius: float, keep: float = 0.0) -> void:
	var r_cells := int(ceil(radius / cell_size))
	var cc := Vector2i(int(center.x * inv_cell), int(center.y * inv_cell))
	var r2 := (radius / cell_size) * (radius / cell_size)
	for y in range(maxi(0, cc.y - r_cells), mini(height, cc.y + r_cells + 1)):
		for x in range(maxi(0, cc.x - r_cells), mini(width, cc.x + r_cells + 1)):
			if Vector2(x - cc.x, y - cc.y).length_squared() <= r2:
				for c in names.size():
					values[c * cell_count + y * width + x] *= keep

## Scales all channels inside a world-space rectangle by `keep` (0 clears them).
func wipe_rect(rect: Rect2, keep: float = 0.0) -> void:
	var x0 := clampi(int(rect.position.x * inv_cell), 0, width)
	var y0 := clampi(int(rect.position.y * inv_cell), 0, height)
	var x1 := clampi(int(ceil(rect.end.x / cell_size)), 0, width)
	var y1 := clampi(int(ceil(rect.end.y / cell_size)), 0, height)
	for c in names.size():
		for y in range(y0, y1):
			var row := c * cell_count + y * width
			for x in range(x0, x1):
				values[row + x] *= keep

## Zeroes the given cells in every channel (e.g. obstacle cells, so trails
## don't diffuse through walls).
func clear_cells(cells: PackedInt32Array) -> void:
	for c in names.size():
		var off := c * cell_count
		for cell in cells:
			values[off + cell] = 0.0

## Advances one tick: evaporation for every channel, diffusion for one band.
func update() -> void:
	var rows_per_tick := ceili(float(height) / diffuse_every)
	var y0 := _band_start
	var y1 := mini(height, y0 + rows_per_tick)
	for c in names.size():
		scale[c] *= decay_per_tick[c]
		if scale[c] < RENORMALISE_BELOW:
			_renormalise(c)
		if diffusion[c] > 0.0:
			_diffuse_band(c, y0, y1)
	_band_start = 0 if y1 >= height else y1

func _renormalise(c: int) -> void:
	var s := scale[c]
	var off := c * cell_count
	for i in cell_count:
		values[off + i] *= s
	scale[c] = 1.0

## 3x3 box blur of rows [y0, y1) of channel c, blended by the channel's rate.
## Uses running sums: a horizontal 3-tap pass into _row_sums, then a vertical
## 3-tap pass back into values. _row_sums holds band rows y0-1 .. y1 (one extra
## row each side); rows outside the grid are left as zeros, so trails fade at
## the world edge and the inner loop needs no bounds checks.
##
## Rows that are all zero (row_active == 0) are skipped: their horizontal sums
## stay zero, and a row whose neighbourhood (itself and the rows above and
## below) is empty stays empty, so it isn't touched at all.
func _diffuse_band(c: int, y0: int, y1: int) -> void:
	var off := c * cell_count
	var act := c * height
	var band_rows := y1 - y0 + 2
	if _row_sums.size() != band_rows * width:
		_row_sums.resize(band_rows * width)
	_row_sums.fill(0.0)

	# Horizontal pass: _row_sums[r][x] = v[x-1] + v[x] + v[x+1], r = y - (y0 - 1).
	# had[r]: whether that row had any content before this pass.
	var had := PackedByteArray()
	had.resize(band_rows)
	for y in range(maxi(0, y0 - 1), mini(height, y1 + 1)):
		if row_active[act + y] == 0:
			continue
		had[y - y0 + 1] = 1
		var src := off + y * width
		var dst := (y - y0 + 1) * width
		var prev := 0.0
		var cur := values[src]
		for x in width - 1:
			var nxt := values[src + x + 1]
			_row_sums[dst + x] = prev + cur + nxt
			prev = cur
			cur = nxt
		_row_sums[dst + width - 1] = prev + cur

	# Vertical pass + blend: v += d * (mean - v); tiny values flush to zero.
	var d := diffusion[c]
	var k := d / 9.0
	var keep := 1.0 - d
	var flush := FLUSH_EPSILON / scale[c]
	for y in range(y0, y1):
		var r := y - y0 + 1
		if had[r - 1] == 0 and had[r] == 0 and had[r + 1] == 0:
			continue
		var mid := r * width
		var above := mid - width
		var below := mid + width
		var row := off + y * width
		var any := false
		for x in width:
			var v := values[row + x] * keep + (_row_sums[above + x] + _row_sums[mid + x] + _row_sums[below + x]) * k
			if v > flush:
				values[row + x] = v
				any = true
			else:
				values[row + x] = 0.0
		row_active[act + y] = 1 if any else 0
