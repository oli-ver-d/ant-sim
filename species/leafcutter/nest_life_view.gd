class_name NestLifeView
extends Control
## The life inside a leafcutter nest, for FungusCutaway's detailed view:
## - the queen, sitting on the garden of the royal chamber; each egg the
##   simulation lays (LeafcutterBrood's lay log) appears at the tip of her
##   abdomen at that moment, and a nurse carries it to the egg pile;
## - the brood where the simulation keeps it (chamber and slot): eggs in a
##   pile, larvae (white grubs) tucked into the garden, growing as nurses
##   bring them fungus, pupae in rows darkening as they mature;
## - callows: pale young workers a nurse helps out of the casing, who then
##   walk up the tunnels timed by their age so they leave through the
##   entrance on the tick the simulation spawns them on the surface;
## - one leaf carrier coming down per fragment delivered, dropping it on the
##   garden.
## Nurses and carriers are render-only agents (NestWorker) given tasks from
## the brood state. In timelapse they hurry, and brood no nurse gets to in
## time fades out and back in at its place. Randomness uses the view's own seeded
## RNG, so a recording is repeatable and the simulation is never touched.

const Stage := LeafcutterBrood.Stage
const Task := NestWorker.Task
const Carry := NestWorker.Carry

## Length of a minim underground (px at 1080 wide); other castes scale from
## it by (size ratio)^CASTE_SIZE_POWER, so majors stay smaller than the queen
## and minims stay big enough to read on a phone.
const NURSE_LENGTH := 52.0
const CASTE_SIZE_POWER := 0.6
const QUEEN_LENGTH := 230.0
const QUEEN_COLOR := Color(0.42, 0.18, 0.08, 0.6)
## Head, thorax, gaster length and height: a big mesosoma and a swollen,
## egg-laying gaster.
const QUEEN_LOOK := Vector4(1.3, 1.4, 1.9, 1.85)
## Where on the floor of the royal chamber she sits (-1..1), and the egg pile.
const QUEEN_AT := -0.2
const PILE_AT := 0.72
const EGG_COLOR := Color(0.98, 0.97, 0.91)
const LARVA_COLOR := Color(0.97, 0.95, 0.88)
const PUPA_PALE := Color(0.95, 0.91, 0.81)
const PUPA_DARK := Color(0.64, 0.45, 0.3)
const CALLOW_TINT := Color(0.93, 0.76, 0.55)
const FUNGUS_COLOR := Color(0.96, 0.94, 0.87)
const LEAF_COLOR := Color(0.38, 0.64, 0.2)
const OUTLINE := Color(0.25, 0.18, 0.12, 0.55)
## Share of the callow stage spent being freed from the casing; then it walks out.
const CALLOW_FREE := 0.35
const NURSE_SPEED := 90.0
const CARRIER_SPEED := 120.0
const MAX_CARRIERS := 4
const MAX_NURSES := 14
## Video seconds a task waits for a free nurse before the brood sorts itself out.
const PATIENCE := 2.5
## Seconds to fade out (and back in) when brood jumps to its place.
const JUMP_FADE := 0.25
## Lay events more recent than this (video seconds) are played at the queen.
const FRESH_EGG := 1.0
## Seconds the intro spotlight takes to fade out.
const SPOT_FADE := 1.5
## How dark the spotlight makes the rest of the view.
const SPOT_DIM := 0.62

## One brood item as drawn.
class Shown:
	var pos: Vector2
	## Chamber it lies in now (it may be on its way to another).
	var chamber: int = 0
	var stage: int = 0
	## Larva growth as of its last feed (drawn size).
	var growth: float = 0.0
	## Progress through the current stage, 0-1.
	var age: float = 0.0
	var carried: bool = false
	var callow_path: PackedVector2Array = []
	var callow_len: float = 0.0
	var look_seed: int = 0
	var facing: float = 1.0
	## Seconds into a fade-jump to its slot (0 = none).
	var fade: float = 0.0

	func alpha() -> float:
		if fade <= 0.0:
			return 1.0
		return absf(1.0 - fade / JUMP_FADE)

var sim: Simulation
var nest: FungusNest
var cut: FungusCutaway
## Video seconds from the start to spotlight the queen (0 = none).
var spotlight_time: float = 0.0

var _brood_layer: Control
var _back: SideAntRenderer
var _front: SideAntRenderer
var _items: Control
var _spot: Control
var _spot_tex: GradientTexture2D
var _shown: Dictionary[int, Shown] = {}
## Tasks waiting for a nurse: {"kind": Task, "id": brood id, "age": video s}.
var _pending: Array[Dictionary] = []
var _workers: Array[NestWorker] = []
## Leaf bits dropped on the garden: x, y, age (video s), seed.
var _flecks: Array[Vector4] = []
## Brood ids laid recently, to start at the queen.
var _fresh: Dictionary[int, bool] = {}
var _rng := RandomNumberGenerator.new()
var _clock: float = 0.0
## Simulated seconds per video second, smoothed.
var _rate: float = 1.0
var _last_sim: float = -1.0
var _seen_laid: int = -1
var _seen_emerged: int = -1
var _seen_leaf: int = -1
var _queen_pulse: float = 0.0
var _staff_timer: float = 0.0
var _minim: CasteDef
var _media: CasteDef

