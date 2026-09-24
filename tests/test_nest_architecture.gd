extends TestCase
## M13b: the leafcutter nest's architecture (FungusChambers): lobed,
## irregular chambers with alcoves, a hierarchy of galleries that chambers
## hang off, stubs, cross-links making loops; gardens and brood in them.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

## An established nest with `chambers` garden chambers dug out at the start.
func _nest_sim(chambers: int, seed_value: int = 7) -> Simulation:
	var data := {"seed": seed_value, "colonies": [{"species": "leafcutter", "nest": [540, 1000],
		"population": {"queen": 1, "minim": 30, "media": 20},
		"nest_params": {"initial_fungus": 200, "initial_chambers": chambers, "max_chambers": 60,
			"underground": {"size": [1400, 1400], "royal_radius": 40},
			"brood": {"lay_interval": 6, "initial": {"egg": 6, "larva": 8, "pupa": 6}}}}]}
	return ScenarioLoader.build(data, _registry, _config)

func _layout(sim: Simulation) -> FungusChambers:
	return (sim.colonies[0].nest as FungusNest).chambers_layout

func test_chambers_are_irregular_lobed_blobs() -> void:
	var layout := _layout(_nest_sim(16))
	var w := layout.world
	check(layout.count() >= 14, "chambers placed (%d)" % layout.count())
	var irregular := 0
	var alcoves := 0
	for c in layout.list:
		if c.kind != FungusChambers.Kind.GARDEN:
			continue
		check(c.lobes.size() >= 10, "chamber %d has 2+ lobes" % c.index)
		# Area against the circle through its furthest cell from the centre.
		var far := 0.0
		for cell in c.cells:
			far = maxf(far, w.cell_center(cell).distance_to(c.centre))
		var fill := c.cells.size() * w.cell_size * w.cell_size / (PI * far * far)
		if fill < 0.8:
			irregular += 1
		alcoves += c.alcoves.size()
	check(irregular >= (layout.count() - 1) * 3 / 4, "most chambers far from round (%d)" % irregular)
	check(alcoves >= 3, "some chambers have alcoves (%d)" % alcoves)
	var royal := layout.royal()
	check_eq(royal.alcoves.size(), 2, "the royal chamber: the queen's niche and a pupae alcove")
	var mean := 0.0
	for c in layout.list:
		mean += c.cells.size()
	mean /= layout.count()
	check(royal.cells.size() > mean * 0.9, "the royal chamber is large (%d cells, mean %.0f)" % [royal.cells.size(), mean])

func test_chambers_hang_off_branching_galleries() -> void:
	var layout := _layout(_nest_sim(16))
	var levels := {}
	for g in layout.galleries:
		levels[g.level] = levels.get(g.level, 0) + 1
	check(levels.get(FungusChambers.Level.MAIN, 0) >= 2, "main galleries (%s)" % levels)
	check(levels.get(FungusChambers.Level.SECONDARY, 0) >= 3, "secondary tunnels (%s)" % levels)
	var branch_off_tunnel := 0
	for g in layout.galleries:
		if g.parent >= 0:
			branch_off_tunnel += 1
			# It starts on its parent gallery.
			var p := layout.galleries[g.parent]
			check(FungusChambers._polyline_distance(p.points, g.points[0]) < 2.0, "gallery %d starts on its parent" % g.index)
	check(branch_off_tunnel >= 3, "tunnels branch off tunnels (%d)" % branch_off_tunnel)
	for c in layout.list:
		if c.kind == FungusChambers.Kind.GARDEN:
			check(c.gallery >= 0, "chamber %d hangs off a gallery" % c.index)
			var g := layout.galleries[c.gallery]
			check(FungusChambers._polyline_distance(g.points, c.tunnel[0]) < 2.0, "its capillary leaves from the gallery")
	# Widths: mains wider than secondaries, capillaries narrowest; tapering.
	for g in layout.galleries:
		check(g.radii[g.radii.size() - 1] <= g.radii[0] + 1e-4, "gallery %d tapers" % g.index)
		if g.level == FungusChambers.Level.MAIN and g.parent < 0:
			check(g.radii[0] > layout.tunnel_radius * 1.2, "main galleries are wide")

func test_cross_links_make_loops() -> void:
	var sim := _nest_sim(16)
	var layout := _layout(sim)
	check(layout.has_loop(), "a cross-link once there are %d chambers" % layout.count())
	var nav := sim.layers[1].nav()
	nav.update()
	var shortcut := 0
	for link in layout.links:
		var a := layout.list[link.x]
		var b := layout.list[link.y]
		var walk := nav.distance(a.nav_field, b.centre)
		var tree := layout._tree_distance(a.gallery, a.attach_s, b.gallery, b.attach_s)
		if walk < tree * 0.8:
			shortcut += 1
	check(shortcut >= 1, "a link is a shortcut to walk (%d)" % shortcut)

