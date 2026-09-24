class_name NativeAnts
extends RefCounted
## Drives the native ant kernel (the AntKernel class from the ant_native
## GDExtension in native/, see README "Native ant kernel") for a Simulation.
## When the extension isn't built (or --no-native is given) the Simulation
## has no NativeAnts and everything runs in GDScript, with the same results.
##
## The kernel updates ants in the core behaviours explore, follow_trail,
## carry_home and linger itself, and gives every other behaviour native
## steering (Steering.move/move_to/sense_turn/sense_away, Simulation.lay).
## Any tick that changes an ant's state or needs GDScript objects (food
## sources, items, the nest) runs the ant's GDScript behaviour as usual.
##
## The kernel reads and writes the Simulation's packed arrays in place: each
## tick begin_tick() gives it their buffers (after making sure no other array
## shares them) and end_tick() checks that none was reallocated meanwhile. So
## during a tick nothing may replace or resize those arrays (writing
## elements is fine).

## The kernel (an AntKernel; untyped so this script parses without the extension).
var kernel: Variant
var _sim: Simulation
## Portal.changes when the nests were last sent to the kernel.
var _portal_changes: int = -1
## Behaviour script -> kernel kind.
var _kinds: Dictionary = {}
## Nest script -> _defines_entrance_once().
var _plain: Dictionary[Script, bool] = {}

## Switch the kernel off for Simulations created from now on (tests compare
## both). --no-native on the command line switches it off too.
static var enabled: bool = true

## True if the extension is loaded and not switched off.
static func available() -> bool:
	return enabled and ClassDB.class_exists(&"AntKernel") and not OS.get_cmdline_user_args().has("--no-native")

func _init(sim: Simulation) -> void:
	_sim = sim
	kernel = ClassDB.instantiate(&"AntKernel")
	kernel.set_rng(sim.rng)
	kernel.set_dt(sim.dt)
	_kinds[ExploreBehaviour] = _k(&"KIND_EXPLORE")
	_kinds[FollowTrailBehaviour] = _k(&"KIND_FOLLOW_TRAIL")
	_kinds[CarryHomeBehaviour] = _k(&"KIND_CARRY_HOME")
	_kinds[LingerBehaviour] = _k(&"KIND_LINGER")

## Sends a colony's params to the kernel (after Colony.build_params()).
func push_colony(colony: Colony) -> void:
	var values := PackedFloat64Array([colony.sensor_distance, colony.sensor_cos, colony.sensor_sin,
			colony.sensor_angle, colony.sense_threshold, colony.wander_strength, colony.avoid_lookahead,
			colony.deposit_base, colony.deposit_decay_per_second, colony.carry_mass_slowdown,
			colony.clutter_slowdown, colony.obstacle_memory, colony.food_check_interval])
	kernel.set_colony(colony.id, values, colony.caste_turn_rate, colony.caste_phase_per_unit, colony.num_states)
	var slots: int = _k(&"SLOT_COUNT")
	var params := PackedFloat64Array()
	params.resize(colony.species.castes.size() * colony.num_states * slots)
	for c in colony.species.castes.size():
		for s in colony.num_states:
			var kind: int = _kinds.get(_sim.behaviours[s].get_script(), 0)
			if kind == 0 or not colony.allows(c, s):
				continue
			var p := colony.params_for(c, s)
			var k := (c * colony.num_states + s) * slots
			# The same conversions the GDScript behaviours make.
			params[k + _k(&"SLOT_KIND")] = kind
			params[k + _k(&"SLOT_FOLLOW")] = int(p.get("follow_channel", -1))
			params[k + _k(&"SLOT_LAY")] = int(p.get("lay_channel", -1))
			params[k + _k(&"SLOT_AVOID")] = int(p.get("avoid_channel", -1))
			params[k + _k(&"SLOT_TIMEOUT")] = float(p.get("timeout", 60.0))
			params[k + _k(&"SLOT_HOME_BIAS")] = float(p.get("home_bias", 0.0))
			params[k + _k(&"SLOT_HOME_CONE")] = deg_to_rad(float(p.get("home_cone_deg", 0.0)))
			params[k + _k(&"SLOT_RADIUS")] = float(p.get("radius", 80.0))
			params[k + _k(&"SLOT_SPEED_FACTOR")] = float(p.get("speed_factor", 0.5))
			params[k + _k(&"SLOT_DURATION")] = float(p.get("duration", 0.0))
	kernel.set_state_params(colony.id, params)
	_portal_changes = -1