func bind(simulation: Simulation, target: FungusNest, cutaway: FungusCutaway) -> void:
	sim = simulation
	nest = target
	cut = cutaway
	_rng.seed = 424242 + nest.colony_id
	var castes := sim.colonies[nest.colony_id].species.castes
	_minim = castes[0]
	_media = castes[mini(1, castes.size() - 1)]
	for c in castes:
		if c.id == &"minim":
			_minim = c
		elif c.id == &"media":
			_media = c
	_brood_layer = _layer(_draw_brood)
	_back = SideAntRenderer.new()
	add_child(_back)
	_front = SideAntRenderer.new()
	add_child(_front)
	_items = _layer(_draw_items)
	_spot = _layer(_draw_spotlight)
	_spot.visible = false
	# Clear in the middle, darkening to DIM at the edge (and beyond).
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, SPOT_DIM)])
	_spot_tex = GradientTexture2D.new()
	_spot_tex.gradient = g
	_spot_tex.fill = GradientTexture2D.FILL_RADIAL
	_spot_tex.fill_from = Vector2(0.5, 0.5)
	_spot_tex.fill_to = Vector2(1.0, 0.5)
	_spot_tex.width = 256
	_spot_tex.height = 256

func _layer(draw_fn: Callable) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(draw_fn)
	add_child(c)
	return c

func _scale() -> float:
	return cut.size.x / 1080.0

func _process(delta: float) -> void:
	if sim == null or delta <= 0.0:
		return
	_clock += delta
	var now := sim.time()
	if _last_sim >= 0.0:
		_rate = lerpf(_rate, (now - _last_sim) / delta, 1.0 - exp(-delta / 0.3))
	_last_sim = now
	var speedup := clampf(_rate, 1.0, 5.0)
	_queen_pulse = maxf(0.0, _queen_pulse - delta / 0.7)
	_read_events()
	_sync_brood(delta)
	_staff(delta)
	for task in _pending:
		task["age"] = float(task["age"]) + delta
	_assign_tasks()
	for w: NestWorker in _workers.duplicate():
		w.move(delta, speedup)
		_work(w)
	for n in range(_flecks.size() - 1, -1, -1):
		var f := _flecks[n]
		f.z += delta
		_flecks[n] = f
		if f.z > 6.0:
			_flecks.remove_at(n)
	_draw_ants()
	_update_spotlight()
	_brood_layer.queue_redraw()
	_items.queue_redraw()

# --- Events -------------------------------------------------------------------------

## Plays what the simulation logged since last frame: eggs laid, workers
## emerged (named to the layout to highlight on the surface), leaf delivered.
func _read_events() -> void:
	var b := nest.brood
	if b != null:
		if _seen_laid < 0:
			_seen_laid = b.eggs_laid
		while _seen_laid < b.eggs_laid:
			var n := _seen_laid
			_seen_laid += 1
			if b.eggs_laid - n > LeafcutterBrood.EVENT_LOG:
				continue
			# Only eggs laid moments ago (in video time) start at the queen;
			# in a fast timelapse the rest are already in the pile.
			var ago := (sim.tick_count - b.lay_tick(n)) * sim.dt / maxf(_rate, 0.01)
			if ago < FRESH_EGG:
				_fresh[b.lay_ids[n % LeafcutterBrood.EVENT_LOG]] = true
				_queen_pulse = 1.0
		if _seen_emerged < 0:
			_seen_emerged = b.emerged
		if _seen_emerged < b.emerged:
			_seen_emerged = b.emerged
			# Only near real time: in a timelapse workers pour out too fast to follow.
			if _rate < 3.0:
				cut.highlight_ant = b.emerge_ants[(b.emerged - 1) % LeafcutterBrood.EVENT_LOG]
	if _seen_leaf < 0:
		_seen_leaf = nest.leaf_items
	var arrived := nest.leaf_items - _seen_leaf
	_seen_leaf = nest.leaf_items
	var carriers := 0
	for w in _workers:
		if w.is_carrier:
			carriers += 1
	for n in mini(arrived, MAX_CARRIERS - carriers):
		_spawn_carrier()

# --- Brood --------------------------------------------------------------------------

