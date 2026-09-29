extends TestCase
## M15h: scatter presets (Scatter): the same seed gives the same scatter, the
## ground steers what grows where, nothing lands in keep-clear zones (entrances,
## cleared discs, food, paths, room for middens and planned entrances), and
## every food source stays reachable from its colony.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _data(scatter: Array, seed_value: int = 3, colony: Dictionary = {}) -> Dictionary:
	var col := colony if not colony.is_empty() else \
			{"species": "leafcutter", "nest": [540, 1300], "nest_type": "basic_nest", "population": {"media": 40}}
	return {"seed": seed_value,
		"colonies": [col],
		"food": [
			{"type": "food_pile", "pos": [540, 500], "radius": 26, "amount": 400},
			{"type": "food_pile", "pos": [180, 1700], "radius": 20, "amount": 200},
			{"type": "food_pile", "pos": [900, 1000], "radius": 20, "amount": 200},
		],
		"scenery": scatter}

func _build(scatter: Array, seed_value: int = 3, colony: Dictionary = {}) -> Simulation:
	return ScenarioLoader.build(_data(scatter, seed_value, colony), _registry, _config)

func test_same_seed_same_scatter() -> void:
	var scatter := [{"scatter": {"preset": "meadow"}}, {"scatter": {"preset": "rocky", "rect": [0, 0, 1080, 900]}}]
	var a := _build(scatter)
	var b := _build(scatter)
	check(a.scenery.props.size() > 100, "a meadow and a rocky patch (%d props)" % a.scenery.props.size())
	check_eq(a.scenery.props.size(), b.scenery.props.size(), "same count")
	for i in mini(a.scenery.props.size(), b.scenery.props.size()):
		check_eq(a.scenery.props[i].position, b.scenery.props[i].position, "prop %d position" % i)
		check_eq(a.scenery.props[i].outline, b.scenery.props[i].outline, "prop %d outline" % i)
	check_eq(a.world.obstacles, b.world.obstacles, "same footprints")
	var c := _build(scatter, 99)
	check(c.scenery.props[0].position != a.scenery.props[0].position, "another seed, another scatter")

func test_scatter_leaves_the_run_rng_alone() -> void:
	var plain := _build([])
	var scattered := _build([{"scatter": {"preset": "forest_floor"}}])
	check(scattered.scenery.props.size() > 20, "props placed")
	check_eq(scattered.rng.state, plain.rng.state, "Simulation.rng untouched by the scatter")

## "blocking": false places only canopy, so the run is the same as without it.
func test_canopy_only_scatter_keeps_the_run() -> void:
	var plain := _build([])
	var sim := _build([{"scatter": {"preset": "forest_floor", "blocking": false, "density": 2.0}}])
	check(sim.scenery.props.size() > 20, "props placed (%d)" % sim.scenery.props.size())
	for p in sim.scenery.props:
		check(p.type_id == "plant" or p.type_id == "grass", "only plants and grass (%s)" % p.type_id)
		check(not p.blocks, "nothing blocks")
	check_eq(sim.world.obstacles, plain.world.obstacles, "no footprints")
	check(not sim.world.prop_near(Vector2(540, 960), 2000.0), "no prop cells")
	for t in 150:
		plain.step()
		sim.step()
	check_eq(sim.state_hash(), plain.state_hash(), "same state hash")

func test_every_preset_places_its_types() -> void:
	for preset: String in Scatter.PRESETS:
		var sim := _build([{"scatter": {"preset": preset, "density": 2.0}}])
		var types: Dictionary[String, bool] = {}
		for p in sim.scenery.props:
			types[p.type_id] = true
		check(sim.scenery.props.size() >= 20, "%s places props (%d)" % [preset, sim.scenery.props.size()])
		check(types.size() >= 2, "%s mixes types (%s)" % [preset, types.keys()])

func test_ground_steers_the_mix() -> void:
	var data := _data([{"scatter": {"preset": "meadow"}}])
	data["ground"] = {"base": "moss", "regions": [{"material": "sand", "shape": "rect", "rect": [0, 960, 1080, 960]}]}
	var sim := ScenarioLoader.build(data, _registry, _config)
	var moss := 0
	var sand := 0
	for p in sim.scenery.props:
		if p.type_id == "rock":
			continue
		if p.position.y < 960.0:
			moss += 1
		else:
			sand += 1
	check(moss > sand * 2, "plants favour moss over sand (%d vs %d)" % [moss, sand])

func test_nothing_in_keep_clear_zones() -> void:
	var s := {"preset": "meadow", "density": 2.0,
			"clear": [{"shape": "polyline", "points": [[540, 1300], [900, 1000]], "width": 60}]}
	var rocky := s.duplicate()
	rocky["preset"] = "rocky"
	var sim := _build([{"scatter": s}, {"scatter": rocky}])
	var zones := Scatter.keep_clear_zones(sim, s, Scatter.KEEP_CLEAR)
	check(zones.size() >= 6, "zones for the nest, food and path (%d)" % zones.size())
	var hard_hits := 0
	var reserve_hits := 0
	for p in sim.scenery.props:
		for z in zones:
			if z.hard:
				for pt in p.outline + p.canopy + PackedVector2Array([p.position]):
					if z.distance(pt) < -2.0:
						hard_hits += 1
			elif p.blocks:
				for c in p.cells:
					@warning_ignore("integer_division")
					var at := Vector2((c % sim.world.width + 0.5), (c / sim.world.width + 0.5)) * sim.world.cell_size
					if z.distance(at) < -sim.world.cell_size:
						reserve_hits += 1
	check_eq(hard_hits, 0, "prop points inside hard zones")
	check_eq(reserve_hits, 0, "blocking cells inside reserve zones")
	var nest := sim.colonies[0].nest
	for site in nest.entrance_sites():
		check(not sim.world.prop_near(site.position, site.reach(nest.entrance_style)), "entrance clear of props")
	for src in sim.food_sources:
		check(not sim.world.prop_near(src.position, 30.0), "food at %s clear of props" % src.position)