## Sends every nest's entrance to the kernel (it changes when a portal opens
## or closes, and a nest may move in its update()).
func push_nests() -> void:
	for colony in _sim.colonies:
		var nest := colony.nest
		kernel.set_nest(colony.id, _plain_entrance(nest), nest.has_entrance(), nest.entrance_position(),
				nest.radius, nest.sense_radius)
	_portal_changes = Portal.changes

## Call after an ant's GDScript tick: re-sends the nests if a portal changed.
func sync() -> void:
	if Portal.changes != _portal_changes:
		push_nests()

## Hands the kernel this tick's arrays. Called at the end of begin_step().
func begin_tick() -> void:
	var sim := _sim
	# A packed array assigned to another (e.g. the render snapshots, see
	# end_step()) shares its buffer until one of them is written, which then
	# copies it. Writing an element of each array here makes sure each has a
	# buffer of its own before the kernel takes it.
	sim.alive[0] = sim.alive[0]
	sim.pos[0] = sim.pos[0]
	sim.heading[0] = sim.heading[0]
	sim.speed[0] = sim.speed[0]
	sim.colony_id[0] = sim.colony_id[0]
	sim.caste_id[0] = sim.caste_id[0]
	sim.state[0] = sim.state[0]
	sim.carried[0] = sim.carried[0]
	sim.timer[0] = sim.timer[0]
	sim.source_age[0] = sim.source_age[0]
	sim.since_obstacle[0] = sim.since_obstacle[0]
	sim.scratch_f0[0] = sim.scratch_f0[0]
	sim.anim_phase[0] = sim.anim_phase[0]
	sim.layer[0] = sim.layer[0]
	sim.transit_until[0] = sim.transit_until[0]
	sim.carry_mass[0] = sim.carry_mass[0]
	for l in sim.layers:
		var w := l.world
		var f := l.pheromones
		w.obstacles[0] = w.obstacles[0]
		w.near_blocked[0] = w.near_blocked[0]
		w.clutter[0] = w.clutter[0]
		if f.scale.size() > 0:
			f.values[0] = f.values[0]
			f.row_active[0] = f.row_active[0]
			f.scale[0] = f.scale[0]
	kernel.bind_ants(sim.alive, sim.pos, sim.heading, sim.speed, sim.colony_id, sim.caste_id, sim.state,
			sim.carried, sim.timer, sim.source_age, sim.since_obstacle, sim.scratch_f0, sim.anim_phase, sim.layer,
			sim.transit_until, sim.carry_mass)
	for l in sim.layers:
		var w := l.world
		var f := l.pheromones
		kernel.bind_layer(l.index, w.obstacles, w.near_blocked, w.clutter, w.width, w.height, w.inv_cell,
				f.values, f.row_active, f.scale, f.reinforce, f.cap, w.cell_size, f.width, f.height, f.inv_cell)
	push_nests()
	push_food()
	kernel.set_profiling(sim.layers.size() > 1)

## Sends each colony the food sources it forages from that are not used up,
## as circles FoodSource.sense_bound() wide: outside them the kernel skips
## explore's food check (it can't find anything there). One used up during
## the tick only makes the kernel check in vain.
func push_food() -> void:
	for colony in _sim.colonies:
		var circles := PackedFloat64Array()
		for src in _sim.food_sources:
			if not src.is_depleted() and colony.food_types.has(src.type_id):
				circles.append_array([src.position.x, src.position.y, src.sense_bound()])
		kernel.set_food(colony.id, circles)