## Matches the drawn brood to the simulation's records and makes tasks for
## what changed: new eggs to carry, brood to move to a new chamber, larvae to
## feed, callows to free.
func _sync_brood(delta: float) -> void:
	var b := nest.brood
	if b == null:
		return
	var alive: Dictionary[int, bool] = {}
	for i in b.count():
		var id := b.id[i]
		alive[id] = true
		var st := b.stage[i]
		var target := _slot_pos(i)
		var sh: Shown = _shown.get(id)
		if sh == null:
			sh = Shown.new()
			sh.look_seed = id * 7919 + 17
			sh.facing = 1.0 if (id % 2) == 0 else -1.0
			sh.stage = st
			sh.chamber = b.chamber[i]
			sh.growth = b.growth[i]
			sh.pos = target
			if _fresh.has(id):
				_fresh.erase(id)
				sh.pos = _queen_tip()
				sh.chamber = 0
				_add_task(Task.MOVE, id)
			elif st == Stage.CALLOW:
				_start_callow(sh, i)
			_shown[id] = sh
		sh.age = b.age[i] / b.stage_time[st]
		if st != sh.stage:
			sh.stage = st
			if st == Stage.CALLOW:
				_start_callow(sh, i)
				_add_task(Task.FREE, id)
		if st == Stage.CALLOW:
			# Where its age says it is: it leaves through the entrance
			# exactly when the stage ends.
			sh.pos = sh.pos.lerp(_callow_pos(sh), 1.0 - exp(-delta / 0.035))
			continue
		if sh.carried:
			continue
		var far := sh.pos.distance_to(target) > 2.0
		if sh.fade > 0.0:
			sh.fade += delta
			if sh.fade >= JUMP_FADE and far:
				sh.pos = target
				sh.chamber = b.chamber[i]
			if sh.fade >= 2.0 * JUMP_FADE:
				sh.fade = 0.0
		elif far and _waited(id, Task.MOVE) > PATIENCE:
			# No nurse came in time (fast timelapse): it fades out and back in
			# at its place rather than sliding through the soil.
			sh.fade = 0.001
			_pending = _pending.filter(func(t: Dictionary) -> bool: return not (int(t["id"]) == id and t["kind"] == Task.MOVE))
		elif far and not _has_task(id, Task.MOVE):
			_add_task(Task.MOVE, id)
		if st == Stage.LARVA:
			if b.growth[i] - sh.growth > 0.2 and not _has_task(id, Task.FEED):
				_add_task(Task.FEED, id)
			if _waited(id, Task.FEED) > PATIENCE:
				sh.growth = lerpf(sh.growth, b.growth[i], 1.0 - exp(-delta / 0.5))
		elif st > Stage.LARVA:
			sh.growth = 1.0
	for id: int in _shown.keys():
		if not alive.has(id):
			_shown.erase(id)
	_pending = _pending.filter(func(t: Dictionary) -> bool: return _shown.has(int(t["id"])) or int(t["id"]) < 0)

## Screen position (feet / resting point) of brood record i.
func _slot_pos(i: int) -> Vector2:
	var b := nest.brood
	var s := _scale()
	var k := mini(b.chamber[i], cut.chamber_count() - 1)
	var slot := b.slot[i]
	if b.stage[i] == Stage.EGG:
		# Egg piles: rows of 6, 5, 4... stacked up; every 21 eggs a new pile.
		var base := cut.floor_point(0, PILE_AT if (slot / 21) % 2 == 0 else -0.6)
		var j := slot % 21
		var row := 0
		var width := 6
		while j >= width:
			j -= width
			row += 1
			width -= 1
		return base + Vector2((j - (width - 1) * 0.5) * 15.0, -row * 11.0 + 3.0) * s
	# Larvae and pupae lie in rows along the garden top, later rows tucked
	# deeper in (and staggered).
	var per_row := 6 if b.stage[i] == Stage.LARVA else 5
	var row := slot / per_row
	var col := slot % per_row
	var u := -0.8 + 1.6 * (col + 0.5 + 0.5 * (row % 2)) / (per_row + 0.5)
	var sink := (12.0 + 24.0 * row) if b.stage[i] == Stage.LARVA else (3.0 + 20.0 * row)
	return cut.floor_point(k, u) + Vector2(0, sink * s)

func _queen_feet() -> Vector2:
	return cut.floor_point(0, QUEEN_AT) + Vector2(0, 2.0 * _scale())

func _queen_length() -> float:
	return QUEEN_LENGTH * _scale()

## The tip of her abdomen (she faces left).
func _queen_tip() -> Vector2:
	var l := _queen_length()
	return _queen_feet() + Vector2(0.78 * l, -(SideAntRenderer.FOOT + 0.02) * l)

func _start_callow(sh: Shown, i: int) -> void:
	var from := _slot_pos(i)
	sh.pos = from
	sh.callow_path = cut.path(from, nest.brood.chamber[i], cut.entrance(), -1)
	sh.callow_len = 0.0
	for n in range(1, sh.callow_path.size()):
		sh.callow_len += sh.callow_path[n - 1].distance_to(sh.callow_path[n])

