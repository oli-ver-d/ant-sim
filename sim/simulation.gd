class_name Simulation
extends RefCounted
## The whole simulation state and its fixed-tick loop. Knows nothing about
## rendering: renderers read these arrays each frame.
##
## Ants are not objects: each ant is an index into the packed arrays below.
## Removed ants go on a free list and their slot is reused by the next spawn.
## All randomness goes through `rng`, so the same seed and scenario give the
## same run.

var config: SimConfig
var registry: Registry
var rng := RandomNumberGenerator.new()
var world: World
var pheromones: PheromoneField
var colonies: Array[Colony] = []
var food_sources: Array[FoodSource] = []
var items: Dictionary[int, Item] = {}

var tick_count: int = 0
## Seconds per tick (1 / tick_rate).
var dt: float

# Behaviour table: states are stored per ant as a byte index into these.
var behaviour_ids: PackedStringArray = []
var behaviours: Array[Behaviour] = []
var behaviour_index: Dictionary[String, int] = {}

# --- Per-ant arrays (all sized to `capacity`) --------------------------------
var capacity: int
## Slots [0, high_water) have been used at least once; iterate only these.
var high_water: int = 0
var ant_count: int = 0
var alive: PackedByteArray = []
var pos: PackedVector2Array = []
## Heading in radians (0 = +x, clockwise on screen since y points down).
var heading: PackedFloat32Array = []
## This ant's cruise speed (caste speed with a little individual variation).
var speed: PackedFloat32Array = []
var colony_id: PackedByteArray = []
var caste_id: PackedByteArray = []
var state: PackedByteArray = []
## Carried item id, or -1.
var carried: PackedInt32Array = []
## Seconds spent in the current state (reset on every transition).
var timer: PackedFloat32Array = []
## Seconds since this ant last touched a trail source (nest or food);
## deposit strength decays with it so trails are strongest near their origin.
var source_age: PackedFloat32Array = []
## Generic scratch slots for behaviours (meaning depends on the current state).
var scratch_f0: PackedFloat32Array = []
var scratch_f1: PackedFloat32Array = []
var scratch_i: PackedInt32Array = []
var target: PackedVector2Array = []
## Walk-cycle phase for rendering (advances with distance travelled).
var anim_phase: PackedFloat32Array = []
## Snapshots for rendering: positions/headings after the last two *completed*
## ticks. Renderers interpolate prev -> shown, so they never see a tick that is
## half processed (see begin_step()/step_ants()). Snapshotting is cheap:
## assigning a packed array shares it; the next write to pos makes one copy.
var shown_pos: PackedVector2Array = []
var shown_heading: PackedFloat32Array = []
var prev_pos: PackedVector2Array = []
var prev_heading: PackedFloat32Array = []

## Index of the next ant to update in the tick in progress, or -1 between ticks.
var _cursor: int = -1
## Number of ant slots the tick in progress covers (high_water at its start).
var _tick_ants: int = 0

var _free_slots: PackedInt32Array = []
var _next_item_id: int = 0
var _next_food_id: int = 0
## Obstacle cells, cleared from pheromones once per diffusion cycle.
var _blocked_cells: PackedInt32Array = []
var _blocked_version: int = -1

## Timed scenario events sorted by "t" (simulated seconds); see ScenarioEvents.
var events: Array[Dictionary] = []
var _next_event: int = 0
## Active rain: [{"area": {...}, "until": seconds}]. Wipes pheromones in its
## area every tick while active; renderers may show it.
var rain: Array[Dictionary] = []

## Accumulated microseconds spent in each part of step(), for profiling.
var profile_usec: Dictionary[String, int] = {"nests": 0, "ants": 0, "pheromones": 0}

