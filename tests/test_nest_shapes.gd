extends TestCase
## M13a: dig job shapes (paths, blobs of lobes, cell sets) with rough
## outlines, soil texture (clay, roots, stones), ragged digging, routed
## tunnels, and chambers looked up by cell.

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

## Digs every cell of `job` with the plan's own bites; returns the cells freed.
func _dig_out(plan: ExcavationPlan, job: ExcavationPlan.Job) -> Dictionary:
	var freed := {}
	var log_start := plan.world.dig_log.size()
	for c in job.cells:
		var guard := 0
		while plan.world.is_soil(c) and guard < 50:
			plan.dig_cell(job, c, 1.0)
			guard += 1
	for k in range(log_start, plan.world.dig_log.size()):
		var c := plan.world.dig_log[k]
		if not plan.world.is_soil(c):
			freed[c] = true
	return freed

## Signed distance from p to a path (radius interpolated along each segment).
func _path_distance(pts: PackedVector2Array, radii: PackedFloat32Array, p: Vector2) -> float:
	var best := INF
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var seg := b - a
		var t := clampf((p - a).dot(seg) / seg.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + seg * t) - lerpf(radii[k], radii[k + 1], t))
	return best

func test_path_job_digs_its_cells_within_the_overdig() -> void:
	var sim := _sim()
	var plan := sim.colonies[0].nest.excavation_plan()
	var w := plan.world
	plan.overdig = 5.0
	plan.rough_seed = 3
	var pts := PackedVector2Array([Vector2(208, 200), Vector2(250, 180), Vector2(300, 200), Vector2(330, 250)])
	var radii := PackedFloat32Array([9.0, 8.0, 6.0, 4.0])
	var job := plan.add_path_job("gallery", pts[0], pts, radii)
	check(job.cells.size() > 80, "a tunnel's worth of cells (%d)" % job.cells.size())
	var inside := 0
	var core := 0
	for c in range(w.obstacles.size()):
		var d := _path_distance(pts, radii, w.cell_center(c))
		if d <= -5.0 / 3.0 - 0.01 and w.is_soil(c):
			core += 1
			if job.cells.has(c):
				inside += 1
	check_eq(inside, core, "every cell well inside the path is in the job")
	var worst := -INF
	for c in job.cells:
		worst = maxf(worst, _path_distance(pts, radii, w.cell_center(c)))
	check(worst <= 5.0 + 1e-3, "no cell beyond the overdig (%.2f)" % worst)
	check(worst > 1.0, "the outline is rough (reaches %.2f past the path)" % worst)
	var freed := _dig_out(plan, job)
	check(job.done, "dug out")
	check_eq(freed.size(), job.cells.size(), "exactly its cells freed")
	for c in job.cells:
		if not freed.has(c):
			check(false, "cell %d of the job not freed" % c)
			break
	# Progress ranks: the far end ranks highest, so tunnels advance along it.
	var shape := job.shape
	var near_end := shape.rank[shape.cells.find(w.cell_at(pts[3]))]
	var near_start := shape.rank[shape.cells.find(w.cell_at(pts[0] + Vector2(4, 0)))]
	check(near_end > near_start + 100.0, "rank grows along the path (%.0f -> %.0f)" % [near_start, near_end])

func test_blob_job_is_irregular_and_digs_its_cells() -> void:
	var sim := _sim()
	var plan := sim.colonies[0].nest.excavation_plan()
	var w := plan.world
	var lobes := PackedFloat32Array([280, 200, 44, 20, 0.0, 262, 185, 16, 12, 0.8, 305, 212, 14, 10, 0.0])
	var job := plan.add_blob_job("cave", Vector2(210, 200), lobes, Vector2(240, 200))
	var n := job.cells.size()
	check(n > 150, "a chamber's worth of cells (%d)" % n)
	# Not a circle: the widest extent differs clearly between directions.
	var box := job.shape.box
	check(absi(box.size.x - box.size.y) >= 3, "irregular extent (%s)" % box.size)
	var freed := _dig_out(plan, job)
	check_eq(freed.size(), n, "exactly its cells freed")
	# Ranked outward from the way in.
	var r_in := job.shape.rank[job.shape.cells.find(w.cell_at(Vector2(244, 200)))]
	var r_far := job.shape.rank[job.shape.cells.find(w.cell_at(Vector2(312, 212)))]
	check(r_in > r_far, "opens up from where it is entered")