## Walked distance along the callow's path at its current age.
func _callow_walked(sh: Shown) -> float:
	return clampf((sh.age - CALLOW_FREE) / (1.0 - CALLOW_FREE), 0.0, 1.0) * sh.callow_len

func _callow_pos(sh: Shown) -> Vector2:
	return _along(sh.callow_path, _callow_walked(sh))

## Point `dist` along a polyline, and the direction there via _along_dir.
static func _along(route: PackedVector2Array, dist: float) -> Vector2:
	for n in range(1, route.size()):
		var seg := route[n - 1].distance_to(route[n])
		if dist <= seg:
			return route[n - 1].lerp(route[n], dist / maxf(seg, 0.001))
		dist -= seg
	return route[route.size() - 1] if route.size() > 0 else Vector2.ZERO

static func _along_dir(route: PackedVector2Array, dist: float) -> Vector2:
	for n in range(1, route.size()):
		var seg := route[n - 1].distance_to(route[n])
		if dist <= seg or n == route.size() - 1:
			return (route[n] - route[n - 1]).normalized()
		dist -= seg
	return Vector2.RIGHT

# --- Tasks and workers --------------------------------------------------------------

func _add_task(kind: Task, id: int) -> void:
	_pending.append({"kind": kind, "id": id, "age": 0.0})

func _has_task(id: int, kind: Task) -> bool:
	for t in _pending:
		if int(t["id"]) == id and t["kind"] == kind:
			return true
	for w in _workers:
		if w.brood_id == id and w.task == kind:
			return true
	return false

## Video seconds a pending task has waited, or -1 if none is pending.
func _waited(id: int, kind: Task) -> float:
	for t in _pending:
		if int(t["id"]) == id and t["kind"] == kind:
			return float(t["age"])
	return -1.0

## Keeps enough nurses for the brood: more brood, more nurses. The first frame
## gets them all; after that they come in one at a time, from the side of the
## chamber that needs them most.
func _staff(delta: float) -> void:
	var brood_n := nest.brood.count() if nest.brood != null else 0
	var want := clampi(3 + brood_n / 5, 3, MAX_NURSES)
	var nurses: Array[NestWorker] = []
	for w in _workers:
		if not w.is_carrier:
			nurses.append(w)
	_staff_timer -= delta
	var first := nurses.is_empty()
	while nurses.size() < want and (first or _staff_timer <= 0.0):
		_staff_timer = 0.4
		var k := _neediest_chamber(nurses)
		var w := NestWorker.new()
		w.length = _length(_minim)
		w.speed = NURSE_SPEED * _scale()
		w.color = Color(_minim.color, _minim.mandible_size)
		w.look = _look(_minim)
		w.phase = _rng.randf() * TAU
		w.carry_seed = _rng.randi() % 1000
		w.pos = cut.floor_point(k, -1.0 if _rng.randf() < 0.5 else 1.0)
		w.chamber = k
		if first:
			w.pos = cut.floor_point(k, _rng.randf_range(-0.8, 0.8))
		w.wait = _rng.randf_range(0.0, 0.5)
		_workers.append(w)
		nurses.append(w)
	if nurses.size() > want + 2:
		for w in nurses:
			if w.task == Task.IDLE and not w.walking():
				_workers.erase(w)
				break

## The brood chamber with the most brood per nurse.
func _neediest_chamber(nurses: Array[NestWorker]) -> int:
	var best := 0
	var best_need := -INF
	for k in cut.chamber_count():
		var brood_n := 0.5 if k == 0 else 0.0
		if nest.brood != null:
			for i in nest.brood.count():
				if nest.brood.chamber[i] == k:
					brood_n += 1.0
		var staff := 0
		for w in nurses:
			if w.chamber == k:
				staff += 1
		var need := brood_n / (staff + 1.0)
		if need > best_need:
			best_need = need
			best = k
	return best

## Gives pending tasks to idle nurses, oldest first, nearest nurse first.
func _assign_tasks() -> void:
	var n := 0
	while n < _pending.size():
		var t := _pending[n]
		var id := int(t["id"])
		var sh: Shown = _shown.get(id)
		if sh == null or float(t["age"]) > 12.0:
			_pending.remove_at(n)
			continue
		var best: NestWorker = null
		var best_d := INF
		for w in _workers:
			if w.is_carrier or w.task != Task.IDLE:
				continue
			var d := w.pos.distance_squared_to(sh.pos)
			if d < best_d:
				best_d = d
				best = w
		if best == null:
			return
		_pending.remove_at(n)
		best.task = t["kind"]
		best.brood_id = id
		best.step = 0
		best.wait = 0.0
		best.working = false
		best.go(cut.path(best.pos, best.chamber, _beside(best, sh.pos, sh.chamber), sh.chamber), sh.chamber)

