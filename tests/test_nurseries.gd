extends TestCase
## M17c2: brood nurseries. Once a nest with brood care is big enough
## (nest_params "nurseries"), eggs, larvae and pupae each get a chamber of
## their own; nurses carry brood there and move it on as it changes stage.
## Both species' nests (core ColonyNest), and none before the threshold.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

## An established leafcutter nest (open, chambers dug) with plenty of workers.
func _leafcutter(nurseries: Dictionary, seed_value: int = 5) -> Simulation:
	var data := {"seed": seed_value, "colonies": [{"species": "leafcutter", "nest": [540, 1000],
		"population": {"queen": 1, "minim": 40, "media": 20},
		"nest_params": {"initial_fungus": 600, "initial_chambers": 2, "max_chambers": 4,
			"underground": {"size": [1000, 1000], "royal_radius": 40},
			"nurseries": nurseries,
			"brood": {"lay_interval": 5, "egg": 30, "larva": 40, "pupa": 30, "callow": 4,
				"initial": {"egg": 6, "larva": 8, "pupa": 6}}}}]}
	return ScenarioLoader.build(data, _registry, _config)

## An established harvester nest with a big seed cache.
func _harvester(nurseries: Dictionary, seed_value: int = 3) -> Simulation:
	var data := {"seed": seed_value, "colonies": [{"species": "harvester", "nest_type": "granary_nest", "nest": [540, 1000],
		"population": {"queen": 1, "minor": 50, "major": 5},
		"nest_params": {"initial_seeds": 150, "brood_reserve": 1, "ant_cost": 0.5, "initial_chambers": 2, "dig_fraction": 0.6,
			"max_chambers": 4, "underground": {"size": [900, 900]}, "nurseries": nurseries,
			"brood": {"lay_interval": 5, "egg": 30, "larva": 40, "pupa": 30, "callow": 4,
				"initial": {"egg": 6, "larva": 8, "pupa": 6}}}}]}
	return ScenarioLoader.build(data, _registry, _config)

## Steps until the nest has its nurseries (or `limit` seconds); returns the
## seconds it took (INF if none).
func _until_nurseries(sim: Simulation, limit: float) -> float:
	var nest := sim.colonies[0].nest as ColonyNest
	for t in roundi(limit * _config.tick_rate):
		sim.step()
		if nest.has_nurseries():
			return sim.time()
	return INF