func test_cell_set_job() -> void:
	var sim := _sim()
	var plan := sim.colonies[0].nest.excavation_plan()
	var w := plan.world
	var cells: PackedInt32Array = []
	for x in range(55, 70):
		cells.append(w.cell_at(Vector2(x * 4 + 2, 120)))
		cells.append(w.cell_at(Vector2(x * 4 + 2, 124)))
	var job := plan.add_shape_job("slot", Vector2(220, 122), DigShape.from_cells(w, cells, Vector2(220, 122)))
	check_eq(job.cells.size(), cells.size(), "all its soil cells")
	check_eq(_dig_out(plan, job).size(), cells.size(), "and exactly those dug")

func test_capsule_jobs_are_unchanged_without_overdig() -> void:
	var sim := _sim()
	var plan := sim.colonies[0].nest.excavation_plan()
	var w := plan.world
	var job := plan.add_job("tunnel", Vector2(210, 200), Vector2(210, 200), Vector2(300, 240), 7.0)
	var want: PackedInt32Array = []
	for c in w.cells_in_segment(Vector2(210, 200), Vector2(300, 240), 7.0):
		if w.is_soil(c):
			want.append(c)
	var got := job.cells.duplicate()
	got.sort()
	want.sort()
	check_eq(got, want, "the capsule's cells, exactly")

func test_soil_texture() -> void:
	var sim := _sim({"texture": {"clay": 0.2, "stones": 10}})
	var w := sim.layers[1].world
	var kinds := [0, 0, 0, 0]
	for k in w.soil_kind:
		kinds[k] += 1
	var n := float(w.soil_kind.size())
	check(kinds[World.Soil.CLAY] > n * 0.05, "clay patches (%d cells)" % kinds[World.Soil.CLAY])
	check(kinds[World.Soil.ROOT] > 0, "roots (%d cells)" % kinds[World.Soil.ROOT])
	check(kinds[World.Soil.STONE] > 0, "stones (%d cells)" % kinds[World.Soil.STONE])
	check(not w.is_blocked(Vector2(200, 200)), "the shaft kept clear")
	var clay := w.soil_kind.find(World.Soil.CLAY)
	var plain := w.soil_kind.find(World.Soil.PLAIN)
	check(w.hardness_at(clay) > w.hardness_at(plain) * 1.5, "clay is harder")
	var stone := w.soil_kind.find(World.Soil.STONE)
	check(w.hardness_at(stone) == INF and not w.dig(stone, 100.0), "stones can't be dug")
	# Same seed, same soil; another seed, other soil.
	var again := _sim({"texture": {"clay": 0.2, "stones": 10}})
	check_eq(again.layers[1].world.soil_kind, w.soil_kind, "deterministic")
	var other := Simulation.new(_config, _registry, 2)
	other.add_colony("digger", Vector2(540, 1200), {"underground": {"size": [400, 400], "shaft": [200, 200],
			"texture": {"clay": 0.2, "stones": 10}}})
	check(other.layers[1].world.soil_kind != w.soil_kind, "another seed, other soil")

## A job never claims stones: a chamber dug around one keeps it as a pillar.
func test_jobs_leave_stones() -> void:
	var sim := _sim()
	var plan := sim.colonies[0].nest.excavation_plan()
	var w := plan.world
	var stone := w.cell_at(Vector2(260, 200))
	w.soil_kind.resize(w.obstacles.size())
	w._make_stone(stone)
	var job := plan.add_blob_job("cave", Vector2(210, 200), PackedFloat32Array([260, 200, 30, 30, 0.0]), Vector2(232, 200))
	check(not job.cells.has(stone), "the stone isn't part of the job")
	_dig_out(plan, job)
	check(job.done and w.is_blocked(w.cell_center(stone)), "dug around it")