## Where a worker stands to reach something at `at` in chamber k: beside
## it, on the floor, facing it.
func _beside(w: NestWorker, at: Vector2, k: int) -> Vector2:
	var side := -1.0 if w.pos.x < at.x else 1.0
	return Vector2(at.x + side * w.length * 0.5, minf(at.y, cut.floor_y(k)) if k >= 0 else at.y)

## Steps a worker's task along when it has arrived / finished waiting.
func _work(w: NestWorker) -> void:
	# Carried brood goes where the nurse's mandibles are.
	if w.carry == Carry.BROOD and _shown.has(w.brood_id):
		_shown[w.brood_id].pos = w.mouth() + Vector2(0, 2.0 * _scale())
	if w.walking() or w.wait > 0.0:
		return
	w.working = false
	var b := nest.brood
	var sh: Shown = _shown.get(w.brood_id)
	var i := b.index_of(w.brood_id) if b != null and w.brood_id >= 0 else -1
	match w.task:
		Task.IDLE:
			_idle(w)
		Task.MOVE:
			if sh == null or i < 0 or sh.stage == Stage.CALLOW:
				_finish(w)
			elif w.step == 0:
				sh.carried = true
				w.carry = Carry.BROOD
				w.step = 1
				w.go(cut.path(w.pos, sh.chamber, _beside(w, _slot_pos(i), b.chamber[i]), b.chamber[i]), b.chamber[i])
			else:
				var target := _slot_pos(i)
				if w.pos.distance_to(_beside(w, target, b.chamber[i])) > w.length:
					# The slot changed on the way (a stage ended): go on there.
					w.go(cut.path(w.pos, w.chamber, _beside(w, target, b.chamber[i]), b.chamber[i]), b.chamber[i])
				else:
					sh.carried = false
					sh.pos = target
					sh.chamber = b.chamber[i]
					_finish(w)
		Task.FEED:
			if sh == null or i < 0 or sh.stage != Stage.LARVA:
				_finish(w)
			elif w.step == 0:
				# Pick a tuft of fungus from the garden nearby...
				w.go(PackedVector2Array([w.pos, cut.floor_point(sh.chamber, _rng.randf_range(-0.9, 0.9))]), sh.chamber)
				w.step = 1
			elif w.step == 1:
				w.carry = Carry.FUNGUS
				w.working = true
				w.wait = 0.5
				w.step = 2
			elif w.step == 2:
				w.go(cut.path(w.pos, w.chamber, _beside(w, sh.pos, sh.chamber), sh.chamber), sh.chamber)
				w.step = 3
			elif w.step == 3:
				# ...and feed it to the larva, which grows.
				w.working = true
				w.wait = 1.2
				w.step = 4
			else:
				w.carry = Carry.NONE
				sh.growth = b.growth[i]
				_finish(w)
		Task.GROOM, Task.FREE:
			if sh == null or i < 0:
				_finish(w)
			elif w.step == 0:
				w.working = true
				w.wait = _rng.randf_range(1.2, 2.4) if w.task == Task.GROOM else 1.8
				w.dir = Vector2(signf(sh.pos.x - w.pos.x) if absf(sh.pos.x - w.pos.x) > 0.5 else 1.0, 0.0)
				w.step = 1
			else:
				_finish(w)
		Task.CARRY_LEAF:
			if w.step == 0:
				# Drop the fragment on the garden, then head back up and out.
				w.carry = Carry.NONE
				_flecks.append(Vector4(w.mouth().x, w.mouth().y + 3.0 * _scale(), 0.0, float(w.carry_seed)))
				w.working = true
				w.wait = 0.5
				w.step = 1
			elif w.step == 1:
				w.go(cut.path(w.pos, w.chamber, cut.entrance(), -1), -1)
				w.step = 2
			else:
				_workers.erase(w)

func _finish(w: NestWorker) -> void:
	if w.carry == Carry.BROOD and _shown.has(w.brood_id):
		_shown[w.brood_id].carried = false
	w.task = Task.IDLE
	w.carry = Carry.NONE
	w.working = false
	w.brood_id = -1
	w.step = 0
	w.wait = _rng.randf_range(0.3, 1.2)

## Idle nurses stroll about their chamber and groom brood lying there.
func _idle(w: NestWorker) -> void:
	var here: Array[int] = []
	for id: int in _shown:
		var sh := _shown[id]
		if sh.chamber == w.chamber and not sh.carried and sh.stage != Stage.CALLOW:
			here.append(id)
	if not here.is_empty() and _rng.randf() < 0.45:
		var id := here[_rng.randi() % here.size()]
		w.task = Task.GROOM
		w.brood_id = id
		w.step = 0
		w.go(cut.path(w.pos, w.chamber, _beside(w, _shown[id].pos, w.chamber), w.chamber), w.chamber)
		return
	var to := cut.floor_point(w.chamber, _rng.randf_range(-0.9, 0.9))
	w.go(PackedVector2Array([w.pos, to]), w.chamber)
	w.wait = _rng.randf_range(0.4, 2.0)