## Checks that the kernel's arrays are still the Simulation's. Returns false
## (and reports an error) if one was replaced during the tick.
func end_tick() -> bool:
	var sim := _sim
	var moved: PackedStringArray = []
	var mask: int = kernel.check_ants(sim.alive, sim.pos, sim.heading, sim.speed, sim.colony_id, sim.caste_id,
			sim.state, sim.carried, sim.timer, sim.source_age, sim.since_obstacle, sim.scratch_f0, sim.anim_phase,
			sim.layer, sim.transit_until, sim.carry_mass)
	_name_bits(mask, ANT_ARRAYS, "", moved)
	for l in sim.layers:
		var w := l.world
		var f := l.pheromones
		mask = kernel.check_layer(l.index, w.obstacles, w.near_blocked, w.clutter, f.values, f.row_active, f.scale)
		_name_bits(mask, LAYER_ARRAYS, "layer %d " % l.index, moved)
	var ok := moved.is_empty()
	if not ok:
		push_error("NativeAnts: %s replaced during tick %d; switching to GDScript ants" % [", ".join(moved), sim.tick_count])
	if sim.layers.size() > 1:
		var prof: PackedInt64Array = kernel.take_profile()
		@warning_ignore("integer_division")
		var n := prof.size() / 2
		for l in mini(n, sim.profile_layer_usec.size()):
			sim.profile_layer_usec[l] += prof[l]
			sim.profile_layer_ant_ticks[l] += prof[n + l]
	return ok

## Arrays in bind_ants/check_ants and bind_layer/check_layer order (the bits
## of the check masks).
const ANT_ARRAYS: PackedStringArray = ["alive", "pos", "heading", "speed", "colony_id", "caste_id", "state",
		"carried", "timer", "source_age", "since_obstacle", "scratch_f0", "anim_phase", "layer", "transit_until",
		"carry_mass"]
const LAYER_ARRAYS: PackedStringArray = ["obstacles", "near_blocked", "clutter", "pheromone values", "row_active",
		"pheromone scale"]

static func _name_bits(mask: int, names: PackedStringArray, prefix: String, out: PackedStringArray) -> void:
	if mask < 0:
		out.append(prefix + "(not bound)")
		return
	for b in names.size():
		if mask & (1 << b):
			out.append(prefix + names[b])

## An AntKernel integer constant.
static func _k(constant: StringName) -> int:
	return ClassDB.class_get_integer_constant(&"AntKernel", constant)

## True if the nest uses NestType's own entrance geometry (has_entrance,
## entrance_position, is_at_nest), which the kernel reproduces.
func _plain_entrance(nest: NestType) -> bool:
	var script: Script = nest.get_script()
	if not _plain.has(script):
		_plain[script] = _defines_entrance_once(script)
	return _plain[script]

static func _defines_entrance_once(script: Script) -> bool:
	var counts := {}
	for m: Dictionary in script.get_script_method_list():
		counts[m["name"]] = counts.get(m["name"], 0) + 1
	# A method a subclass overrides is listed once per script that defines it.
	for method: String in ["has_entrance", "entrance_position", "is_at_nest"]:
		if counts.get(method, 0) != 1:
			return false
	return true

# --- Grid helpers ------------------------------------------------------------------------
# For any sim code (e.g. food sources): the kernel's versions when it is
# available, else the same in GDScript, with the same results.

static var _class_ok: int = -1

static func _static_ok() -> bool:
	if _class_ok < 0:
		_class_ok = 1 if ClassDB.class_exists(&"AntKernel") and not OS.get_cmdline_user_args().has("--no-native") else 0
	return enabled and _class_ok == 1

## Cells of `mask` (nx by ny, row-major) equal to `value` that have a
## 4-neighbour which isn't (the grid's border counts as not), in row-major
## order: the edge of a shape.
static func mask_edges(mask: PackedByteArray, nx: int, ny: int, value: int) -> PackedInt32Array:
	if _static_ok():
		return ClassDB.class_call_static(&"AntKernel", &"mask_edges", mask, nx, ny, value)
	var out: PackedInt32Array = []
	for cy in ny:
		for cx in nx:
			if mask[cy * nx + cx] != value:
				continue
			var inner := cx > 0 and mask[cy * nx + cx - 1] == value and cx < nx - 1 and mask[cy * nx + cx + 1] == value \
					and cy > 0 and mask[(cy - 1) * nx + cx] == value and cy < ny - 1 and mask[(cy + 1) * nx + cx] == value
			if not inner:
				out.append(cy * nx + cx)
	return out

## Index of the point nearest `at` (the first of equally near ones), or -1.
static func nearest_point(points: PackedVector2Array, at: Vector2) -> int:
	if _static_ok():
		return ClassDB.class_call_static(&"AntKernel", &"nearest_point", points, at)
	var best := -1
	var best_d := INF
	for k in points.size():
		var d := points[k].distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = k
	return best