func _check_reachable(seed_value: int) -> void:
	var sim := _build([{"scatter": {"preset": "rocky", "density": 3.0}}, {"scatter": {"preset": "forest_floor", "density": 2.0}}], seed_value)
	var reach := Scatter._reachability(sim, [])
	var targets: PackedByteArray = reach[0]["targets"]
	check_eq(targets.size(), 4, "three foods and the edge")
	for t in targets.size():
		check_eq(targets[t], 1, "seed %d: target %d reachable" % [seed_value, t])

func test_food_reachable_seed_3() -> void:
	_check_reachable(3)

func test_food_reachable_seed_17() -> void:
	_check_reachable(17)

## A wall across the world with one gap, food beyond it; a prop plugging the
## gap is dropped (a plant keeps its canopy).
func _plugged(type: String) -> Array:
	var data := _data([])
	data["obstacles"] = [{"shape": "polyline", "points": [[0, 800], [980, 800]], "width": 16}]
	var sim := ScenarioLoader.build(data, _registry, _config)
	var baseline := Scatter._reachability(sim, [])
	var p := Scatter.Placed.new()
	p.data = {"type": "rock", "center": [1030, 800], "radius": 60, "flat": 1.0} if type == "rock" \
			else {"type": "plant", "kind": "rosette", "center": [1030, 800], "radius": 70, "stem": 60}
	p.prop = sim.scenery.add(p.data)
	p.at = p.prop.position
	p.reach = 70.0
	p.block = 60.0
	var cut := Scatter._reachability(sim, [p])
	check_eq((cut[0]["targets"] as PackedByteArray)[0], 0, "%s cuts the far food off" % type)
	var result := Scatter.Result.new()
	result.placed.append(p.prop)
	var dropped := Scatter._keep_connected(sim, [p], baseline, result)
	check_eq(dropped, 1, "%s dropped" % type)
	check(result.dropped_bounds.size() == 1 and result.dropped_bounds[0].has_point(Vector2(1030, 800)),
			"the dropped prop's bounds are reported")
	var after := Scatter._reachability(sim, [])
	check_eq((after[0]["targets"] as PackedByteArray)[0], 1, "food reachable again")
	check(not sim.world.is_blocked(Vector2(1030, 800)), "gap free again")
	return [sim, result]

func test_blocking_rock_that_cuts_off_food_is_dropped() -> void:
	var out := _plugged("rock")
	var result: Scatter.Result = out[1]
	check(result.placed.is_empty(), "rock gone")

func test_blocking_stem_that_cuts_off_food_keeps_its_canopy() -> void:
	var out := _plugged("plant")
	var sim: Simulation = out[0]
	var result: Scatter.Result = out[1]
	check_eq(result.placed.size(), 1, "plant kept")
	if result.placed.size() == 1:
		check(not result.placed[0].blocks and not result.placed[0].canopy.is_empty(), "canopy only")
		check(sim.scenery.props.has(result.placed[0]), "still in the scenery")

func test_room_kept_for_planned_entrances_and_middens() -> void:
	var colony := {"species": "leafcutter", "nest": [540, 1300], "population": {"minim": 30, "media": 30},
			"nest_params": {"entrances": {"at": [100], "spacing": 150},
				"underground": {"size": [1000, 1000], "carve": [{"center": [500, 500], "radius": 40}]}}}
	var sim := _build([{"scatter": {"preset": "rocky", "density": 3.0}}], 5, colony)
	var nest := sim.colonies[0].nest as ColonyNest
	check(nest != null and nest.underground_layer >= 0, "a digging nest")
	var room := maxf(nest.entrance_spacing * 2.2, nest.midden_distance.y)
	var main := nest.entrance_position()
	var blocking := 0
	var inside := 0
	for p in sim.scenery.props:
		if not p.blocks:
			continue
		blocking += 1
		for c in p.cells:
			@warning_ignore("integer_division")
			var at := Vector2((c % sim.world.width + 0.5), (c / sim.world.width + 0.5)) * sim.world.cell_size
			if at.distance_to(main) < room:
				inside += 1
				break
	check(blocking > 10, "rocks placed (%d)" % blocking)
	check_eq(inside, 0, "blocking props inside the reserved ring")
	check(not sim.world.prop_near(nest.spoil_position(), 40.0), "spoil heap clear")

func test_scatter_in_an_event() -> void:
	var data := _data([])
	data["events"] = [{"t": 0.1, "type": "add_scenery", "scenery": {"scatter": {"preset": "sandy", "density": 2.0}}}]
	var sim := ScenarioLoader.build(data, _registry, _config)
	check(sim.scenery.props.is_empty(), "nothing before the event")
	for t in 6:
		sim.step()
	check(sim.scenery.props.size() > 10, "scattered by the event (%d)" % sim.scenery.props.size())