## A leaf carrier coming down from the entrance to a garden chamber.
func _spawn_carrier() -> void:
	var w := NestWorker.new()
	w.is_carrier = true
	w.task = Task.CARRY_LEAF
	w.carry = Carry.LEAF
	w.carry_seed = _rng.randi() % 1000
	w.length = _length(_media)
	w.speed = CARRIER_SPEED * _scale() * _rng.randf_range(0.9, 1.1)
	w.color = Color(_media.color, _media.mandible_size)
	w.look = _look(_media)
	w.pos = cut.entrance()
	w.dir = Vector2.DOWN
	# Fresh leaf goes onto whichever garden has room, mostly the fuller ones.
	var k := _rng.randi() % cut.chamber_count()
	w.go(cut.path(w.pos, -1, cut.floor_point(k, _rng.randf_range(-0.7, 0.7)), k), k)
	_workers.append(w)

# --- Drawing ------------------------------------------------------------------------

func _draw_ants() -> void:
	_back.clear()
	_front.clear()
	# The queen: slow antenna sway, abdomen swelling a little as she lays.
	var look := QUEEN_LOOK
	look.w *= 1.0 + 0.07 * sin(_queen_pulse * PI)
	_back.add(_queen_feet(), _queen_length(), Vector2.LEFT, Vector2.DOWN, QUEEN_COLOR, look, 0.0, 0.25 * sin(_clock * 0.9))
	for id: int in _shown:
		var sh := _shown[id]
		var i := nest.brood.index_of(id)
		if i < 0:
			continue
		var caste := sim.colonies[nest.colony_id].species.castes[nest.brood.caste[i]]
		var l := _length(caste)
		var clook := _look(caste)
		if sh.stage == Stage.CALLOW:
			var col := Color(caste.color.lerp(CALLOW_TINT, 0.55), caste.mandible_size)
			var walked := _callow_walked(sh)
			if walked <= 0.0:
				# Unfolding in the casing.
				var fold := 1.0 - clampf(sh.age / CALLOW_FREE, 0.0, 1.0) * 0.9
				_back.add(sh.pos, l, Vector2(sh.facing, 0), Vector2.DOWN, col, clook, fold, 0.0)
			else:
				_front.add(sh.pos, l, _along_dir(sh.callow_path, walked), _ground_at(sh.pos), col, clook, 0.0, walked / l * 2.4)
	for w in _workers:
		w.ground = _ground_at(w.pos)
		_front.add(w.pos + w.bob(_clock), w.length, w.dir, w.ground, w.color, w.look, 0.0, w.phase)
	_back.commit()
	_front.commit()

## Intro: everything but the queen dimmed, fading out after spotlight_time.
func _spotlight() -> float:
	return clampf((spotlight_time - _clock) / SPOT_FADE, 0.0, 1.0) if spotlight_time > 0.0 else 0.0

func _update_spotlight() -> void:
	_spot.modulate.a = _spotlight()
	_spot.visible = _spot.modulate.a > 0.0
	if _spot.visible:
		_spot.queue_redraw()

## Dims the view outside a soft ellipse around the queen: a radial gradient
## over her, and flat dimming around it.
func _draw_spotlight() -> void:
	var l := _queen_length()
	var c := _queen_feet() + Vector2(0.25 * l, -0.3 * l)
	var r := Rect2(c - Vector2(1.6, 0.95) * l, Vector2(3.2, 1.9) * l)
	var dim := Color(0, 0, 0, SPOT_DIM)
	var full := Rect2(Vector2.ZERO, cut.size)
	_spot.draw_texture_rect(_spot_tex, r, false)
	_spot.draw_rect(Rect2(0, 0, full.size.x, r.position.y), dim)
	_spot.draw_rect(Rect2(0, r.end.y, full.size.x, full.size.y - r.end.y), dim)
	_spot.draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), dim)
	_spot.draw_rect(Rect2(r.end.x, r.position.y, full.size.x - r.end.x, r.size.y), dim)

## Which way is solid ground at p: outward on a chamber's wall or ceiling,
## otherwise down (floors, and tunnels).
func _ground_at(p: Vector2) -> Vector2:
	for k in cut.chamber_count():
		var r := cut.chamber_rect(k)
		var q := (p - r.position) / r.size
		if q.length_squared() < 1.1 and p.y < cut.floor_y(k) - 6.0 * _scale():
			return (q / r.size).normalized()
	return Vector2.DOWN

## Drawn length of a caste underground.
func _length(caste: CasteDef) -> float:
	return NURSE_LENGTH * pow(caste.size / _minim.size, CASTE_SIZE_POWER) * _scale()

## Side-view look of a caste: head, thorax, gaster length and height.
static func _look(caste: CasteDef) -> Vector4:
	return Vector4(caste.head_scale, caste.thorax_scale, caste.abdomen_scale, caste.abdomen_scale)

