extends TestCase
## M15a: scenery props (Scenery, PropType): built deterministically from their
## own seed, never touching the simulation's RNG; blocking footprints stamped
## into the World (and World.prop_mask), drawn as free by the obstacle mask.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

const SCENERY := [
	{"type": "rock", "center": [700, 1150], "radius": 50, "flat": 0.7},
	{"type": "log", "points": [[300, 1000], [480, 1060], [560, 1020]], "width": 26},
	{"type": "plant", "kind": "rosette", "center": [420, 1250], "radius": 60, "stem": 7},
	{"type": "grass", "center": [640, 1350], "radius": 40},
]

func _data(scenery: Array = SCENERY, seed_value: int = 3) -> Dictionary:
	return {"seed": seed_value,
		"colonies": [{"species": "leafcutter", "nest": [540, 1300], "population": {"minim": 30, "media": 130, "major": 10}}],
		"food": [{"type": "food_pile", "pos": [540, 850], "radius": 26, "amount": 400}],
		"scenery": scenery}

func _run(sim: Simulation, ticks: int) -> void:
	for t in ticks:
		sim.step()

func test_core_types_are_registered() -> void:
	for id: String in ["rock", "log", "plant", "grass"]:
		check(_registry.scenery_types.has(id), "scenery type %s" % id)

func test_same_seed_same_props() -> void:
	var a := ScenarioLoader.build(_data(), _registry, _config)
	var b := ScenarioLoader.build(_data(), _registry, _config)
	check_eq(a.scenery.props.size(), 4, "every prop placed")
	for i in a.scenery.props.size():
		var pa := a.scenery.props[i]
		var pb := b.scenery.props[i]
		check_eq(pa.outline, pb.outline, "%s outline" % pa.type_id)
		check_eq(pa.canopy, pb.canopy, "%s canopy" % pa.type_id)
		check_eq(pa.cells, pb.cells, "%s cells" % pa.type_id)
	check_eq(a.world.obstacles, b.world.obstacles, "same footprints")
	var c := ScenarioLoader.build(_data(), _registry, _config, 99)
	check(c.scenery.props[0].outline != a.scenery.props[0].outline, "another seed gives another rock")

func test_types_block_as_declared() -> void:
	var sim := ScenarioLoader.build(_data(), _registry, _config)
	var props := sim.scenery.props
	check(props[0].blocks and props[0].cells.size() > 100, "rock blocks (%d cells)" % props[0].cells.size())
	check(props[1].blocks and props[1].cells.size() > 50, "log blocks (%d cells)" % props[1].cells.size())
	check(props[2].blocks and props[2].cells.size() > 0, "plant stem blocks")
	check(not props[2].canopy.is_empty(), "plant has a canopy")
	check(not props[3].blocks and props[3].cells.is_empty(), "grass is canopy only")
	check(sim.world.is_blocked(Vector2(700, 1150)), "rock centre blocked")
	check(sim.world.is_blocked(Vector2(420, 1250)), "stem blocked")
	check(not sim.world.is_blocked(Vector2(420, 1290)), "under the plant canopy is free")
	check(not sim.world.is_blocked(Vector2(640, 1350)), "grass does not block")
	for p in props:
		for c in p.cells:
			check(sim.world.obstacles[c] == World.Cell.WALL and sim.world.is_prop_cell(c), "%s cell %d is a prop wall" % [p.type_id, c])

## Non-blocking props leave the run exactly as it was: same RNG state after
## loading, same state hash after running.
func test_props_do_not_touch_sim_rng() -> void:
	var plain := ScenarioLoader.build(_data([]), _registry, _config)
	var decorated := ScenarioLoader.build(_data([
		{"type": "grass", "center": [640, 1350], "radius": 40},
		{"type": "plant", "center": [300, 1100], "stem": 0},
		{"type": "rock", "center": [200, 400], "radius": 30, "blocks": false},
	]), _registry, _config)
	check_eq(decorated.scenery.props.size(), 3, "placed")
	check_eq(decorated.rng.state, plain.rng.state, "RNG untouched by loading")
	_run(plain, 300)
	_run(decorated, 300)
	check_eq(decorated.state_hash(), plain.state_hash(), "same run with non-blocking scenery")

func test_blocking_props_block_ants_gdscript() -> void:
	_check_ants_stay_out(false)

func test_blocking_props_block_ants_native() -> void:
	if not (NativeAnts.enabled and ClassDB.class_exists(&"AntKernel") and not OS.get_cmdline_user_args().has("--no-native")):
		print("    (native kernel not built: skipped)")
		return
	_check_ants_stay_out(true)

