class_name Simulation
extends RefCounted
## The whole simulation state and its fixed-tick loop. Knows nothing about
## rendering: renderers read these arrays each frame.
##
## Ants are not objects: each ant is an index into the packed arrays below.
## Removed ants go on a free list and their slot is reused by the next spawn.
## All randomness goes through `rng`, so the same seed and scenario give the
## same run.
##
## Layers: layer 0 is the surface (`world` and `pheromones` are its World and
## PheromoneField). A nest may add an underground layer (add_layer) linked to
## the surface by a Portal. Each ant is on one layer (`layer[i]`) and moves,
## senses and lays pheromone there; positions are in its layer's coordinates.
##
## Native ant kernel: when the ant_native GDExtension is built, `native`
## (NativeAnts) updates ants in the core behaviours in native code and speeds
## up steering for the rest, with exactly the same results. It writes these
## arrays in place during a tick, so nothing may replace or resize them while
## a tick is in progress (element writes are fine).

var config: SimConfig
var registry: Registry
var rng := RandomNumberGenerator.new()
## Surface layer's obstacle grid and pheromones (layers[0]).
var world: World
var pheromones: PheromoneField
## Surface scenery props (render-side; only blocking footprints reach `world`).
var scenery: Scenery
var layers: Array[SimLayer] = []
var portals: Array[Portal] = []
## True once there is more than one layer (hot paths skip layer lookups otherwise).
var multi_layer: bool = false
var colonies: Array[Colony] = []
var food_sources: Array[FoodSource] = []
var items: Dictionary[int, Item] = {}
## Ids of the items being carried, in pick-up order: for behaviours looking
## for a carried item, there being far fewer of those than items.
var carried_items: Dictionary[int, bool] = {}
var _food_index: Dictionary[int, FoodSource] = {}

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
## Id of the item this ant is riding on, or -1 (see mount()).
var riding: PackedInt32Array = []
## Seconds spent in the current state (reset on every transition).
var timer: PackedFloat32Array = []
## Seconds since this ant last touched a trail source (nest or food);
## deposit strength decays with it so trails are strongest near their origin.
var source_age: PackedFloat32Array = []
## Seconds since this ant last had to steer around an obstacle (see Steering.move).
var since_obstacle: PackedFloat32Array = []
## Generic scratch slots for behaviours (meaning depends on the current state).
var scratch_f0: PackedFloat32Array = []
var scratch_f1: PackedFloat32Array = []
var scratch_i: PackedInt32Array = []
var target: PackedVector2Array = []
## Walk-cycle phase for rendering (advances with distance travelled).
var anim_phase: PackedFloat32Array = []
## Layer the ant is on (index into `layers`).
var layer: PackedByteArray = []
## While going through a portal: the tick it comes out (0 = not in a portal),
## and which portal (see enter_portal()).
var transit_until: PackedInt32Array = []
var transit_portal: PackedInt32Array = []
## Tick the ant last came out of a portal (renderers fade it in).
var arrive_tick: PackedInt32Array = []
## Agents on each layer (kept up to date by spawn, remove and portals).
var layer_agents: PackedInt32Array = []
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
## Ids of obstructing items (debris) lying on the ground.
var _ground_clutter: PackedInt32Array = []

## Timed scenario events sorted by "t" (simulated seconds); see ScenarioEvents.
var events: Array[Dictionary] = []
var _next_event: int = 0
## Incremented whenever an item is created, destroyed, picked up or put down,
## so renderers of items lying on the ground know when to redraw.
var items_version: int = 0
## Rain showers, past and present: [{"area", "start", "until", "keep"}]
## (see start_rain). Active ones wash pheromones out of their area.
var rain: Array[Dictionary] = []

## Accumulated microseconds spent in each part of step(), for profiling.
var profile_usec: Dictionary[String, int] = {"nests": 0, "ants": 0, "pheromones": 0}
## With several layers: microseconds of ant updates, and ant updates, per layer.
var profile_layer_usec: PackedInt64Array = []
var profile_layer_ant_ticks: PackedInt64Array = []

