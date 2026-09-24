class_name GardenGrid
extends RefCounted
## The fungus gardens of a leafcutter nest that digs its own underground, as
## a grid of CELL-unit cells over the nest's layer (finer than its nav grid),
## covering the dug garden chambers (and the founding garden in the royal
## chamber). Each cell holds:
##   fungus     fungus mass (the garden's sponge), at most `cap` per cell
##   substrate  fresh leaf pulp planted on it, not yet digested
##   spent      old, exhausted material, to be weeded out as waste
##   age        seconds the cell has been growing fungus
##   gong       gongylidia (the swollen hyphal tips ants eat), 0-1
##   sick       1 if a mould has taken hold (spreads until weeded)
##
## It is the M8 model: the gardens digest their pulp at digest_rate * fungus
## per second (each cell by its share of the pulp, growing fungus there),
## turning fungus_yield of it into fungus and the rest
## into spent material; the colony's upkeep eats from every cell alike (a
## lazy scale, like PheromoneField's, so that costs nothing per cell). So
## FungusNest.fungus, .substrate and .waste are this grid's totals.
##   - Growth spreads: a cell with fungus seeds its neighbours that have
##     substrate but no fungus yet, so the garden advances over new pulp.
##   - A cell grows no more fungus once full (cap); a full chamber means the
##     nest needs a new one.
##   - Old cells (older than `life` seconds) slowly turn to spent material;
##     mouldy cells turn fast and infect their neighbours.
##   - Gongylidia swell on healthy fungus over time; nurses harvest them.
##
## Cells are updated a slice per tick (every cell once per SWEEP_TICKS), so
## a big nest's gardens cost a fixed, small share of each tick.

const CELL := 2.0
const SWEEP_TICKS := 30
const NONE := 255

var width: int
var height: int
var fungus: PackedFloat32Array = []
var substrate: PackedFloat32Array = []
var spent: PackedFloat32Array = []
var age: PackedFloat32Array = []
var gong: PackedFloat32Array = []
var sick: PackedByteArray = []
## Chamber index of each cell, or NONE outside the gardens.
var chamber_of: PackedByteArray = []
## Garden cells, chamber by chamber (chamber_first[k] .. + chamber_count[k]).
var cells: PackedInt32Array = []
var chamber_first: PackedInt32Array = []
var chamber_count: PackedInt32Array = []
## Fungus a cell holds when full.
var cap: float = 0.08
## Real fungus = stored fungus * fscale (upkeep scales everything at once).
var fscale: float = 1.0
## Incremented whenever cells change, for renderers.
var version: int = 0

var digest_rate: float = 0.02
var fungus_yield: float = 0.6
var life: float = 900.0
var sick_rate: float = 0.0000005
var gong_rate: float = 1.0 / 90.0
## Fungus grown in total (digested pulp * fungus_yield).
var grown: float = 0.0

var _cursor: int = 0
var _sum_fungus: float = 0.0
var _sum_substrate: float = 0.0
var _sum_spent: float = 0.0
## Fungus and pulp in all the gardens as of the last full sweep (digestion
## uses them).
var _sweep_fungus: float = 0.0
var _sweep_substrate: float = 0.0
## Stored fungus and spent material per chamber, as of the last full sweep.
var _chamber_fungus: PackedFloat32Array = []
var _chamber_spent: PackedFloat32Array = []

func setup(layer_size: Vector2, params: Dictionary) -> void:
	width = int(layer_size.x / CELL)
	height = int(layer_size.y / CELL)
	var n := width * height
	fungus.resize(n)
	substrate.resize(n)
	spent.resize(n)
	age.resize(n)
	gong.resize(n)
	sick.resize(n)
	chamber_of.resize(n)
	chamber_of.fill(NONE)
	life = float(params.get("garden_life", life))
	sick_rate = float(params.get("mould_rate", sick_rate))

## Makes the cells within `radius` of `centre` (and within `clip_radius` of
## `clip_centre`, if given: the chamber's walls) the garden of chamber k.
func add_chamber(k: int, centre: Vector2, radius: float, clip_centre: Vector2 = Vector2.ZERO, clip_radius: float = 0.0) -> void:
	while chamber_first.size() <= k:
		chamber_first.append(cells.size())
		chamber_count.append(0)
	chamber_first[k] = cells.size()
	var r2 := radius * radius
	for cy in range(maxi(0, int((centre.y - radius) / CELL)), mini(height, int((centre.y + radius) / CELL) + 1)):
		for cx in range(maxi(0, int((centre.x - radius) / CELL)), mini(width, int((centre.x + radius) / CELL) + 1)):
			var c := cy * width + cx
			if chamber_of[c] != NONE:
				continue
			var at := Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)
			if at.distance_squared_to(centre) <= r2 and (clip_radius <= 0.0 or at.distance_to(clip_centre) <= clip_radius):
				chamber_of[c] = k
				cells.append(c)
	chamber_count[k] = cells.size() - chamber_first[k]
	version += 1