## Eggs, larvae, casings and leaf bits (under the ants).
func _draw_brood() -> void:
	var s := _scale()
	var ci := _brood_layer
	for f in _flecks:
		var a := clampf(1.0 - (f.z - 3.0) / 3.0, 0.0, 1.0)
		_leaf_bit(ci, Vector2(f.x, f.y), 10.0 * s, int(f.w), Color(LEAF_COLOR, a))
	if nest.brood == null:
		return
	for id: int in _shown:
		var sh := _shown[id]
		if sh.carried:
			continue
		match sh.stage:
			Stage.EGG:
				_egg(ci, sh.pos, s, sh.alpha())
			Stage.LARVA:
				_larva(ci, sh.pos, sh.growth, sh.facing, sh.look_seed, s, sh.alpha())
			Stage.PUPA:
				_pupa(ci, sh.pos, _brood_length(id) * 0.8, sh.facing, sh.age, sh.alpha())
			Stage.CALLOW:
				if _callow_walked(sh) <= 0.0:
					_casing(ci, sh.pos, sh.age / CALLOW_FREE, sh.look_seed, s)
				# A soft glow follows the young worker so it can be picked out.
				var glow := clampf(sh.age / CALLOW_FREE, 0.0, 1.0) * clampf(2.0 - _rate * 0.5, 0.0, 1.0)
				for n in 10:
					ci.draw_circle(sh.pos + Vector2(0, -12.0 * s), (60.0 - 4.5 * n) * s,
							Color(1.0, 0.88, 0.6, 0.03 * glow), true, -1.0, true)

## What the workers carry (over the ants).
func _draw_items() -> void:
	var s := _scale()
	# Intro: name the queen.
	var spot := _spotlight()
	if spot > 0.0:
		var font := ThemeDB.fallback_font
		var fs := int(34 * s)
		var w := font.get_string_size("the queen", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := _queen_feet() + Vector2(0.4, -0.66) * _queen_length() - Vector2(w * 0.5, 0)
		_items.draw_string_outline(font, at, "the queen", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(7 * s), Color(0.05, 0.03, 0.02, 0.8 * spot))
		_items.draw_string(font, at, "the queen", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.85, spot))
	for w in _workers:
		var m := w.mouth()
		match w.carry:
			Carry.BROOD:
				var sh: Shown = _shown.get(w.brood_id)
				if sh == null:
					continue
				if sh.stage == Stage.EGG:
					_egg(_items, sh.pos, s)
				elif sh.stage == Stage.LARVA:
					_larva(_items, sh.pos, sh.growth, w.dir.x, sh.look_seed, s)
				elif sh.stage == Stage.PUPA:
					_pupa(_items, sh.pos + Vector2(0, 6.0 * s), _brood_length(w.brood_id) * 0.8, signf(w.dir.x), sh.age)
			Carry.FUNGUS:
				_items.draw_circle(m, 6.0 * s, OUTLINE, true, -1.0, true)
				_items.draw_circle(m, 5.0 * s, FUNGUS_COLOR, true, -1.0, true)
				_items.draw_circle(m + Vector2(-1.6, -1.6) * s, 2.0 * s, Color(1, 1, 1, 0.8), true, -1.0, true)
			Carry.LEAF:
				# Held up over the body, as leafcutters carry them.
				var d := w.dir.normalized()
				var up := -SideAntRenderer.down_for(d, w.ground)
				_leaf_bit(_items, m + up * w.length * 0.4 - d * w.length * 0.05, w.length * 0.34, w.carry_seed, LEAF_COLOR)

## `c` with its alpha scaled by `a`.
static func _fa(c: Color, a: float) -> Color:
	return Color(c, c.a * a)

static func _ellipse(ci: CanvasItem, c: Vector2, r: Vector2, angle: float, col: Color) -> void:
	var pts: PackedVector2Array = []
	for n in 18:
		var a := TAU * n / 18.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(angle))
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, 1.0, true)

static func _egg(ci: CanvasItem, at: Vector2, s: float, a: float = 1.0) -> void:
	_ellipse(ci, at, Vector2(9.0, 6.5) * s, 0.3, _fa(OUTLINE, a))
	_ellipse(ci, at, Vector2(7.8, 5.4) * s, 0.3, _fa(EGG_COLOR, a))
	ci.draw_circle(at + Vector2(-2.5, -2.0) * s, 1.8 * s, Color(1, 1, 1, 0.9 * a), true, -1.0, true)