## The native ant kernel's driver (see NativeAnts), or null when the
## extension isn't built or is switched off: then every ant runs in GDScript.
var native: NativeAnts = null
## Its AntKernel, for the steering helpers to call (untyped: the class only
## exists with the extension). Only valid while native_bound.
var kernel: Variant = null
## True during a tick while the kernel holds this tick's arrays.
var native_bound: bool = false
## Mass of the item each ant picked up (the kernel reads it for carry_home).
var carry_mass: PackedFloat64Array = []

func _init(sim_config: SimConfig, sim_registry: Registry, seed_value: int) -> void:
	config = sim_config
	registry = sim_registry
	rng.seed = seed_value
	dt = config.tick_dt()
	var surface := SimLayer.new(0, &"surface", config.world_size, config.cell_size, config.diffuse_every_n_ticks, dt)
	layers.append(surface)
	layer_agents.append(0)
	world = surface.world
	pheromones = surface.pheromones
	scenery = Scenery.new(world, registry, seed_value)

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
	since_obstacle.resize(capacity)
	scratch_f0.resize(capacity)
	scratch_f1.resize(capacity)
	anim_phase.resize(capacity)
	prev_pos.resize(capacity)
	shown_pos.resize(capacity)
	shown_heading.resize(capacity)
	prev_heading.resize(capacity)
	carried.resize(capacity)
	carried.fill(-1)
	riding.resize(capacity)
	riding.fill(-1)
	scratch_i.resize(capacity)
	layer.resize(capacity)
	transit_until.resize(capacity)
	transit_portal.resize(capacity)
	arrive_tick.resize(capacity)
	arrive_tick.fill(NEVER_ARRIVED)
	carry_mass.resize(capacity)
	if NativeAnts.available():
		native = NativeAnts.new(self)
		kernel = native.kernel

## arrive_tick of an ant that never came through a portal.
const NEVER_ARRIVED := -(1 << 30)

# --- Setup ---------------------------------------------------------------------

## Adds a layer (e.g. an underground) of `size` world units with `cell`-unit
## cells. Its pheromone field gets every channel the surface has, at the same
## indices. Returns the new layer.
func add_layer(layer_name: StringName, size: Vector2i, cell: int) -> SimLayer:
	assert(layers.size() < 255, "Too many layers for a byte index")
	var l := SimLayer.new(layers.size(), layer_name, size, cell, config.diffuse_every_n_ticks, dt)
	l.clear_blocked = false
	# Same channels as the surface (including a colony being set up right now).
	for c in pheromones.channel_count():
		l.pheromones.add_channel_like(pheromones, c)
	layers.append(l)
	layer_agents.append(0)
	multi_layer = true
	return l

## Links two layers (see Portal). Its nav field toward the side-b end is
## created on layer b.
func add_portal(layer_a: int, pos_a: Vector2, layer_b: int, pos_b: Vector2, radius: float = 10.0) -> Portal:
	var p := Portal.new()
	p.id = portals.size()
	p.layer_a = layer_a
	p.pos_a = pos_a
	p.layer_b = layer_b
	p.pos_b = pos_b
	p.radius = radius
	var nav := layers[layer_b].nav()
	# Every cell within the portal radius is a way out.
	p.nav_field = nav.set_target(StringName("portal:%d" % p.id),
			layers[layer_b].world.cells_in_segment(pos_b, pos_b, maxf(radius * 0.6, layers[layer_b].world.cell_size)))
	portals.append(p)
	return p

## Starts taking ant i through `portal` (it must be near the end on its
## layer). The ant walks into the hole for the portal's transit time, then
## comes out at the other end. Riders on its item get off here. Returns false
## if the portal is closed or the ant is already going through one.
func enter_portal(i: int, portal: Portal) -> bool:
	if not portal.open or transit_until[i] != 0 or not portal.connects(layer[i]):
		return false
	var item := item_of(i)
	if item != null:
		_dismount_all(item)
	dismount(i)
	transit_portal[i] = portal.id
	transit_until[i] = tick_count + maxi(1, roundi(portal.transit_time / dt))
	return true

func in_transit(i: int) -> bool:
	return transit_until[i] != 0