func _init(sim_config: SimConfig, sim_registry: Registry, seed_value: int) -> void:
	config = sim_config
	registry = sim_registry
	rng.seed = seed_value
	dt = config.tick_dt()
	world = World.new(config.world_size, config.cell_size)
	pheromones = PheromoneField.new(config.grid_size(), config.cell_size, config.diffuse_every_n_ticks, dt)

	# Behaviour indices are assigned in sorted id order so they are stable.
	var ids := registry.behaviours.keys()
	ids.sort()
	assert(ids.size() <= 255, "Too many behaviour states for a byte index")
	for id: String in ids:
		behaviour_index[id] = behaviours.size()
		behaviour_ids.append(id)
		behaviours.append(registry.behaviours[id])

	capacity = config.max_ants
	alive.resize(capacity)
	colony_id.resize(capacity)
	caste_id.resize(capacity)
	state.resize(capacity)
	pos.resize(capacity)
	target.resize(capacity)
	heading.resize(capacity)
	speed.resize(capacity)
	timer.resize(capacity)
	source_age.resize(capacity)
	scratch_f0.resize(capacity)
	scratch_f1.resize(capacity)
	anim_phase.resize(capacity)
	prev_pos.resize(capacity)
	shown_pos.resize(capacity)
	shown_heading.resize(capacity)
	prev_heading.resize(capacity)
	carried.resize(capacity)
	carried.fill(-1)
	scratch_i.resize(capacity)

# --- Setup ---------------------------------------------------------------------

func add_colony(species_id: String, nest_pos: Vector2, nest_param_overrides: Dictionary = {}) -> Colony:
	var def := registry.species.get(species_id) as SpeciesDef
	assert(def != null, "Unknown species %s" % species_id)
	var colony := Colony.new(colonies.size(), def, nest_pos)
	for ch in def.channels:
		colony.channels[ch.name] = pheromones.add_channel(StringName("c%d.%s" % [colony.id, ch.name]), ch)
	colony.build_params(config, behaviour_index)
	var nest_script: Script = registry.nest_types.get(def.nest_type)
	assert(nest_script != null, "Unknown nest type %s" % def.nest_type)
	colony.nest = nest_script.new()
	colony.nest.type_id = def.nest_type
	var nest_params := def.nest_params.duplicate()
	nest_params.merge(nest_param_overrides, true)
	colony.nest.setup(self, colony, nest_params)
	colonies.append(colony)
	return colony

func add_food_source(type_id: String, params: Dictionary) -> FoodSource:
	var script: Script = registry.food_source_types.get(type_id)
	assert(script != null, "Unknown food source type %s" % type_id)
	var src: FoodSource = script.new()
	src.id = _next_food_id
	_next_food_id += 1
	src.type_id = type_id
	src.position = _vec2(params.get("pos", [0, 0]))
	src.rotation = deg_to_rad(params.get("rotation", 0.0))
	src.setup(self, params)
	food_sources.append(src)
	return src

func food_by_id(food_id: int) -> FoodSource:
	for src in food_sources:
		if src.id == food_id:
			return src
	return null

# --- Ants ------------------------------------------------------------------------

## Creates an ant and returns its index, or -1 if the simulation is full.
func spawn_ant(colony: Colony, caste: int, at: Vector2, heading_rad: float) -> int:
	var i: int
	if _free_slots.size() > 0:
		i = _free_slots[_free_slots.size() - 1]
		_free_slots.resize(_free_slots.size() - 1)
	elif high_water < capacity:
		i = high_water
		high_water += 1
	else:
		return -1
	var caste_def := colony.species.castes[caste]
	alive[i] = 1
	pos[i] = at
	shown_pos[i] = at
	prev_pos[i] = at
	heading[i] = heading_rad
	shown_heading[i] = heading_rad
	prev_heading[i] = heading_rad
	speed[i] = caste_def.speed * rng.randf_range(0.9, 1.1)
	colony_id[i] = colony.id
	caste_id[i] = caste
	carried[i] = -1
	timer[i] = 0.0
	source_age[i] = 0.0
	scratch_f0[i] = 0.0
	scratch_f1[i] = 0.0
	scratch_i[i] = -1
	target[i] = Vector2.ZERO
	anim_phase[i] = rng.randf() * TAU
	state[i] = colony.caste_initial_state[caste]
	ant_count += 1
	colony.population += 1
	colony.population_by_caste[caste] += 1
	behaviours[state[i]].enter(self, i)
	return i

func remove_ant(i: int) -> void:
	if alive[i] == 0:
		return
	behaviours[state[i]].exit(self, i)
	if carried[i] >= 0:
		drop_item(i)
	var colony := colonies[colony_id[i]]
	colony.population -= 1
	colony.population_by_caste[caste_id[i]] -= 1
	alive[i] = 0
	ant_count -= 1
	_free_slots.append(i)

func colony_of(i: int) -> Colony:
	return colonies[colony_id[i]]

func caste_of(i: int) -> CasteDef:
	return colonies[colony_id[i]].species.castes[caste_id[i]]