func has_chamber(k: int) -> bool:
	return k < chamber_count.size() and chamber_count[k] > 0

func cell_at(at: Vector2) -> int:
	var cx := int(at.x / CELL)
	var cy := int(at.y / CELL)
	if cx < 0 or cy < 0 or cx >= width or cy >= height:
		return -1
	return cy * width + cx

func cell_center(c: int) -> Vector2:
	@warning_ignore("integer_division")
	return Vector2((c % width + 0.5) * CELL, (c / width + 0.5) * CELL)

# --- Totals -------------------------------------------------------------------------------

func total_fungus() -> float:
	return _sum_fungus * fscale

func total_substrate() -> float:
	return _sum_substrate

func total_spent() -> float:
	return _sum_spent

## Fungus in cell c.
func fungus_at(c: int) -> float:
	return fungus[c] * fscale

## Share of chamber k's room its fungus fills (0-1), as of the last full
## sweep (cached: callers ask often).
func fill(k: int) -> float:
	if not has_chamber(k) or k >= _chamber_fungus.size():
		return 0.0
	return _chamber_fungus[k] * fscale / (chamber_count[k] * cap)

## Fungus all the garden cells hold when full.
func capacity() -> float:
	return cells.size() * cap

## Recounts the totals exactly (running sums drift a little).
func recount() -> void:
	var f := 0.0
	var s := 0.0
	var w := 0.0
	_chamber_fungus.resize(chamber_count.size())
	_chamber_fungus.fill(0.0)
	_chamber_spent.resize(chamber_count.size())
	_chamber_spent.fill(0.0)
	for c in cells:
		f += fungus[c]
		s += substrate[c]
		w += spent[c]
		_chamber_fungus[chamber_of[c]] += fungus[c]
		_chamber_spent[chamber_of[c]] += spent[c]
	_sum_fungus = f
	_sum_substrate = s
	_sum_spent = w
	_sweep_fungus = f * fscale
	_sweep_substrate = s

# --- Changes -------------------------------------------------------------------------------

## The colony eats `amount` of fungus, from every cell alike. Returns what was eaten.
func eat(amount: float) -> float:
	var total := total_fungus()
	if total <= 1e-9:
		return 0.0
	var take := minf(amount, total)
	fscale *= 1.0 - take / total
	if fscale < 0.01:
		_renormalise()
	return take

## Adds fungus mass to cell c (e.g. a starting pellet, or inoculum carried in).
func add_fungus(c: int, mass: float) -> void:
	fungus[c] += mass / fscale
	_sum_fungus += mass / fscale
	if age[c] <= 0.0:
		age[c] = 0.01
	version += 1

## Takes up to `mass` fungus from cell c; returns what was taken.
func take_fungus(c: int, mass: float) -> float:
	var take := minf(mass, fungus[c] * fscale)
	fungus[c] -= take / fscale
	_sum_fungus -= take / fscale
	version += 1
	return take

## Spreads `mass` of fresh pulp over the cells within `radius` of `at`
## (garden cells only). Returns what was planted (all of it if any cell fits).
func plant(at: Vector2, mass: float, radius: float = 3.0) -> float:
	var targets: PackedInt32Array = []
	var weights: PackedFloat32Array = []
	var total_w := 0.0
	var r2 := radius * radius
	for cy in range(maxi(0, int((at.y - radius) / CELL)), mini(height, int((at.y + radius) / CELL) + 1)):
		for cx in range(maxi(0, int((at.x - radius) / CELL)), mini(width, int((at.x + radius) / CELL) + 1)):
			var c := cy * width + cx
			if chamber_of[c] == NONE:
				continue
			var d2 := Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL).distance_squared_to(at)
			if d2 <= r2:
				var wgt := 1.0 - d2 / (r2 + 0.01) * 0.7
				targets.append(c)
				weights.append(wgt)
				total_w += wgt
	if targets.is_empty():
		return 0.0
	for k in targets.size():
		var m := mass * weights[k] / total_w
		substrate[targets[k]] += m
		_sum_substrate += m
	version += 1
	return mass