## How visible ant i is for renderers, 0-1: fading out while it goes into a
## portal, fading in after it comes out.
func portal_fade(i: int) -> float:
	var done := completed_ticks()
	if transit_until[i] != 0:
		var total := maxi(1, roundi(portals[transit_portal[i]].transit_time / dt))
		return clampf(float(transit_until[i] - done) / total, 0.0, 1.0)
	var since := done - arrive_tick[i]
	if since > 30:
		return 1.0
	return clampf(float(since) / 10.0, 0.0, 1.0)

## One tick of an ant going through a portal: into the hole, then out.
func _tick_transit(i: int) -> void:
	var p := portals[transit_portal[i]]
	if tick_count < transit_until[i]:
		var here := p.end_on(layer[i])
		var step := speed[i] * 0.6 * dt
		var to := here - pos[i]
		if to.length() > 0.5:
			heading[i] = to.angle()
		pos[i] = pos[i].move_toward(here, step)
		anim_phase[i] += step * colonies[colony_id[i]].caste_phase_per_unit[caste_id[i]]
		return
	var to_layer := p.other_layer(layer[i])
	var out := p.end_on(to_layer)
	var h := rng.randf_range(-PI, PI)
	var at := out + Vector2.from_angle(h) * 2.0
	if layers[to_layer].world.is_blocked(at):
		at = out
	layer_agents[layer[i]] -= 1
	layer_agents[to_layer] += 1
	layer[i] = to_layer
	pos[i] = at
	heading[i] = h
	# Jump the render snapshots too, so the ant doesn't streak across the layer.
	prev_pos[i] = at
	shown_pos[i] = at
	transit_until[i] = 0
	arrive_tick[i] = tick_count
	since_obstacle[i] = 1e6

## World of the layer ant i is on.
func world_of(i: int) -> World:
	return layers[layer[i]].world

## overrides: this colony's own tweaks: "nest_type" (a nest type to use instead
## of the species' own), "params" and "state_params" (see
## Colony.build_params) and "channels": {"home": {"half_life": 60, ...}}
## (PheromoneChannelDef properties).
func add_colony(species_id: String, nest_pos: Vector2, nest_param_overrides: Dictionary = {},
		overrides: Dictionary = {}) -> Colony:
	var def := registry.species.get(species_id) as SpeciesDef
	assert(def != null, "Unknown species %s" % species_id)
	var colony := Colony.new(colonies.size(), def, nest_pos)
	for ch in def.channels:
		var channel_def := _channel_def(ch, overrides)
		colony.channels[ch.name] = pheromones.add_channel(StringName("c%d.%s" % [colony.id, ch.name]), channel_def)
		for l in range(1, layers.size()):
			layers[l].pheromones.add_channel(StringName("c%d.%s" % [colony.id, ch.name]), channel_def)
	colony.build_params(config, behaviour_index, overrides)
	var nest_type: String = overrides.get("nest_type", "")
	if nest_type == "":
		nest_type = def.nest_type
	var nest_script: Script = registry.nest_types.get(nest_type)
	assert(nest_script != null, "Unknown nest type %s" % nest_type)
	colony.nest = nest_script.new()
	colony.nest.type_id = nest_type
	var nest_params := def.nest_params.duplicate()
	nest_params.merge(nest_param_overrides, true)
	colony.nest.setup(self, colony, nest_params)
	# A nest that digs has more states and params for its castes (see Colony).
	if colony.nest.underground_layer >= 0:
		colony.build_params(config, behaviour_index, overrides)
	colonies.append(colony)
	if native != null:
		native.push_colony(colony)
	return colony

## Moves ants standing on blocked cells (e.g. after a wall was drawn over
## them) to the nearest free cell, so no ant is ever inside an obstacle.
## Riders are skipped: they follow their item. Returns how many were moved.
func evict_ants_from_obstacles() -> int:
	var moved := 0
	for i in high_water:
		var w := layers[layer[i]].world
		if alive[i] == 0 or riding[i] >= 0 or in_transit(i) or not w.is_blocked(pos[i]):
			continue
		var p := w.nearest_free(pos[i])
		pos[i] = p
		# Jump the render snapshots too, so the ant doesn't streak across the wall.
		prev_pos[i] = p
		shown_pos[i] = p
		moved += 1
	return moved