## Params the colony's species set for the ant's current state.
func state_params(i: int) -> Dictionary:
	return colonies[colony_id[i]].state_params_by_index[state[i]]

func state_id(i: int) -> String:
	return behaviour_ids[state[i]]

## Switches state via exit()/enter(). Only called from step() with a tick() result,
## or by setup code.
func change_state(i: int, next_state: String) -> void:
	var next_idx: int = behaviour_index.get(next_state, -1)
	assert(next_idx >= 0, "Unknown behaviour state '%s'" % next_state)
	assert(caste_of(i).states.has(next_state),
			"Caste %s may not enter state %s" % [caste_of(i).id, next_state])
	behaviours[state[i]].exit(self, i)
	state[i] = next_idx
	timer[i] = 0.0
	behaviours[next_idx].enter(self, i)

## Lays pheromone on channel c at the ant's position. Strength decays
## exponentially with the time since the ant last touched its source.
func lay(i: int, c: int) -> void:
	var colony := colonies[colony_id[i]]
	var amount := colony.deposit_base * exp(-source_age[i] * colony.deposit_decay_per_second)
	# Inlined PheromoneField.deposit() (max + reinforce); ants are always inside the world.
	var field := pheromones
	var at := pos[i]
	var idx := c * field.cell_count + int(at.y * field.inv_cell) * field.width + int(at.x * field.inv_cell)
	var s := field.scale[c]
	var a := amount / s
	field.values[idx] = minf(maxf(field.values[idx], a) + a * field.reinforce[c], field.cap[c] / s)

# --- Items -----------------------------------------------------------------------

func create_item(type_id: String, mass: float) -> Item:
	var script: Script = registry.item_types.get(type_id)
	assert(script != null, "Unknown item type %s" % type_id)
	var item: Item = script.new()
	item.id = _next_item_id
	_next_item_id += 1
	item.type_id = type_id
	item.mass = mass
	items[item.id] = item
	return item

func destroy_item(item_id: int) -> void:
	items.erase(item_id)

func item_of(i: int) -> Item:
	return items.get(carried[i]) if carried[i] >= 0 else null

func pick_up(i: int, item: Item) -> void:
	assert(carried[i] < 0, "Ant %d already carries an item" % i)
	carried[i] = item.id
	item.carrier = i

## Puts the carried item on the ground at the ant's position.
func drop_item(i: int) -> Item:
	var item := item_of(i)
	carried[i] = -1
	if item != null:
		item.carrier = -1
		item.position = pos[i]
		item.rotation = heading[i]
	return item

## Hands the carried item to the ant's nest and records the delivery.
func deliver_item(i: int) -> void:
	var item := item_of(i)
	if item == null:
		return
	var colony := colonies[colony_id[i]]
	carried[i] = -1
	item.carrier = -1
	colony.nest.receive_item(self, item)
	colony.delivered_items += 1
	colony.delivered_mass += item.mass
	destroy_item(item.id)

# --- Queries ---------------------------------------------------------------------

## First food source this colony forages from that the ant at pos senses, with
## a clear line of sight to the source's centre (sources themselves aren't
## obstacles, so this only checks walls/water in between), or null.
func find_sensed_food(at: Vector2, colony: Colony) -> FoodSource:
	for src in food_sources:
		if src.is_depleted() or not colony.food_types.has(src.type_id):
			continue
		if src.is_sensed_at(at, colony) and world.line_clear(at, src.position):
			return src
	return null

# --- Tick ------------------------------------------------------------------------

## Advances the simulation by exactly one fixed tick of `dt` seconds.
## Same as begin_step() + step_ants(all) + end_step().
func step() -> void:
	if not in_tick():
		begin_step()
	step_ants(capacity)
	end_step()

# A tick can be split across several rendered frames so a heavy tick doesn't
# cause one slow frame: begin_step(), then step_ants(n) as many times as
# needed until it returns true, then end_step(). Ants are processed in the
# same order with the same random numbers either way, so the result is
# identical to step().

func in_tick() -> bool:
	return _cursor >= 0

## Ticks fully completed so far (excludes a tick in progress).
func completed_ticks() -> int:
	return tick_count - 1 if in_tick() else tick_count

## Fraction of the ants already updated in the tick in progress (0 between ticks).
func tick_fraction() -> float:
	if not in_tick() or _tick_ants == 0:
		return 0.0
	return float(_cursor) / _tick_ants