func test_route_avoids_stones_and_cavities() -> void:
	var sim := _sim()
	var l := sim.layers[1]
	var w := l.world
	# A wall of stone across the way with one gap, and a chamber off to one side.
	w.soil_kind.resize(w.obstacles.size())
	for y in range(100, 300, 4):
		if y < 236 or y > 252:
			w._make_stone(w.cell_at(Vector2(260, y)))
	w.carve_segment(Vector2(300, 150), Vector2(300, 150), 20)
	var from := Vector2(210, 200)
	var to := Vector2(340, 200)
	var route := l.route(from, to, {"seed": 4, "clearance": 20.0})
	check(route.size() >= 3, "a route (%d points)" % route.size())
	check(route[0] == from and route[route.size() - 1] == to, "from end to end")
	var through_gap := false
	var worst_stone := INF
	var closest_cave := INF
	for k in route.size() - 1:
		for s in 9:
			var p := route[k].lerp(route[k + 1], s / 8.0)
			var c := w.cell_at(p)
			if w.obstacles[c] == World.Cell.WALL:
				worst_stone = 0.0
			if absf(p.x - 260.0) < 4.0:
				through_gap = through_gap or (p.y > 234 and p.y < 254)
			closest_cave = minf(closest_cave, p.distance_to(Vector2(300, 150)) - 20.0)
	check(worst_stone == INF, "never on a stone")
	check(through_gap, "through the gap in the stones")
	check(closest_cave > 8.0, "clear of the other chamber (%.1f)" % closest_cave)
	# Deterministic, and the meander noise makes routes wind.
	check_eq(l.route(from, to, {"seed": 4, "clearance": 20.0}), route, "same route again")
	var open := l.route(Vector2(20, 20), Vector2(380, 30), {"seed": 9, "meander": 2.0, "margin": 60.0})
	var dev := 0.0
	for p in open:
		dev = maxf(dev, absf(p.y - lerpf(20.0, 30.0, (p.x - 20.0) / 360.0)))
	check(dev > 4.0, "winds a little over open soil (%.1f)" % dev)

## Diggers bite the face unevenly (random but deterministic).
func test_ragged_digging_is_deterministic() -> void:
	var hashes: PackedStringArray = []
	for run in 2:
		var sim := _sim({"overdig": 4.0, "texture": {}, "plan": [{"name": "gallery", "path": [[204, 200], [260, 170], [320, 180]],
				"radii": [8, 7, 6], "diggers": 6}]})
		for n in 6:
			sim.change_state(sim.spawn_ant(sim.colonies[0], 0, Vector2(200, 200), 0.0, 1), "dig")
		for t in 90 * _config.tick_rate:
			sim.step()
		hashes.append(sim.state_hash())
		check(sim.colonies[0].nest.excavation_plan().remaining() < sim.colonies[0].nest.excavation_plan().jobs[0].cells.size(),
				"dug some of it")
	check_eq(hashes[0], hashes[1], "same run, same hash")

## Chambers are looked up by cell, and the sampling helpers stay inside.
func test_chamber_lookup_matches_shape() -> void:
	var sim := ScenarioLoader.load_simulation("res://tests/fixtures/scenarios/garden_demo.json", _default_registry, _config)
	var nest := sim.colonies[0].nest as FungusNest
	var layout := nest.chambers_layout
	var w := layout.world
	check(layout.count() >= 3, "chambers (%d)" % layout.count())
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for c in layout.list:
		var member := {}
		for cell in c.cells:
			member[cell] = true
		var bad := 0
		for cell in c.cells:
			if layout.chamber_at(w.cell_center(cell)) != c.index:
				bad += 1
		check_eq(bad, 0, "chamber %d: all its cells map to it" % c.index)
		for n in 200:
			var p := c.centre + Vector2(rng.randf_range(-80, 80), rng.randf_range(-80, 80))
			var cell := w.cell_at(p)
			if cell >= 0 and member.has(cell) != (layout.chamber_at(p) == c.index):
				bad += 1
		check_eq(bad, 0, "chamber %d: chamber_at agrees with its shape" % c.index)
		if c.dug:
			for n in 20:
				var q := layout.random_point(c.index, rng, 2)
				if layout.chamber_at(q) != c.index or w.is_blocked(q):
					bad += 1
				var f := layout.floor_point(c.index, rng)
				if layout.chamber_at(f) != c.index or layout.depth_at(f) < 1:
					bad += 1
			check_eq(bad, 0, "chamber %d: sampled points inside and open" % c.index)
			var edge := layout.point_in(c.index, 0.7, 1.0)
			check(layout.chamber_at(layout.point_in(c.index, 0.7, 0.5)) == c.index, "point_in inside")
			check(layout.chamber_at(edge + Vector2.from_angle(0.7) * w.cell_size * 1.5) != c.index, "point_in 1 at its edge")
	# The queen and brood places are inside their chambers.
	check_eq(layout.chamber_at(nest.queen_spot()), 0, "queen in the royal chamber")
	check(layout.chamber_at(nest.pile_centre(LeafcutterBrood.Pile.LARVAE)) >= 0, "larvae in a chamber")
	check(nest.garden.chamber_count[0] > 20, "a founding garden")