## Re-applies config, species and colony settings to every colony (params
## and pheromone channel settings), e.g. after live tuning. Structural config
## (world size, tick rate... see SimConfig.STRUCTURAL) is not re-applied.
func refresh_params() -> void:
	for colony in colonies:
		colony.build_params(config, behaviour_index, colony.overrides)
		if native != null:
			native.push_colony(colony)
		for ch in colony.species.channels:
			for l in layers:
				l.pheromones.configure_channel(colony.channels[ch.name], _channel_def(ch, colony.overrides))

## The channel definition a colony uses: the species' own, or a copy with
## the colony's "channels" overrides applied (e.g. {"home": {"half_life": 60}}).
static func _channel_def(ch: PheromoneChannelDef, overrides: Dictionary) -> PheromoneChannelDef:
	var tweaks: Dictionary = overrides.get("channels", {}).get(str(ch.name), {})
	if tweaks.is_empty():
		return ch
	var channel := ch.duplicate() as PheromoneChannelDef
	for key: String in tweaks:
		assert(key in channel, "Unknown channel property %s" % key)
		channel.set(key, tweaks[key])
	return channel

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
	_food_index[src.id] = src
	# Added during a tick (e.g. with the mouse): the kernel's food checks see it at once.
	if native_bound:
		native.push_food()
	return src

func food_by_id(food_id: int) -> FoodSource:
	return _food_index.get(food_id)

# --- Ants ------------------------------------------------------------------------

## Creates an ant and returns its index, or -1 if the simulation is full.
func spawn_ant(colony: Colony, caste: int, at: Vector2, heading_rad: float, on_layer: int = 0) -> int:
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
	riding[i] = -1
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
	since_obstacle[i] = 1e6
	scratch_f0[i] = 0.0
	scratch_f1[i] = 0.0
	scratch_i[i] = -1
	target[i] = Vector2.ZERO
	anim_phase[i] = rng.randf() * TAU
	layer[i] = on_layer
	layer_agents[on_layer] += 1
	transit_until[i] = 0
	arrive_tick[i] = NEVER_ARRIVED
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
	dismount(i)
	var colony := colonies[colony_id[i]]
	colony.population -= 1
	colony.population_by_caste[caste_id[i]] -= 1
	alive[i] = 0
	layer_agents[layer[i]] -= 1
	transit_until[i] = 0
	ant_count -= 1
	_free_slots.append(i)

func colony_of(i: int) -> Colony:
	return colonies[colony_id[i]]

func caste_of(i: int) -> CasteDef:
	return colonies[colony_id[i]].species.castes[caste_id[i]]

## Params for the ant's current state (species params + caste overrides).
func state_params(i: int) -> Dictionary:
	return colonies[colony_id[i]].params_for(caste_id[i], state[i])

func state_id(i: int) -> String:
	return behaviour_ids[state[i]]

## Switches state via exit()/enter(). Only called from step() with a tick() result,
## or by setup code.
func change_state(i: int, next_state: String) -> void:
	var next_idx: int = behaviour_index.get(next_state, -1)
	assert(next_idx >= 0, "Unknown behaviour state '%s'" % next_state)
	assert(colonies[colony_id[i]].allows(caste_id[i], next_idx),
			"Caste %s may not enter state %s" % [caste_of(i).id, next_state])
	behaviours[state[i]].exit(self, i)
	state[i] = next_idx
	timer[i] = 0.0
	behaviours[next_idx].enter(self, i)

## Lays pheromone on channel c at the ant's position. Strength decays
## exponentially with the time since the ant last touched its source.
func lay(i: int, c: int) -> void:
	if native_bound:
		kernel.lay(i, c)
		return
	var colony := colonies[colony_id[i]]
	var amount := colony.deposit_base * exp(-source_age[i] * colony.deposit_decay_per_second)
	# Inlined PheromoneField.deposit() (max + reinforce); ants are always inside the world.
	var field := layers[layer[i]].pheromones if multi_layer else pheromones
	var at := pos[i]
	var row := int(at.y * field.inv_cell)
	var idx := c * field.cell_count + row * field.width + int(at.x * field.inv_cell)
	field.row_active[c * field.height + row] = 1
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
	items_version += 1
	return item

func destroy_item(item_id: int) -> void:
	carried_items.erase(item_id)
	items.erase(item_id)
	items_version += 1

