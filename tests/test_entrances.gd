extends TestCase
## M15e: nest entrances on the surface: styles from nest params and species
## defaults, the entrance sites (sealed, open, extra) and how they widen with
## use (Portal.uses), cleared discs, the spoil heap's fan, the surface traffic
## that wears the ground (render only: it never changes a run), and new
## entrances kept off props.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

const DIGGING := {"species": "leafcutter", "nest": [540, 1100], "population": {"minim": 40, "media": 20},
	"params": {"hitchhiker_fraction": 0.0},
	"nest_params": {"underground": {"size": [800, 800], "carve": [{"center": [400, 400], "radius": 40}]}}}
const FOOD := {"type": "food_pile", "pos": [540, 800], "radius": 24, "amount": 400}

func _build(colonies: Array, extra: Dictionary = {}) -> Simulation:
	var data := {"seed": 5, "colonies": colonies, "food": [FOOD]}
	data.merge(extra, true)
	return ScenarioLoader.build(data, _registry, _config)

func test_styles_from_species_and_params() -> void:
	var sim := _build([
		{"species": "leafcutter", "nest": [300, 600], "population": {"media": 5}},
		{"species": "harvester", "nest": [700, 600], "population": {"minor": 5}},
		{"species": "leafcutter", "nest": [300, 1300], "nest_type": "basic_nest", "population": {"media": 5},
			"nest_params": {"entrance": {"style": "turret", "clear_radius": 50, "clears_plants": true}}},
		{"species": "leafcutter", "nest": [700, 1300], "nest_type": "basic_nest", "population": {"media": 5}},
		{"species": "leafcutter", "nest": [540, 1700], "nest_type": "basic_nest", "population": {"media": 5},
			"nest_params": {"entrance": {"style": "no_such_style"}}}])
	var nests := sim.colonies.map(func(c: Colony) -> NestType: return c.nest)
	check_eq(nests[0].entrance_style, "mound", "leafcutter nests are mounds")
	check_eq(nests[1].entrance_style, "crater", "harvester nests are craters")
	check(nests[1].clears_plants, "harvesters clear plants")
	check_eq(nests[1].clear_radius, (nests[1] as SeedNest).disc_radius, "cleared as far as the disc")
	check_eq(nests[2].entrance_style, "turret", "style from nest params")
	check_eq(nests[2].clear_radius, 50.0, "clear radius from nest params")
	check_eq(nests[3].entrance_style, "hole", "a basic nest is a hole")
	check(not nests[3].clears_plants, "and clears nothing")
	check_eq(nests[4].entrance_style, "hole", "unknown style falls back to a hole")

func test_sites_sealed_then_open() -> void:
	var sealed := DIGGING.duplicate(true)
	sealed["nest_params"]["underground"]["open"] = false
	var sim := _build([sealed])
	var nest := sim.colonies[0].nest
	var sites := nest.entrance_sites()
	check_eq(sites.size(), 1, "the sealed main entrance is listed")
	check(not sites[0].open, "sealed")
	check_eq(sites[0].position, nest.entrance_position(), "at the entrance")
	check_eq(EntranceRenderer.style_of(nest, sites[0]), "hole", "a sealed mound is drawn as a plug")
	nest.portal.open = true
	check(nest.entrance_sites()[0].open, "open once dug")
	check_eq(EntranceRenderer.style_of(nest, nest.entrance_sites()[0]), "mound", "then in its style")
	# An extra entrance shows only once it's open, smaller than the main one.
	var extra := nest.add_entrance(sim, nest.entrance_position() + Vector2(160, 0), nest.portal.pos_b + Vector2(160, 0), 8.0)
	check_eq(nest.entrance_sites().size(), 1, "closed extra entrance not drawn")
	extra.open = true
	sites = nest.entrance_sites()
	check_eq(sites.size(), 2, "open extra entrance drawn")
	check(not sites[1].main and sites[1].index == 1, "extra entrance is heap 1")
	check(sites[1].radius < sites[0].radius, "extra entrance starts smaller")

func test_entrance_widens_with_use() -> void:
	var sim := _build([DIGGING])
	var nest := sim.colonies[0].nest
	check(is_equal_approx(nest.entrance_radius(0, true), nest.radius * 0.85), "main opens at 85%")
	var last := 0.0
	for uses: int in [0, 500, 2000, 8000, 50000]:
		var r := nest.entrance_radius(uses, true)
		check(r > last, "wider after %d uses" % uses)
		last = r
	check(last <= nest.radius * 1.2 + 1e-4, "main tops out at 120%")
	check(nest.entrance_radius(50000, false) <= nest.radius + 1e-4, "extra tops out at 100%")
	# Ants coming out of the nest count as uses.
	for t in 300:
		sim.step()
	check(nest.portal.uses > 0, "ants went through (%d)" % nest.portal.uses)
	check_eq(nest.entrance_sites()[0].uses, nest.portal.uses, "site reports the portal's uses")