func _check_ants_stay_out(native: bool) -> void:
	var was := NativeAnts.enabled
	NativeAnts.enabled = native
	# Props right round the nest and across the way to the food.
	var sim := ScenarioLoader.build(_data([
		{"type": "rock", "center": [540, 1180], "radius": 45},
		{"type": "rock", "center": [620, 1330], "radius": 30},
		{"type": "log", "points": [[380, 1000], [700, 1000]], "width": 24},
		{"type": "plant", "center": [470, 1320], "stem": 8},
	]), _registry, _config)
	var inside := 0
	var past := false
	for t in 600:
		sim.step()
		if t % 10 != 0:
			continue
		for i in sim.high_water:
			if sim.alive[i] != 0 and sim.layer[i] == 0 and sim.world.is_blocked(sim.pos[i]):
				inside += 1
			if sim.alive[i] != 0 and sim.pos[i].y < 980.0:
				past = true
	check_eq(inside, 0, "ant samples inside a prop or wall (native=%s)" % native)
	check_eq(sim.native != null, native, "ran with the kernel = %s" % native)
	check(past, "ants found their way round the log (native=%s)" % native)
	NativeAnts.enabled = was

func test_prop_cells_render_as_free_in_obstacle_mask() -> void:
	var sim := Simulation.new(_config, _registry, 1)
	sim.world.fill_circle(Vector2(100, 100), 20, World.Cell.WALL)
	sim.world.fill_circle(Vector2(300, 100), 20, World.Cell.WATER)
	var rock := sim.scenery.add({"type": "rock", "center": [200, 300], "radius": 30})
	var bytes := ObstacleRenderer.mask_bytes(sim.world)
	var wall := sim.world.cell_at(Vector2(100, 100))
	var water := sim.world.cell_at(Vector2(300, 100))
	check_eq([bytes[wall * 3], bytes[wall * 3 + 1], bytes[wall * 3 + 2]], [255, 0, 0], "wall")
	check_eq([bytes[water * 3], bytes[water * 3 + 1], bytes[water * 3 + 2]], [0, 255, 0], "water")
	for c in rock.cells:
		check_eq([bytes[c * 3], bytes[c * 3 + 1], bytes[c * 3 + 2]], [0, 0, 255], "prop cell %d" % c)

func test_props_leave_walls_and_water_alone() -> void:
	var sim := Simulation.new(_config, _registry, 1)
	sim.world.fill_rect(Rect2(180, 280, 60, 40), World.Cell.WATER)
	var water_cells := sim.world.blocked_cells()
	var rock := sim.scenery.add({"type": "rock", "center": [200, 300], "radius": 40})
	for c in water_cells:
		check_eq(sim.world.obstacles[c], World.Cell.WATER, "water stays water")
		check(not rock.cells.has(c), "water not claimed")
	sim.scenery.remove(rock)
	check_eq(sim.world.blocked_cells(), water_cells, "only the water is left")

func test_remove_scenery_frees_only_unshared_cells() -> void:
	var sim := ScenarioLoader.build({"seed": 1, "scenery": [
		{"type": "rock", "name": "a", "center": [200, 300], "radius": 40},
		{"type": "rock", "name": "b", "center": [240, 300], "radius": 40},
	], "events": [
		{"t": 0.1, "type": "remove_scenery", "name": "a"},
		{"t": 0.2, "type": "add_scenery", "scenery": [{"type": "log", "name": "branch", "points": [[500, 500], [700, 560]], "width": 20}]},
		{"t": 0.3, "type": "remove_scenery", "at": [240, 300]},
	]}, _registry, _config)
	var world := sim.world
	var a := sim.scenery.props[0]
	var b := sim.scenery.props[1]
	var shared := world.cell_at(Vector2(220, 300))
	check(a.cells.has(shared) and b.cells.has(shared), "overlap claimed by both")
	check_eq(world.prop_mask[shared], 2, "counted twice")
	var only_a := world.cell_at(Vector2(170, 300))
	var v := world.version
	_run(sim, 4)
	check(world.version > v, "world version bumped")
	check_eq(world.obstacles[only_a], World.Cell.FREE, "a's own cells freed")
	check_eq(world.obstacles[shared], World.Cell.WALL, "shared cell still blocked by b")
	check_eq(world.prop_mask[shared], 1, "one prop left on it")
	check_eq(sim.scenery.named("a").size(), 0, "a gone")
	_run(sim, 6)
	check_eq(sim.scenery.named("branch").size(), 1, "added by an event")
	check(world.is_blocked(Vector2(600, 530)), "the branch blocks")
	check_eq(sim.scenery.named("b").size(), 0, "removed by point")
	check_eq(world.obstacles[shared], World.Cell.FREE, "freed once no prop covers it")
	check_eq(world.prop_mask[shared], 0, "mask cleared")

func test_unknown_type_is_skipped() -> void:
	var sim := Simulation.new(_config, _registry, 1)
	check(sim.scenery.add({"type": "no_such_prop", "center": [10, 10]}) == null, "unknown type -> null")
	check_eq(sim.scenery.props.size(), 0, "nothing added")