func item_of(i: int) -> Item:
	return items.get(carried[i]) if carried[i] >= 0 else null

func pick_up(i: int, item: Item) -> void:
	assert(carried[i] < 0, "Ant %d already carries an item" % i)
	if item.carrier < 0:
		_set_on_ground(item, false)
	carried[i] = item.id
	carry_mass[i] = item.mass
	carried_items[item.id] = true
	item.carrier = i
	items_version += 1

## Puts the carried item on the ground at the ant's position. Riders get off.
func drop_item(i: int) -> Item:
	var item := item_of(i)
	carried[i] = -1
	if item != null:
		item.carrier = -1
		carried_items.erase(item.id)
		item.position = pos[i]
		item.rotation = heading[i]
		item.layer = layer[i]
		_dismount_all(item)
		_set_on_ground(item, true)
		items_version += 1
	return item

## Places a new item on the ground (e.g. debris from a scenario).
func place_on_ground(item: Item, at: Vector2, rotation_rad: float, on_layer: int = 0) -> void:
	item.carrier = -1
	carried_items.erase(item.id)
	item.position = at
	item.rotation = rotation_rad
	item.layer = on_layer
	_set_on_ground(item, true)
	items_version += 1

## Hands the carried item to the ant's nest and records the delivery.
## Riders get off at the nest.
func deliver_item(i: int) -> void:
	var item := item_of(i)
	if item == null:
		return
	var colony := colonies[colony_id[i]]
	carried[i] = -1
	item.carrier = -1
	_dismount_all(item)
	colony.nest.receive_item(self, item)
	colony.delivered_items += 1
	colony.delivered_mass += item.mass
	destroy_item(item.id)

## Ids of obstructing items lying on the ground (debris), in placement order.
func ground_clutter() -> PackedInt32Array:
	return _ground_clutter

func _set_on_ground(item: Item, on_ground: bool) -> void:
	if not item.obstructs:
		return
	var k := _ground_clutter.find(item.id)
	if on_ground and k < 0:
		_ground_clutter.append(item.id)
		layers[item.layer].world.add_clutter(item.position, item.footprint, 1)
	elif not on_ground and k >= 0:
		_ground_clutter.remove_at(k)
		layers[item.layer].world.add_clutter(item.position, item.footprint, -1)

# --- Riding ------------------------------------------------------------------------
# Generic mechanism for ants riding on a carried item (e.g. hitchhikers).
# A rider's position/heading are set from its item's carrier at the end of
# every tick (after all ants have moved), so riders stay glued to the item.
# Behaviours decide when to mount; the core makes riders dismount when the
# item is dropped or delivered (riding[i] becomes -1).

## Puts ant i on `item` at `offset` (item frame: x along the carrier's heading).
func mount(i: int, item: Item, offset: Vector2) -> void:
	dismount(i)
	riding[i] = item.id
	item.riders.append(i)
	item.rider_offsets.append(offset)

func dismount(i: int) -> void:
	var item: Item = items.get(riding[i]) if riding[i] >= 0 else null
	riding[i] = -1
	if item == null:
		return
	var k := item.riders.find(i)
	if k >= 0:
		item.riders.remove_at(k)
		item.rider_offsets.remove_at(k)

func _dismount_all(item: Item) -> void:
	for r in item.riders:
		riding[r] = -1
	item.riders.clear()
	item.rider_offsets.clear()

## Moves every rider onto its item (called at the end of each tick).
func _sync_riders() -> void:
	for id: int in items:
		var item: Item = items[id]
		if item.riders.is_empty() or item.carrier < 0:
			continue
		var c := item.carrier
		var h := heading[c]
		var fwd := Vector2.from_angle(h)
		var centre := pos[c] + fwd * caste_of(c).size * Item.HOLD_OFFSET
		for k in item.riders.size():
			var r := item.riders[k]
			var o := item.rider_offsets[k]
			pos[r] = centre + fwd * o.x + fwd.orthogonal() * o.y
			heading[r] = h
			if layer[r] != layer[c]:
				layer_agents[layer[r]] -= 1
				layer_agents[layer[c]] += 1
				layer[r] = layer[c]

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
		colony.nest.update_underground(self, dt)
	if tick_count % POOL_EVERY == 0 and _pools_on:
		balance_pools()
	var lookahead := 0.0
	for colony in colonies:
		lookahead = maxf(lookahead, colony.avoid_lookahead)
	for l in layers:
		l.world.ensure_near_blocked(lookahead)
		if l.nav_grid != null:
			l.nav_grid.update()
	# Ants spawned during this tick get their first update next tick.
	_tick_ants = high_water
	_cursor = 0
	if native != null:
		if layers.size() > 1 and profile_layer_usec.size() != layers.size():
			profile_layer_usec.resize(layers.size())
			profile_layer_ant_ticks.resize(layers.size())
		native.begin_tick()
		native_bound = true
	profile_usec["nests"] += Time.get_ticks_usec() - t0