func test_cleared_disc_grows_with_the_colony() -> void:
	var small := _build([{"species": "harvester", "nest": [540, 1100], "population": {"minor": 4}}])
	var big := _build([{"species": "harvester", "nest": [540, 1100], "population": {"minor": 900}}])
	var rs := small.colonies[0].nest.cleared_radius(small)
	var rb := big.colonies[0].nest.cleared_radius(big)
	check(rs > 0.0 and rb > rs, "wider for a bigger colony (%.1f, %.1f)" % [rs, rb])
	check(rb <= big.colonies[0].nest.clear_radius + 1e-4, "at most the full radius")
	var leaf := _build([{"species": "leafcutter", "nest": [540, 1100], "population": {"media": 900}}])
	check_eq(leaf.colonies[0].nest.cleared_radius(leaf), 0.0, "no disc for a nest that doesn't clear one")
	var discs := GroundCoverRenderer.cleared_discs(big)
	check_eq(discs.size(), 1, "one cleared disc for the ground cover")
	# Decals inside the disc fade out, those outside keep their alpha.
	var buffer := PackedFloat32Array()
	for at: Vector2 in [Vector2(540, 1100), Vector2(540, 1100 + rb * 2.0)]:
		buffer.append_array([1, 0, 0, at.x, 0, 1, 0, at.y, 1, 1, 1, 1, 0, 0, 5, 0])
	var faded := GroundCoverRenderer.clear_discs(buffer, discs)
	check_eq(faded[11], 0.0, "decal in the disc cleared")
	check_eq(faded[GroundCoverRenderer.STRIDE + 11], 1.0, "decal outside kept")
	# Plants go right inside the disc (a canopy clear spot with w = 1).
	var cleared := 0
	for s in CanopyRenderer.clear_spots(big):
		if s.w > 0.5:
			cleared += 1
			check(is_equal_approx(s.z, rb), "canopy cleared as far as the disc")
	check_eq(cleared, 1, "one cleared canopy spot")

func test_surface_traffic_leaves_the_run() -> void:
	var plain := _build([DIGGING])
	var worn := _build([DIGGING])
	worn.layers[0].enable_traffic(WornGroundRenderer.HALF_LIFE, worn.dt)
	for t in 240:
		plain.step()
		worn.step()
	check(worn.layers[0].traffic.at(worn.colonies[0].nest.entrance_position()) > 0.0, "traffic counted at the entrance")
	check_eq(worn.state_hash(), plain.state_hash(), "same run with the surface traffic counted")

func test_spoil_heap_is_a_fan_facing_out() -> void:
	var shape := SpoilHeapRenderer.HeapShape.new()
	shape.out = Vector2.RIGHT
	var rng := RandomNumberGenerator.new()
	var sx := 0.0
	var sy := 0.0
	var bent := 0
	var n := 2000
	for k in n:
		rng.seed = 29 + k * 104729
		var p := SpoilHeapRenderer.crumb_position(k, rng, shape)
		sx += p.x * p.x
		sy += p.y * p.y
		if absf(p.y) > SpoilHeapRenderer._radius(k) * 0.8 and p.x < 0.0:
			bent += 1
	check(sy > sx * 2.0, "wider across than along the way out")
	check(bent > 0, "the ends bend back toward the entrance")
	# Same crumb, same place: the heap grows by accretion.
	rng.seed = 29 + 7 * 104729
	var a := SpoilHeapRenderer.crumb_position(7, rng, shape)
	rng.seed = 29 + 7 * 104729
	check_eq(SpoilHeapRenderer.crumb_position(7, rng, shape), a, "deterministic")
	# With a rim to spill toward, some crumbs lie on the way back to it.
	shape.spill_to = Vector2(-60, 0)
	var spilled := 0
	for k in 500:
		rng.seed = 29 + k * 104729
		if SpoilHeapRenderer.crumb_position(k, rng, shape).x < -25.0:
			spilled += 1
	check(spilled > 20, "crumbs spill toward the rim (%d)" % spilled)

func test_prop_near() -> void:
	var sim := Simulation.new(_config, _registry, 3)
	check(not sim.world.prop_near(Vector2(400, 400), 50.0), "no props at all")
	sim.scenery.add({"type": "rock", "center": [400, 400], "radius": 30})
	check(sim.world.prop_near(Vector2(400, 400), 5.0), "on the rock")
	check(sim.world.prop_near(Vector2(460, 400), 40.0), "rock within reach")
	check(not sim.world.prop_near(Vector2(600, 400), 40.0), "far from it")

func test_renderer_draws_every_site() -> void:
	var sim := _build([DIGGING])
	var nest := sim.colonies[0].nest
	var view := EntranceRenderer.new()
	view.bind(sim, nest)
	view._process(0.0)
	check_eq(view.get_child_count(), 1, "one quad for the main entrance")
	var quad := view.get_child(0) as ColorRect
	var reach := nest.entrance_sites()[0].reach("mound")
	check((quad.position + quad.size * 0.5).distance_to(nest.entrance_position()) < 0.01, "centred on the opening")
	check(is_equal_approx(quad.size.x, reach * 2.0), "as wide as the style reaches")
	var extra := nest.add_entrance(sim, nest.entrance_position() + Vector2(160, 0), nest.portal.pos_b + Vector2(160, 0), 8.0)
	extra.open = true
	view._process(0.0)
	check_eq(view.get_child_count(), 2, "a quad for the new entrance")
	check((view.get_child(1) as ColorRect).visible, "shown")
	extra.open = false
	view._process(0.0)
	check(not (view.get_child(1) as ColorRect).visible, "hidden once closed")
	view.free()