## A C-shaped grub lying on its side; bigger with growth, breathing gently.
func _larva(ci: CanvasItem, at: Vector2, growth: float, facing: float, seed_value: int, s: float,
		alpha: float = 1.0) -> void:
	var l := (15.0 + 26.0 * growth) * s
	var curl := l * 0.3 * (1.0 + 0.04 * sin(_clock * 2.0 + seed_value))
	var centre := at + Vector2(0, -curl * 0.75)
	var pts: PackedVector2Array = []
	var radii: PackedFloat32Array = []
	for n in 7:
		var t := n / 6.0
		var a := lerpf(PI * 1.1, -PI * 0.2, t)
		pts.append(centre + Vector2(cos(a) * curl * facing, -sin(a) * curl * 0.85))
		radii.append(l * (0.21 - 0.07 * t))
	for n in 7:
		ci.draw_circle(pts[n], radii[n] + 1.0 * s, _fa(OUTLINE, alpha), true, -1.0, true)
	for n in 7:
		var shade := LARVA_COLOR.darkened(0.06 * (n % 2))
		ci.draw_circle(pts[n], radii[n], _fa(shade, alpha), true, -1.0, true)
	# Head: a small amber capsule at the thin end.
	ci.draw_circle(pts[6] + (pts[6] - pts[5]).normalized() * radii[6] * 0.6, radii[6] * 0.6, Color(0.86, 0.7, 0.45, alpha), true, -1.0, true)
	ci.draw_circle(pts[1] + Vector2(-0.3, -0.5) * radii[1], radii[1] * 0.35, Color(1, 1, 1, 0.7 * alpha), true, -1.0, true)

## A pupa lying on its side: a pale, compact ant with the head tucked down,
## legs and antennae pressed along the underside. It darkens as it matures,
## the eyes first.
static func _pupa(ci: CanvasItem, feet: Vector2, l: float, facing: float, age: float, a: float = 1.0) -> void:
	var col := _fa(PUPA_PALE.lerp(PUPA_DARK, smoothstep(0.25, 1.0, age)), a)
	var f := Vector2(facing, 1.0)
	# Body parts (centre, radii) in body lengths, x forward, y up from the feet.
	var parts: Array[Rect2] = [
		Rect2(-0.22, -0.16, 0.21, 0.155),  # gaster
		Rect2(-0.02, -0.15, 0.07, 0.07),   # petiole
		Rect2(0.1, -0.17, 0.13, 0.1),      # mesosoma
		Rect2(0.25, -0.1, 0.09, 0.105),    # head, bent down
	]
	for grow: float in [0.018, 0.0]:
		for r in parts:
			_ellipse(ci, feet + r.position * f * l, (r.size + Vector2(grow, grow)) * l, 0.0,
					_fa(OUTLINE, a) if grow > 0.0 else col)
	# Soft light on top of each part.
	for r in parts:
		_ellipse(ci, feet + (r.position + Vector2(0, -r.size.y * 0.4)) * f * l, r.size * Vector2(0.55, 0.35) * l, 0.0,
				Color(1, 1, 1, 0.22 * a))
	# Legs and antennae folded along the underside: darker creases.
	var crease := Color(col.darkened(0.3), 0.8 * a)
	for n in 3:
		var knee := Vector2(0.16 - 0.06 * n, -0.1)
		var tip := Vector2(-0.04 - 0.1 * n, -0.035)
		ci.draw_line(feet + knee * f * l, feet + tip * f * l, crease, maxf(1.0, l * 0.035), true)
	ci.draw_line(feet + Vector2(0.28, -0.18) * f * l, feet + Vector2(0.2, -0.02) * f * l, crease, maxf(1.0, l * 0.025), true)
	# Eyes darken first.
	ci.draw_circle(feet + Vector2(0.28, -0.13) * f * l, l * 0.028, Color(0.12, 0.07, 0.04, smoothstep(0.05, 0.4, age) * a), true, -1.0, true)

## Drawn length of brood item `id`'s adult caste.
func _brood_length(id: int) -> float:
	var i := nest.brood.index_of(id)
	return _length(sim.colonies[nest.colony_id].species.castes[nest.brood.caste[i]]) if i >= 0 else NURSE_LENGTH

## Torn pupal casing around a callow being freed (fades as it comes out).
static func _casing(ci: CanvasItem, at: Vector2, t: float, seed_value: int, s: float) -> void:
	var a := clampf(1.0 - t, 0.0, 1.0) * 0.7
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for n in 5:
		var p := at + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 0)) * s
		_ellipse(ci, p, Vector2(rng.randf_range(5, 10), rng.randf_range(2.5, 5)) * s, rng.randf() * PI, Color(PUPA_PALE, a))

## A small irregular leaf fragment.
static func _leaf_bit(ci: CanvasItem, at: Vector2, r: float, seed_value: int, col: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5
	var pts: PackedVector2Array = []
	var turn := rng.randf() * TAU
	for n in 7:
		var a := turn + TAU * n / 7.0
		pts.append(at + Vector2(cos(a), sin(a) * 0.7) * r * rng.randf_range(0.6, 1.0))
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, col.darkened(0.35), 1.0, true)
	ci.draw_line(pts[0].lerp(at, 0.2), pts[3].lerp(at, 0.2), Color(col.lightened(0.3), col.a * 0.6), 1.0, true)