## Updates up to `count` more ants of the tick in progress. Returns true when
## every ant has been updated (then call end_step()).
func step_ants(count: int) -> bool:
	var t0 := Time.get_ticks_usec()
	var end := mini(_tick_ants, _cursor + count)
	if native_bound:
		_step_ants_native(_cursor, end)
	elif layers.size() > 1:
		_step_ants_layered(_cursor, end)
	else:
		for i in range(_cursor, end):
			if alive[i] == 0:
				continue
			timer[i] += dt
			source_age[i] += dt
			since_obstacle[i] += dt
			var next := behaviours[state[i]].tick(self, i, dt)
			if next != "":
				change_state(i, next)
	_cursor = end
	profile_usec["ants"] += Time.get_ticks_usec() - t0
	return _cursor >= _tick_ants

## step_ants() with the native kernel: it updates ants in order until one
## needs GDScript (see NativeAnts), which is updated here as usual.
func _step_ants_native(from: int, end: int) -> void:
	var i := from
	var layered := layers.size() > 1
	while i < end:
		i = kernel.run(i, end, tick_count)
		if i >= end:
			return
		if layered:
			_step_ants_layered(i, i + 1)
		else:
			timer[i] += dt
			source_age[i] += dt
			since_obstacle[i] += dt
			var next := behaviours[state[i]].tick(self, i, dt)
			if next != "":
				change_state(i, next)
		native.sync()
		i += 1

## step_ants() with several layers: ants going through a portal are moved by
## the core, and time is profiled per layer (profile_layer_usec).
func _step_ants_layered(from: int, end: int) -> void:
	if profile_layer_usec.size() != layers.size():
		profile_layer_usec.resize(layers.size())
		profile_layer_ant_ticks.resize(layers.size())
	for i in range(from, end):
		if alive[i] == 0:
			continue
		var t := Time.get_ticks_usec()
		var li := layer[i]
		if transit_until[i] != 0:
			_tick_transit(i)
		else:
			timer[i] += dt
			source_age[i] += dt
			since_obstacle[i] += dt
			var next := behaviours[state[i]].tick(self, i, dt)
			if next != "":
				change_state(i, next)
		profile_layer_usec[li] += Time.get_ticks_usec() - t
		profile_layer_ant_ticks[li] += 1

## Finishes the tick in progress: pheromone update and render snapshots.
func end_step() -> void:
	assert(in_tick() and _cursor >= _tick_ants, "end_step() before all ants were updated")
	# Traffic is sampled while the kernel still holds this tick's arrays.
	if tick_count % TrafficMap.SAMPLE_EVERY == 0:
		_sample_traffic()
	if native_bound:
		native_bound = false
		if not native.end_tick():
			native = null
			kernel = null
	var t2 := Time.get_ticks_usec()
	# Keeps trails from soaking through walls on the surface (see SimLayer).
	for l in layers:
		l.update_pheromones(tick_count)
		if l.traffic != null:
			l.traffic.decay()
	profile_usec["pheromones"] += Time.get_ticks_usec() - t2

	_sync_riders()
	prev_pos = shown_pos
	prev_heading = shown_heading
	shown_pos = pos
	shown_heading = heading
	_cursor = -1