func _run(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

## Brood (not carried) per stage lying in that stage's nursery, and in all.
func _in_nurseries(nest: ColonyNest) -> Vector2i:
	var b := nest.brood
	var home := 0
	var lying := 0
	for k in b.count():
		if b.carrier[k] >= 0 or b.pile[k] == Brood.Pile.QUEEN:
			continue
		lying += 1
		var s := mini(b.stage[k], Brood.Stage.PUPA)
		if nest.chambers_layout.chamber_at(b.pos[k]) == nest.nursery[s]:
			home += 1
	return Vector2i(home, lying)

func _check_nurseries(sim: Simulation, what: String) -> void:
	var nest := sim.colonies[0].nest as ColonyNest
	var at := _until_nurseries(sim, 900.0)
	check(at < INF, "%s: nurseries in use (at %.0f s)" % [what, at])
	if at == INF:
		return
	var layout := nest.chambers_layout
	var seen := {}
	for s in 3:
		var k := nest.nursery[s]
		check(k > 0 and layout.list[k].dug and layout.list[k].kind == NestChambers.Kind.CHAMBER, "%s: stage %d has a dug chamber" % [what, s])
		check(nest.is_nursery(k), "%s: chamber %d is a nursery" % [what, k])
		seen[k] = true
		check_eq(layout.chamber_at(nest.pile_centre(Brood.Pile.EGGS + s)), k, "%s: stage %d's pile is in its nursery" % [what, s])
	check_eq(seen.size(), 3, "%s: three distinct nurseries" % what)
	# Eggs nearer the queen than the other two nurseries.
	var royal := layout.royal().centre
	var d_egg := layout.list[nest.nursery[0]].centre.distance_to(royal)
	check(d_egg <= layout.list[nest.nursery[1]].centre.distance_to(royal) + 1e-3
			or d_egg <= layout.list[nest.nursery[2]].centre.distance_to(royal) + 1e-3, "%s: eggs near the queen" % what)
	var v := nest.nursery_version
	_run(sim, 150.0)
	var n := _in_nurseries(nest)
	check(n.y > 0, "%s: brood lying about (%d)" % [what, n.y])
	check(n.x >= n.y * 0.7, "%s: most brood in its stage's nursery (%d of %d)" % [what, n.x, n.y])
	check_eq(nest.nursery_version, v, "%s: nurseries stay put" % what)

func test_leafcutter_nest_gets_nurseries() -> void:
	var sim := _leafcutter({"population": 40, "chambers": 3})
	_check_nurseries(sim, "leafcutter")
	var nest := sim.colonies[0].nest as FungusNest
	for s in 3:
		check(not nest.garden.has_chamber(nest.nursery[s]), "no garden in nursery %d" % s)

func test_harvester_nest_gets_nurseries() -> void:
	var sim := _harvester({"carve": true})
	_check_nurseries(sim, "harvester")
	var nest := sim.colonies[0].nest as GranaryNest
	for s in 3:
		check(not nest.is_granary(nest.nursery[s]), "nursery %d isn't a granary" % s)
	var seeds := 0
	for s in nest.seed_chamber.size():
		if nest.is_nursery(nest.seed_chamber[s]):
			seeds += 1
	check_eq(seeds, 0, "no seeds stored in the nurseries")

func test_no_nurseries_below_the_threshold() -> void:
	var sim := _leafcutter({"population": 5000, "chambers": 3})
	var nest := sim.colonies[0].nest as ColonyNest
	_run(sim, 300.0)
	check(not nest.has_nurseries(), "no nurseries")
	check(nest.nursery_planned.is_empty(), "none planned")
	# Brood stays in the royal chamber and the first chamber, as before.
	var b := nest.brood
	for k in b.count():
		if b.carrier[k] < 0:
			var c := nest.chambers_layout.chamber_at(b.pos[k])
			check(c == 0 or c == nest.brood_chamber() or b.pile[k] == Brood.Pile.LOOSE, "brood %d in the royal or brood chamber (%d)" % [k, c])

## Brood put down in a gallery (its carrier died or was called away) goes to
## its pile: nurses can't find their way to brood lying in a gallery.
func test_brood_dropped_in_a_gallery_goes_to_its_pile() -> void:
	var sim := _leafcutter({"carve": true})
	var nest := sim.colonies[0].nest as ColonyNest
	check(_until_nurseries(sim, 900.0) < INF, "nurseries in use")
	var layout := nest.chambers_layout
	var gallery := Vector2.INF
	for y in range(0, 1000, 4):
		for x in range(0, 1000, 4):
			var at := Vector2(x, y)
			if not layout.world.is_blocked(at) and layout.chamber_at(at) < 0:
				gallery = at
				break
		if gallery != Vector2.INF:
			break
	check(gallery != Vector2.INF, "a gallery cell")
	var b := nest.brood
	var k := -1
	for j in b.count():
		if b.carrier[j] < 0 and b.claimed[j] < 0 and b.stage[j] == Brood.Stage.PUPA:
			k = j
			break
	check(k >= 0, "a pupa")
	if k < 0 or gallery == Vector2.INF:
		return
	b.pick_up(k, 0)
	b.put_down(k, gallery, nest)
	check(b.is_home(k, nest), "dropped in a gallery, it lies in its pile")
	check_eq(layout.chamber_at(b.pos[k]), nest.nursery[Brood.Stage.PUPA], "in the pupae's nursery")

## Brood that changes stage is carried on to the next nursery.
func test_brood_moves_on_when_it_changes_stage() -> void:
	var sim := _leafcutter({"carve": true})
	var nest := sim.colonies[0].nest as ColonyNest
	check(_until_nurseries(sim, 900.0) < INF, "nurseries in use")
	_run(sim, 60.0)
	# Follow a larva lying in the larvae's nursery until it has pupated.
	var b := nest.brood
	var pick := -1
	for k in b.count():
		if b.stage[k] == Brood.Stage.LARVA and b.carrier[k] < 0 \
				and nest.chambers_layout.chamber_at(b.pos[k]) == nest.nursery[Brood.Stage.LARVA]:
			if pick < 0 or b.age[k] > b.age[b.index_of(pick)]:
				pick = b.id[k]
	check(pick >= 0, "a larva in its nursery")
	if pick < 0:
		return
	var moved := false
	for t in roundi(200.0 * _config.tick_rate):
		sim.step()
		var k := b.index_of(pick)
		if k < 0:
			break
		if b.stage[k] >= Brood.Stage.PUPA and b.carrier[k] < 0 \
				and nest.chambers_layout.chamber_at(b.pos[k]) == nest.nursery[Brood.Stage.PUPA]:
			moved = true
			break
	check(moved, "the larva, now a pupa, lies in the pupae's nursery")