func test_chambers_do_not_overlap() -> void:
	var layout := _layout(_nest_sim(20, 3))
	var w := layout.world
	var bad := 0
	for a in layout.list:
		for b in layout.list:
			if a == b or a.centre.distance_to(b.centre) > 400.0:
				continue
			for cell in b.cells:
				if DigShape.ellipses_distance(a.lobes, w.cell_center(cell)) < 0.0:
					bad += 1
	check_eq(bad, 0, "no chamber's cells inside another chamber")
	# At least a few units of soil between any two chambers.
	var touching := 0
	for c in layout.list:
		for cell in c.cells:
			for nb: int in [cell - 1, cell + 1, cell - w.width, cell + w.width]:
				var k := layout.chamber_at(w.cell_center(nb))
				if k >= 0 and k != c.index:
					touching += 1
	check_eq(touching, 0, "no two chambers touch")

func test_layout_is_deterministic() -> void:
	var a := _layout(_nest_sim(10))
	var b := _layout(_nest_sim(10))
	check_eq(a.count(), b.count(), "same chambers")
	check_eq(a.galleries.size(), b.galleries.size(), "same galleries")
	for k in mini(a.galleries.size(), b.galleries.size()):
		check_eq(a.galleries[k].points, b.galleries[k].points, "gallery %d the same" % k)
	for k in mini(a.count(), b.count()):
		check_eq(a.list[k].lobes, b.list[k].lobes, "chamber %d the same" % k)

## Gardens fill irregular chambers from their floor; brood lies in chambers
## (pupae in an alcove); the colony works as before.
func test_gardens_and_brood_in_irregular_chambers() -> void:
	var sim := _nest_sim(4)
	var nest := sim.colonies[0].nest as FungusNest
	var layout := nest.chambers_layout
	var w := layout.world
	for c in layout.list:
		if c.dug and c.kind == FungusChambers.Kind.GARDEN:
			check(nest.garden.chamber_count[c.index] > 100, "chamber %d has a garden (%d cells)" % [c.index, nest.garden.chamber_count[c.index]])
			var off := 0
			for gc in nest.garden.cells.slice(nest.garden.chamber_first[c.index], nest.garden.chamber_first[c.index] + nest.garden.chamber_count[c.index]):
				var at := nest.garden.cell_center(gc)
				if layout.chamber_at(at) != c.index or w.is_blocked(at) or layout.in_alcove(c.index, at):
					off += 1
			check_eq(off, 0, "chamber %d: garden only on its open floor" % c.index)
	check_eq(layout.chamber_at(nest.queen_spot()), 0, "the queen in the royal chamber")
	check(layout.in_alcove(0, nest.queen_spot()), "in her niche")
	var k := nest.brood_chamber()
	var pupae := nest.pile_centre(LeafcutterBrood.Pile.PUPAE)
	check_eq(layout.chamber_at(pupae), k, "pupae in the brood chamber")
	if not layout.list[k].alcoves.is_empty():
		check(layout.in_alcove(k, pupae), "pupae kept in an alcove")
	for t in 90 * _config.tick_rate:
		sim.step()
	var blocked := 0
	for i in sim.high_water:
		if sim.alive[i] != 0 and not sim.in_transit(i) and sim.world_of(i).is_blocked(sim.pos[i]):
			blocked += 1
	check_eq(blocked, 0, "no ant inside soil")
	var brood := nest.brood
	var outside := 0
	for b in brood.count():
		if brood.carrier[b] < 0 and w.is_blocked(brood.pos[b]):
			outside += 1
	check_eq(outside, 0, "no brood inside soil")
	check(nest.ants_raised > 0, "brood raised (%d)" % nest.ants_raised)
	check(nest.fed_mass > 0.0, "larvae fed")

## The whole colony_founding run (about 30 minutes headless): run with
## tools/test.sh --long test_colony_founding_grows.
func test_colony_founding_grows() -> void:
	if not OS.get_cmdline_user_args().has("--long"):
		print("    (long: pass --long to run)")
		return
	var sim := ScenarioLoader.load_simulation("colony_founding", _registry, _config)
	var colony := sim.colonies[0]
	var nest := colony.nest as FungusNest
	for t in 7000 * _config.tick_rate:
		sim.step()
	check(colony.total_population() >= 3000, "grew to thousands (%d)" % colony.total_population())
	check(nest.chambers_layout.dug_count() >= 20, "chambers dug (%d)" % nest.chambers_layout.dug_count())
	check(nest.chambers_layout.has_loop(), "with loops")