## Adds each agent's time to its layer's traffic map (layers that count
## traffic, see TrafficMap), in ant order; natively when the kernel runs.
func _sample_traffic() -> void:
	for l in layers:
		var tm := l.traffic
		if tm == null:
			continue
		var add := tm.sample_add(dt)
		if native_bound:
			tm.values[0] = tm.values[0]
			kernel.add_traffic(l.index, tm.values, high_water, add)
		else:
			var inv := tm.inv_cell
			var w := tm.width
			for i in high_water:
				if alive[i] == 0 or layer[i] != l.index or transit_until[i] != 0:
					continue
				var at := pos[i]
				tm.values[int(at.y * inv) * w + int(at.x * inv)] += add
		tm.version += 1

## Hash of the full simulation state, for determinism checks.
func state_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(PackedInt64Array([tick_count, ant_count, high_water, rng.state]).to_byte_array())
	ctx.update(alive.slice(0, high_water))
	ctx.update(_hashed_states())
	ctx.update(pos.slice(0, high_water).to_byte_array())
	ctx.update(heading.slice(0, high_water).to_byte_array())
	ctx.update(carried.slice(0, high_water).to_byte_array())
	ctx.update(riding.slice(0, high_water).to_byte_array())
	ctx.update(pheromones.values.to_byte_array())
	ctx.update(pheromones.scale.to_byte_array())
	for colony in colonies:
		ctx.update(PackedFloat64Array([colony.delivered_items, colony.delivered_mass, colony.population]).to_byte_array())
		colony.nest.hash_state(ctx)
	# Only runs with more than one layer hash these, so single-layer runs
	# keep the hashes they had before layers existed.
	if layers.size() > 1:
		ctx.update(layer.slice(0, high_water))
		ctx.update(transit_until.slice(0, high_water).to_byte_array())
		for l in range(1, layers.size()):
			ctx.update(layers[l].world.obstacles)
			ctx.update(layers[l].world.soil.to_byte_array())
			ctx.update(layers[l].pheromones.values.to_byte_array())
		for p in portals:
			ctx.update(PackedByteArray([1 if p.open else 0]))
		for colony in colonies:
			ctx.update(colony.abstract_by_caste.to_byte_array())
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

## Starts rain for `duration` simulated seconds over an area ({"center": [x, y],
## "radius": r} or {"rect": [x, y, w, h]}; empty = the whole world). While it
## rains, pheromones in the area halve every `wash_half_life` seconds
## (0 = wiped at once). Showers stay in `rain` after they end (renderers use
## them to draw the ground drying); rain_active() says which are falling.
func start_rain(area: Dictionary, duration: float, wash_half_life: float = 0.0) -> void:
	var keep := 0.0
	if wash_half_life > 0.0:
		keep = pow(0.5, dt / wash_half_life)
	if area.is_empty():
		area = {"rect": [0, 0, config.world_size.x, config.world_size.y]}
	rain.append({"area": area, "start": time(), "until": time() + duration, "keep": keep})

func rain_active(shower: Dictionary) -> bool:
	return time() >= float(shower["start"]) and time() <= float(shower["until"])

func _apply_rain() -> void:
	for shower in rain:
		if not rain_active(shower):
			continue
		var area: Dictionary = shower["area"]
		var keep := float(shower["keep"])
		if area.has("rect"):
			pheromones.wipe_rect(ScenarioEvents.rect2(area["rect"]), keep)
		else:
			pheromones.wipe_circle(ScenarioEvents.vec2(area["center"]), float(area["radius"]), keep)

## The ants' states for state_hash(), each as its rank among the states the
## simulation's colonies may use (in index order) rather than its index among
## every registered behaviour, so registering new behaviours no colony here
## can use doesn't change the hash of existing runs.
func _hashed_states() -> PackedByteArray:
	var used := PackedByteArray()
	used.resize(behaviours.size())
	for colony in colonies:
		for k in colony.allowed_states.size():
			if colony.allowed_states[k] != 0:
				used[k % colony.num_states] = 1
	var rank := PackedByteArray()
	rank.resize(behaviours.size())
	var n := 0
	var identity := true
	for s in behaviours.size():
		rank[s] = n
		identity = identity and n == s
		n += used[s]
	var out := state.slice(0, high_water)
	if not identity:
		for i in out.size():
			out[i] = rank[out[i]]
	return out