## Next ant slot to update in the tick in progress.
func tick_cursor() -> int:
	return maxi(_cursor, 0)

## Number of ant slots the tick in progress covers.
func tick_ant_slots() -> int:
	return _tick_ants

func begin_step() -> void:
	assert(not in_tick(), "begin_step() called twice")
	tick_count += 1
	var t0 := Time.get_ticks_usec()
	_apply_due_events()
	_apply_rain()
	for colony in colonies:
		colony.nest.release_waiting(self, dt)
		colony.nest.update(self, dt)
	var lookahead := 0.0
	for colony in colonies:
		lookahead = maxf(lookahead, colony.avoid_lookahead)
	world.ensure_near_blocked(lookahead)
	# Ants spawned during this tick get their first update next tick.
	_tick_ants = high_water
	_cursor = 0
	profile_usec["nests"] += Time.get_ticks_usec() - t0

## Updates up to `count` more ants of the tick in progress. Returns true when
## every ant has been updated (then call end_step()).
func step_ants(count: int) -> bool:
	var t0 := Time.get_ticks_usec()
	var end := mini(_tick_ants, _cursor + count)
	for i in range(_cursor, end):
		if alive[i] == 0:
			continue
		timer[i] += dt
		source_age[i] += dt
		var next := behaviours[state[i]].tick(self, i, dt)
		if next != "":
			change_state(i, next)
	_cursor = end
	profile_usec["ants"] += Time.get_ticks_usec() - t0
	return _cursor >= _tick_ants

## Finishes the tick in progress: pheromone update and render snapshots.
func end_step() -> void:
	assert(in_tick() and _cursor >= _tick_ants, "end_step() before all ants were updated")
	var t2 := Time.get_ticks_usec()
	pheromones.update()
	# Keep trails from soaking through walls: clear obstacle cells once per
	# diffusion cycle (diffusion is the only way pheromone can get there).
	if tick_count % pheromones.diffuse_every == 0:
		if _blocked_version != world.version:
			_blocked_cells = world.blocked_cells()
			_blocked_version = world.version
		pheromones.clear_cells(_blocked_cells)
	profile_usec["pheromones"] += Time.get_ticks_usec() - t2

	prev_pos = shown_pos
	prev_heading = shown_heading
	shown_pos = pos
	shown_heading = heading
	_cursor = -1

## Hash of the full simulation state, for determinism checks.
func state_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(PackedInt64Array([tick_count, ant_count, high_water, rng.state]).to_byte_array())
	ctx.update(alive.slice(0, high_water))
	ctx.update(state.slice(0, high_water))
	ctx.update(pos.slice(0, high_water).to_byte_array())
	ctx.update(heading.slice(0, high_water).to_byte_array())
	ctx.update(carried.slice(0, high_water).to_byte_array())
	ctx.update(pheromones.values.to_byte_array())
	ctx.update(pheromones.scale.to_byte_array())
	for colony in colonies:
		ctx.update(PackedFloat64Array([colony.delivered_items, colony.delivered_mass, colony.population]).to_byte_array())
	return ctx.finish().hex_encode()

static func _vec2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	var a: Array = v
	return Vector2(a[0], a[1])

# --- Scenario events and weather -------------------------------------------------

## Simulated seconds at the end of the current tick.
func time() -> float:
	return tick_count * dt

## Replaces the timed event list (stable-sorted by "t").
func schedule_events(list: Array[Dictionary]) -> void:
	events = list.duplicate()
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	_next_event = 0

func _apply_due_events() -> void:
	while _next_event < events.size() and float(events[_next_event].get("t", 0.0)) <= time() + 1e-6:
		ScenarioEvents.apply(self, events[_next_event])
		_next_event += 1

## Starts rain over an area ({"center": [x, y], "radius": r} or {"rect": [x, y, w, h]})
## for `duration` simulated seconds.
func start_rain(area: Dictionary, duration: float) -> void:
	rain.append({"area": area, "until": time() + duration})

func _apply_rain() -> void:
	var k := 0
	while k < rain.size():
		if time() > float(rain[k]["until"]):
			rain.remove_at(k)
			continue
		var area: Dictionary = rain[k]["area"]
		if area.has("rect"):
			pheromones.wipe_rect(ScenarioEvents.rect2(area["rect"]))
		else:
			pheromones.wipe_circle(ScenarioEvents.vec2(area["center"]), float(area["radius"]))
		k += 1