## Removes up to `mass` of spent material around `at` (weeding; mouldy
## cells there are cleared too). Returns what was removed.
func weed(at: Vector2, mass: float, radius: float = 9.0) -> float:
	var got := 0.0
	var r2 := radius * radius
	for cy in range(maxi(0, int((at.y - radius) / CELL)), mini(height, int((at.y + radius) / CELL) + 1)):
		for cx in range(maxi(0, int((at.x - radius) / CELL)), mini(width, int((at.x + radius) / CELL) + 1)):
			var c := cy * width + cx
			if chamber_of[c] == NONE or Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL).distance_squared_to(at) > r2:
				continue
			sick[c] = 0
			var take := minf(spent[c], mass - got)
			spent[c] -= take
			_sum_spent -= take
			got += take
			if spent[c] <= 1e-6 and fungus[c] * fscale <= cap * 0.05:
				# Cleared down to the floor: the cell starts afresh.
				age[c] = 0.0
				gong[c] = 0.0
	version += 1
	return got

## One tick: updates the next slice of cells (every cell once per
## SWEEP_TICKS ticks, each by SWEEP_TICKS * dt). rng drives mould.
func update(dt: float, rng: RandomNumberGenerator) -> void:
	var n := cells.size()
	if n == 0:
		return
	var per_tick := ceili(float(n) / SWEEP_TICKS)
	var step := dt * SWEEP_TICKS
	var capr := cap / fscale
	var end := mini(n, _cursor + per_tick)
	for j in range(_cursor, end):
		var c := cells[j]
		var f := fungus[c]
		var s := substrate[c]
		if f <= 0.0 and s <= 0.0 and spent[c] <= 0.0:
			continue
		# Digestion: the gardens digest their pulp at the M8 rate (digest_rate
		# * all the fungus), each cell its share by the pulp on it; the new
		# fungus grows where the pulp was.
		if s > 0.0 and _sweep_fungus > 0.0:
			var d := minf(s, digest_rate * _sweep_fungus * step * s / maxf(_sweep_substrate, s))
			substrate[c] = s - d
			_sum_substrate -= d
			var gain := d * fungus_yield / fscale
			grown += d * fungus_yield
			# New growth is young: the cell's age is the mass-weighted age.
			age[c] = age[c] * f / (f + gain) if f > 0.0 else 0.01
			# A full cell spills its growth into a neighbouring garden cell.
			var keep := minf(gain, maxf(0.0, capr - f))
			fungus[c] = f + keep
			if gain > keep:
				_spill(c, gain - keep)
			_sum_fungus += gain
			spent[c] += d * (1.0 - fungus_yield)
			_sum_spent += d * (1.0 - fungus_yield)
			f = fungus[c]
		if f > 0.0:
			age[c] += step
			# Gongylidia swell on healthy fungus.
			if sick[c] == 0:
				gong[c] = minf(1.0, gong[c] + gong_rate * step * minf(1.0, f / capr))
			# Spread into neighbours that have pulp but no fungus yet.
			if f > capr * 0.3:
				_seed_neighbours(c, f)
			# Old or mouldy fungus turns to spent material.
			var rot := 0.0
			if sick[c] != 0:
				rot = 0.08 * step
			elif age[c] > life:
				rot = 0.004 * step
			elif rng.randf() < sick_rate * step:
				sick[c] = 1
			if rot > 0.0:
				var lost := fungus[c] * minf(1.0, rot)
				fungus[c] -= lost
				_sum_fungus -= lost
				spent[c] += lost * fscale
				_sum_spent += lost * fscale
				gong[c] *= 1.0 - minf(1.0, rot)
				if sick[c] != 0 and rng.randf() < 0.04 * step:
					_infect_neighbour(c, rng)
	_cursor = 0 if end >= n else end
	if _cursor == 0:
		recount()
	version += 1

## A cell with plenty of fungus passes a little to each neighbour that has
## pulp but no fungus (moving mass, so the total is unchanged).
func _seed_neighbours(c: int, f: float) -> void:
	var cx := c % width
	@warning_ignore("integer_division")
	var cy := c / width
	for k in 4:
		var nx := cx + (1 if k == 0 else (-1 if k == 1 else 0))
		var ny := cy + (1 if k == 2 else (-1 if k == 3 else 0))
		if nx < 0 or ny < 0 or nx >= width or ny >= height:
			continue
		var nb := ny * width + nx
		if chamber_of[nb] == NONE or fungus[nb] > 0.0 or substrate[nb] <= 0.0:
			continue
		var give := f * 0.05
		fungus[c] -= give
		fungus[nb] += give
		age[nb] = 0.01
		f -= give

func _infect_neighbour(c: int, rng: RandomNumberGenerator) -> void:
	var k := rng.randi() % 4
	var nb := c + (1 if k == 0 else (-1 if k == 1 else (width if k == 2 else -width)))
	if nb >= 0 and nb < chamber_of.size() and chamber_of[nb] != NONE and fungus[nb] > 0.0:
		sick[nb] = 1

func _renormalise() -> void:
	for c in cells:
		fungus[c] *= fscale
	_sum_fungus *= fscale
	fscale = 1.0