# --- Agents and the abstract population ----------------------------------------------
# A layer can cap how many ants it simulates one by one (SimLayer.max_agents).
# Beyond that a colony keeps growing as an abstract population
# (Colony.abstract_by_caste): brood that emerges into a full layer joins it
# (the nest decides, see layer_full()), and every POOL_EVERY ticks
# balance_pools() moves idle agents out of layers that are over their cap,
# brings abstract ants back into layers with room, and swaps a few so the
# agents stay a representative sample of the colony (castes in proportion).
# Abstract ants count wherever the colony's size matters (costs, the HUD);
# the agents do the work. All choices use the sim's RNG, so runs stay
# deterministic.

## Ticks between pool balancing.
const POOL_EVERY := 30
## Most abstract ants brought back into one layer per balancing.
const POOL_MAX_IN := 25

var _pools_on: bool = false
var _pool_cursor: int = 0

## Caps layer `l` at `n` agents (0 = no limit).
func set_max_agents(l: int, n: int) -> void:
	layers[l].max_agents = n
	_pools_on = false
	for layer_ in layers:
		_pools_on = _pools_on or layer_.max_agents > 0

## True if layer l is at its agent cap.
func layer_full(l: int) -> bool:
	return layers[l].max_agents > 0 and layer_agents[l] >= layers[l].max_agents

## Moves ant i into its colony's abstract population.
func pool_ant(i: int) -> void:
	var colony := colonies[colony_id[i]]
	var c := caste_id[i]
	remove_ant(i)
	colony.abstract_by_caste[c] += 1
	colony.abstract += 1

## Adds a new ant of caste c straight to the colony's abstract population.
func add_abstract(colony: Colony, c: int) -> void:
	colony.abstract_by_caste[c] += 1
	colony.abstract += 1

## True if ant i may be moved to the abstract population now: idle enough
## (its state is one of the species' pool_states), carrying nothing, not
## riding or going through a portal, and of a caste that is ever spawned
## (never the queen).
func poolable(i: int) -> bool:
	if alive[i] == 0 or carried[i] >= 0 or riding[i] >= 0 or transit_until[i] != 0:
		return false
	var colony := colonies[colony_id[i]]
	return colony.pool_state_mask[state[i]] != 0 and colony.species.castes[caste_id[i]].spawn_ratio > 0.0

## See the notes above.
func balance_pools() -> void:
	for l in layers:
		if l.max_agents <= 0:
			continue
		var over := layer_agents[l.index] - l.max_agents
		if over > 0:
			_pool_out(l.index, over)
			continue
		for colony in colonies:
			var room := l.max_agents - layer_agents[l.index]
			var n := mini(mini(room, colony.abstract), POOL_MAX_IN)
			for k in n:
				_pool_in(colony, l.index)
			# Full: swap a few so the agents stay representative.
			if colony.abstract > 0 and layer_agents[l.index] >= l.max_agents - 1:
				@warning_ignore("integer_division")
				var swap := maxi(1, l.max_agents / 300)
				var out := _pool_out(l.index, swap, colony.id)
				for k in out:
					_pool_in(colony, l.index)

## Moves up to n poolable agents on layer l (of colony `only`, or any) to
## the abstract population, scanning from a rotating start. Returns how many.
func _pool_out(l: int, n: int, only: int = -1) -> int:
	var moved := 0
	if high_water == 0:
		return 0
	var start := _pool_cursor % high_water
	for k in high_water:
		if moved >= n:
			break
		var i := (start + k) % high_water
		if layer[i] != l or (only >= 0 and colony_id[i] != only) or not poolable(i):
			continue
		pool_ant(i)
		moved += 1
		_pool_cursor = i + 1
	return moved

## Brings one abstract ant of the colony back as an agent on layer l: the
## nest picks the caste and places it (NestType.spawn_from_pool).
func _pool_in(colony: Colony, l: int) -> void:
	if colony.abstract <= 0:
		return
	var c := colony.nest.pool_caste(self, l)
	if c < 0 or colony.abstract_by_caste[c] <= 0:
		return
	colony.abstract_by_caste[c] -= 1
	colony.abstract -= 1
	if colony.nest.spawn_from_pool(self, c, l) < 0:
		colony.abstract_by_caste[c] += 1
		colony.abstract += 1
