extends TestCase
## M13c: traffic maps, busy tunnels widened into highways (and bypassed),
## lanes in wide tunnels, and nests with several entrances.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry: Registry = load("res://tests/test_layers.gd")._make_registry()
var _default_registry := Registry.create_default()

## A "digger" colony (see test_layers) on a 400x400 underground.
func _sim(under: Dictionary = {}) -> Simulation:
	var u := {"size": [400, 400], "shaft": [200, 200], "shaft_radius": 10}
	u.merge(under, true)
	var sim := Simulation.new(_config, _registry, 1)
	sim.add_colony("digger", Vector2(540, 1200), {"underground": u})
	return sim

func _run_seconds(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

func test_traffic_accumulates_and_decays() -> void:
	var sim := _sim()
	var l := sim.layers[1]
	var tm := l.enable_traffic(10.0, sim.dt)
	check(sim.layers[0].traffic == null, "only layers that ask count traffic")
	var at := Vector2(200, 200)
	for n in 3:
		sim.spawn_ant(sim.colonies[0], 0, at, 0.0, 1)
	for n in 20:
		sim._sample_traffic()
	var want := 3 * 20 * TrafficMap.SAMPLE_EVERY * sim.dt
	check(absf(tm.at(at) - want) < 1e-3, "3 ants x 20 samples (%.3f vs %.3f)" % [tm.at(at), want])
	check_eq(tm.at(Vector2(100, 100)), 0.0, "nothing where nobody is")
	for t in roundi(10.0 / sim.dt):
		tm.decay()
	check(absf(tm.at(at) - want * 0.5) < 1e-3, "halves in a half-life (%.3f)" % tm.at(at))
	# Renormalising keeps the values.
	for t in roundi(200.0 / sim.dt):
		tm.decay()
	check(tm.scale >= 1e-4, "scale renormalised (%f)" % tm.scale)
	check(absf(tm.at(at) - want * pow(0.5, 21.0)) < 1e-6, "still right after renormalising")
	# Stepping samples every SAMPLE_EVERY ticks.

	for t in TrafficMap.SAMPLE_EVERY:
		sim.step()
	check(tm.version > 0, "the map is updated as the sim runs")

## A tunnel whose traffic stays high is widened into a highway; a quiet one
## is left alone; at full width and still congested it gets a bypass.
func test_sustained_traffic_widens_tunnels() -> void:
	var sim := _sim({"highways": {"check_every": 1.0, "threshold": 0.5, "sustain": 2, "max_radius": 12.0,
			"bypass": 2.0, "section": 60}})
	var nest := sim.colonies[0].nest
	var hw := nest.highways
	check(hw != null, "highways on")
	check(sim.layers[0].traffic != null and sim.layers[1].traffic != null, "traffic counted on both layers")
	var w := sim.layers[1].world
	var busy := PackedVector2Array([Vector2(210, 200), Vector2(260, 190), Vector2(320, 200)])
	var quiet := PackedVector2Array([Vector2(200, 210), Vector2(200, 300)])
	w.carve_path(busy, PackedFloat32Array([6, 6, 6]))
	w.carve_path(quiet, PackedFloat32Array([6, 6]))
	hw.watch(busy, PackedFloat32Array([6, 6, 6]))
	hw.watch(quiet, PackedFloat32Array([6, 6]))
	var tm := hw.traffic
	# Busy: a steady stream along the first tunnel.
	for t in roundi(6.0 / sim.dt):
		for k in 20:
			var p := busy[0].lerp(busy[2], k / 19.0)
			tm.values[w.cell_at(p)] += 0.2 / tm.scale
		sim.step()
	check(hw.widened >= 1, "the busy tunnel widened (%d)" % hw.widened)
	var names: PackedStringArray = []
	for job in nest.plan.jobs:
		names.append(job.name)
	check(names.has("highway0"), "planned as a highway job (%s)" % names)
	var job: ExcavationPlan.Job = null
	for j in nest.plan.jobs:
		if j.name == "highway0":
			job = j
	if job != null:
		var widest := 0.0
		for r in job.shape.radii:
			widest = maxf(widest, r)
		check(widest > 7.5 and widest <= 12.0, "wider, up to max_radius (%.1f)" % widest)
		check(job.shape.points.size() > busy.size(), "smoothed (more, gentler points)")
		# Nobody quiet got widened: every widening lies along the busy tunnel.
		for p in job.shape.points:
			check(
					NestChambers._polyline_distance(busy, p) < 12.0, "along the busy tunnel")
	for s in hw.sections:
		if NestChambers._polyline_distance(quiet, s.points[0]) < 1.0 and NestChambers._polyline_distance(quiet, s.points[s.points.size() - 1]) < 1.0:
			check_eq(s.level, 0, "the quiet tunnel stays narrow")
	# Dig the widening out at once, then keep the traffic up: at full width
	# it ends up with a bypass.
	for j in nest.plan.jobs:
		if not j.done:
			for c in j.cells:
				while w.is_soil(c):
					nest.plan.dig_cell(j, c, 5.0)
	for t in roundi(20.0 / sim.dt):
		for k in 20:
			var p := busy[0].lerp(busy[2], k / 19.0)
			tm.values[w.cell_at(p)] += 0.5 / tm.scale
		sim.step()
		for j in nest.plan.jobs:
			if not j.done and j.name.begins_with("highway"):
				for c in j.cells:
					while w.is_soil(c):
						nest.plan.dig_cell(j, c, 5.0)
	check(hw.bypasses >= 1, "a congested highway gets a bypass (%d widened)" % hw.widened)

## In a wide tunnel ants going one way keep to one side and ants coming the
## other way to the other.
func test_lanes_separate_the_two_directions() -> void:
	var sim := _sim()
	var l := sim.layers[1]
	l.lanes = 1.0
	l.world.carve_segment(Vector2(40, 200), Vector2(360, 200), 14.0)
	var nav := l.nav()
	var to_right := nav.set_target_point(&"east", Vector2(355, 200))
	var to_left := nav.set_target_point(&"west", Vector2(45, 200))
	var east: PackedInt32Array = []
	var west: PackedInt32Array = []
	for n in 16:
		east.append(sim.spawn_ant(sim.colonies[0], 0, Vector2(50 + n * 3, 200 + (n % 5 - 2) * 3), 0.0, 1))
		west.append(sim.spawn_ant(sim.colonies[0], 0, Vector2(350 - n * 3, 200 + (n % 5 - 2) * 3), PI, 1))
	var east_y := 0.0
	var west_y := 0.0
	var samples := 0
	for t in 300:
		for i in east:
			Travel.go(sim, i, 1, Vector2(355, 200), to_right, 30.0, sim.dt)
		for i in west:
			Travel.go(sim, i, 1, Vector2(45, 200), to_left, 30.0, sim.dt)
		if t > 150:
			for i in east:
				if absf(sim.pos[i].x - 200.0) < 110.0:
					east_y += sim.pos[i].y - 200.0
			for i in west:
				if absf(sim.pos[i].x - 200.0) < 110.0:
					west_y += sim.pos[i].y - 200.0
			samples += 1
	east_y /= samples * east.size()
	west_y /= samples * west.size()
	# Heading east (+x), right is +y (y points down); heading west, -y.
	check(east_y > 2.0, "eastbound keep to their right (%.1f)" % east_y)
	check(west_y < -2.0, "westbound keep to theirs (%.1f)" % west_y)
	check(east_y - west_y > 5.0, "two streams apart (%.1f)" % (east_y - west_y))
	# Without lanes they stay in the middle.
	l.lanes = 0.0
	var mid := 0.0
	for i in east:
		sim.pos[i] = Vector2(60, 200)
	for t in 200:
		for i in east:
			Travel.go(sim, i, 1, Vector2(355, 200), to_right, 30.0, sim.dt)
	for i in east:
		mid += sim.pos[i].y - 200.0
	check(absf(mid / east.size()) < 2.0, "no lanes: down the middle (%.1f)" % (mid / east.size()))

## The lane bias in a tunnel too narrow for two streams, or in a chamber, is off.
func test_no_lanes_in_narrow_tunnels_or_chambers() -> void:
	var sim := _sim()
	var w := sim.layers[1].world
	w.carve_segment(Vector2(40, 100), Vector2(360, 100), 5.0)
	w.carve_segment(Vector2(100, 300), Vector2(100, 300), 60.0)
	var aim := Vector2(210, 100)
	check_eq(Travel.lane_aim(w, Vector2(200, 100), aim, 1.0), aim, "narrow tunnel: no lane")
	check_eq(Travel.lane_aim(w, Vector2(100, 300), Vector2(110, 300), 1.0), Vector2(110, 300), "chamber: no lane")

## Past a population step the nest digs another entrance facing food, and
## ants go in and out through it.
func test_extra_entrances_open_and_are_used() -> void:
	var sim := ScenarioLoader.load_simulation("res://tests/fixtures/scenarios/highway_demo.json", _default_registry, _config)
	var nest := sim.colonies[0].nest as FungusNest
	var used := {}
	var opened_at := -1.0
	for t in 600 * _config.tick_rate:
		sim.step()
		if opened_at < 0.0 and not nest.extra_portals.is_empty() and nest.extra_portals[0].open:
			opened_at = sim.time()
		if opened_at > 0.0 and t % 10 == 0:
			for i in sim.high_water:
				if sim.alive[i] != 0 and sim.transit_until[i] != 0:
					used[sim.transit_portal[i]] = used.get(sim.transit_portal[i], 0) + 1
		# Ants start using it within a second or so of opening (the shaft
		# takes ~460 s to dig): 30 s shows both entrances in use.
		if opened_at > 0.0 and sim.time() > opened_at + 30.0:
			break
	check_eq(nest.extra_portals.size(), 1, "a second entrance planned at the population step")
	check(opened_at > 0.0, "dug open (at %.0f s)" % opened_at)
	if nest.extra_portals.is_empty():
		return
	var p := nest.extra_portals[0]
	check(p.pos_a.distance_to(nest.entrance_position()) >= 140.0, "spaced from the main entrance")
	check(used.get(p.id, 0) > 0 and used.get(nest.portal.id, 0) > 0, "ants use both entrances (%s)" % used)
	check_eq(nest.entrances().size(), 2, "two open entrances")
	check(nest.spoil_count(1) > 0 or nest.spoil_count(0) > 0, "spoil heaps")
	# The nearest entrance is used on the way home.
	check_eq(nest.nearest_entrance(p.pos_a + Vector2(5, 0)), p.pos_a, "nearest entrance")
	check(nest.is_at_nest(p.pos_a), "at the nest at either entrance")

func test_highways_are_deterministic() -> void:
	var hashes: PackedStringArray = []
	for run in 2:
		var sim := ScenarioLoader.load_simulation("res://tests/fixtures/scenarios/highway_demo.json", _default_registry, _config)
		for t in 45 * _config.tick_rate:
			sim.step()
		hashes.append(sim.state_hash())
	check_eq(hashes[0], hashes[1], "same run, same hash")