# --- Finding places --------------------------------------------------------------------
# Scans sample `tries` random cells of a chamber (deterministic through the
# rng), so they cost the same however big the garden is.

## A good cell of chamber k to plant pulp on: on the garden's surface or
## its growing edge, not already loaded with pulp or spent. -1 if none.
func plant_cell(k: int, rng: RandomNumberGenerator, tries: int = 40) -> int:
	if not has_chamber(k):
		return -1
	var best := -1
	var best_score := -INF
	for t in tries:
		var c := cells[chamber_first[k] + rng.randi() % chamber_count[k]]
		var f := fungus[c] * fscale
		var near := f > 0.0 or _neighbour_fungus(c)
		# Best on fungus that has room to grow: pulp there digests at once.
		var growing := minf(f / cap, 1.0) * (1.0 - minf(f / cap, 1.0)) * 4.0
		var score := (1.0 if near else 0.0) + growing - substrate[c] / (cap * 1.5) - spent[c] / cap - float(sick[c])
		if score > best_score:
			best_score = score
			best = c
	return best

## The cell of chamber k with the most gongylidia among `tries` samples, or -1.
func harvest_cell(k: int, rng: RandomNumberGenerator, tries: int = 30) -> int:
	if not has_chamber(k):
		return -1
	var best := -1
	var best_score := 0.0
	for t in tries:
		var c := cells[chamber_first[k] + rng.randi() % chamber_count[k]]
		var score := gong[c] * fungus[c] * fscale
		if score > best_score:
			best_score = score
			best = c
	return best

## A cell of chamber k with spent material or mould worth weeding, or -1.
func weed_cell(k: int, rng: RandomNumberGenerator, min_spent: float, tries: int = 40) -> int:
	if not has_chamber(k):
		return -1
	var best := -1
	var best_score := min_spent
	for t in tries:
		var c := cells[chamber_first[k] + rng.randi() % chamber_count[k]]
		var score := spent[c] + float(sick[c]) * cap
		if score > best_score:
			best_score = score
			best = c
	return best

## Spent material in chamber k, as of the last full sweep.
func spent_in(k: int) -> float:
	if not has_chamber(k) or k >= _chamber_spent.size():
		return 0.0
	return _chamber_spent[k]

func _neighbour_fungus(c: int) -> bool:
	for nb: int in [c - 1, c + 1, c - width, c + width]:
		if nb >= 0 and nb < fungus.size() and fungus[nb] > 0.0:
			return true
	return false

func hash_into(ctx: HashingContext) -> void:
	ctx.update(PackedFloat64Array([fscale, _sum_fungus, _sum_substrate, _sum_spent, _cursor]).to_byte_array())
	if not cells.is_empty():
		ctx.update(cells.to_byte_array())

## Takes up to `mass` of fungus from the cells within `radius` of `at`, the
## richest first (a bite of gongylidia spans several cells). Returns what
## was taken; their gongylidia are used up in proportion.
func take_around(at: Vector2, mass: float, radius: float = 10.0) -> float:
	var near: Array[Vector2] = []
	var r2 := radius * radius
	for cy in range(maxi(0, int((at.y - radius) / CELL)), mini(height, int((at.y + radius) / CELL) + 1)):
		for cx in range(maxi(0, int((at.x - radius) / CELL)), mini(width, int((at.x + radius) / CELL) + 1)):
			var c := cy * width + cx
			if chamber_of[c] != NONE and fungus[c] > 0.0 and Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL).distance_squared_to(at) <= r2:
				near.append(Vector2(fungus[c], c))
	near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	var got := 0.0
	for e in near:
		if got >= mass:
			break
		var c := int(e.y)
		var had := fungus[c] * fscale
		var take := take_fungus(c, minf(mass - got, had * 0.7))
		gong[c] = maxf(0.0, gong[c] - take / maxf(had, 1e-6))
		got += take
	return got

## Puts `raw` stored fungus from a full cell c into its least full
## neighbouring garden cell (or back into c if it has none).
func _spill(c: int, raw: float) -> void:
	var best := c
	var best_f := INF
	var cx := c % width
	@warning_ignore("integer_division")
	var cy := c / width
	for k in 4:
		var nx := cx + (1 if k == 0 else (-1 if k == 1 else 0))
		var ny := cy + (1 if k == 2 else (-1 if k == 3 else 0))
		if nx < 0 or ny < 0 or nx >= width or ny >= height:
			continue
		var nb := ny * width + nx
		if chamber_of[nb] != NONE and fungus[nb] < best_f:
			best_f = fungus[nb]
			best = nb
	if fungus[best] <= 0.0:
		age[best] = 0.01
	fungus[best] += raw
