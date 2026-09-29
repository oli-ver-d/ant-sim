extends TestCase
## M17d: a founding queen who lands first (nest_params "founding": {"landing"},
## Founding): she flies in on the surface, sheds two pairs of wings, walks
## the site, digs down and ends in her chamber with the nest still sealed;
## the underground waits for her, and her first workers dig the same shaft
## open later. Off (no "landing"), nothing changes.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

## A sealed leafcutter founding (as in leafcutter_life), with a quick
## landing (its params merged over the quick ones), or none: null, or
## "empty" for a "founding" key without "landing".
func _founding(landing: Variant = {}, seed_value: int = 3) -> Simulation:
	var params := {"initial_fungus": 12, "queen_reserve": 60, "open_entrance_at": 8, "chamber_capacity": 90,
		"brood_rate": 0.006, "digest_rate": 0.03, "garden_reserve": 0, "brood_reserve": 8,
		"underground": {"size": [1400, 1400], "open": false, "royal_radius": 40},
		"brood": {"lay_interval": 1.2, "egg": 30, "larva": 60, "pupa": 40, "callow": 5,
			"first_workers": 6, "brood_per_worker": 1.2, "initial": {"egg": 3, "larva": 3, "pupa": 3}}}
	if landing is Dictionary:
		var l: Dictionary = {"flight": 3, "shed": 2, "dig": 4, "loop_radius": 8}
		l.merge(landing, true)
		params["founding"] = {"landing": l}
	elif landing is String:
		params["founding"] = {}
	var data := {"seed": seed_value, "colonies": [{"species": "leafcutter", "nest": [540, 1060],
		"population": {"queen": 1, "minim": 4}, "nest_params": params}],
		"food": [{"type": "leaf", "pos": [610, 880], "rotation": -25, "length": 250, "width": 120}]}
	return ScenarioLoader.build(data, _registry, _config)

func _nest(sim: Simulation) -> ColonyNest:
	return sim.colonies[0].nest as ColonyNest

## Steps until the queen is home (or `limit` seconds); returns the time.
func _until_home(sim: Simulation, limit: float = 90.0) -> float:
	var f := _nest(sim).founding
	for t in roundi(limit * _config.tick_rate):
		sim.step()
		if f.is_home():
			return sim.time()
	return INF

func _wing_items(sim: Simulation) -> int:
	var n := 0
	for id: int in sim.items:
		if sim.items[id] is Wing:
			n += 1
	return n

func test_queen_starts_in_the_air() -> void:
	var sim := _founding()
	sim.step()
	var nest := _nest(sim)
	var q := nest.queen_ant
	check(q >= 0, "queen placed")
	check_eq(sim.layer[q], 0, "on the surface")
	check_eq(sim.state_id(q), "found_nest", "state")
	check(nest.founding.queen_altitude(sim) > 100.0, "high up: %.1f" % nest.founding.queen_altitude(sim))
	check_eq(sim.colonies[0].population, 1, "workers held back until she is home")
	var winged := nest.winged_ants(sim)
	check(winged.has(q) and int(winged[q].x) == 2, "two pairs of wings: %s" % [winged])
	check_eq(nest.entrance_sites()[0].radius, 0.0, "no entrance drawn yet")

func test_queen_lands_sheds_wings_and_goes_down_sealed() -> void:
	var sim := _founding()
	var nest := _nest(sim)
	var landed_at := Vector2.INF
	var dug_open := false
	var f := nest.founding
	for t in roundi(90.0 * _config.tick_rate):
		sim.step()
		if landed_at == Vector2.INF and f.phase == Founding.Phase.SHEDDING:
			landed_at = sim.pos[nest.queen_ant]
			check(f.queen_altitude(sim) < 0.01, "on the ground once landed")
		if f.phase == Founding.Phase.DIGGING and nest.entrance_sites()[0].open and nest.entrance_sites()[0].radius > 0.0:
			dug_open = true
		if f.is_home():
			break
	check(f.is_home(), "home within 90 s (at %.1f)" % sim.time())
	check(landed_at.distance_to(f.land) < 1.0, "landed at `land`: %s" % landed_at)
	check(dug_open, "a hole is drawn while she digs")
	var q := nest.queen_ant
	check_eq(sim.layer[q], nest.underground_layer, "underground")
	check_eq(sim.state_id(q), "queen", "state")
	check(sim.pos[q].distance_to(nest.queen_spot()) < 1.0, "in her niche")
	check_eq(_wing_items(sim), 2, "two shed pairs of wings on the ground")
	for id: int in sim.items:
		if sim.items[id] is Wing:
			check_eq(sim.items[id].layer, 0, "wings lie on the surface")
			check(sim.items[id].position.distance_to(landed_at) < 20.0, "where she shed them")
	check(nest.winged_ants(sim).is_empty(), "no wings left on her")
	check_eq(sim.colonies[0].population, 5, "queen + 4 minims")
	check(not nest.portal.open, "still sealed")
	check(not nest.entrance_sites()[0].open, "drawn refilled")
	check_eq(nest.spoil_items, f.spoil_pellets, "her spoil on the heap")

func test_underground_waits_for_the_queen() -> void:
	var sim := _founding()
	var nest := _nest(sim)
	var ages := nest.brood.age.duplicate()
	var reserve := (nest as FungusNest).queen_reserve
	for t in roundi(5.0 * _config.tick_rate):
		sim.step()
	check_eq(nest.brood.count(), 9, "initial brood")
	check_eq(nest.brood.age, ages, "brood doesn't develop without her")
	check_eq(nest.brood.eggs_laid, 0, "no eggs")
	check_eq((nest as FungusNest).queen_reserve, reserve, "no manuring yet")
	check(_until_home(sim) < INF, "home")
	for t in roundi(20.0 * _config.tick_rate):
		sim.step()
	check(nest.brood.eggs_laid > 0, "she lays once home")
	check((nest as FungusNest).queen_reserve < reserve, "and manures her garden")

func test_shed_wings_decay() -> void:
	var sim := _founding({"wing_life": 5})
	check(_until_home(sim) < INF, "home")
	for t in roundi(6.0 * _config.tick_rate):
		sim.step()
	check_eq(_wing_items(sim), 0, "gone after wing_life")

func test_sealed_nest_reopens_later() -> void:
	var sim := _founding()
	var nest := _nest(sim)
	check(_until_home(sim) < INF, "home")
	var opened := INF
	for t in roundi(300.0 * _config.tick_rate):
		sim.step()
		if nest.portal.open:
			opened = sim.time()
			break
	check(opened < INF, "the first workers dig the shaft open (at %.1f)" % opened)

func test_landing_is_deterministic() -> void:
	var a := _founding()
	var b := _founding()
	for t in roundi(40.0 * _config.tick_rate):
		a.step()
		b.step()
	check_eq(a.state_hash(), b.state_hash(), "same seed, same run")

## "founding" without "landing": the queen starts in her chamber, as before
## (existing scenarios' runs are unchanged: checked against their
## fingerprints before M17d, and by tests/test_native.gd).
func test_no_landing_unchanged() -> void:
	var plain := _founding(null)
	var empty := _founding("empty")
	check(_nest(empty).founding == null, "no landing without the key")
	for t in 300:
		plain.step()
		empty.step()
	check_eq(empty.state_hash(), plain.state_hash(), "hash")
	check_eq(plain.layer[_nest(plain).queen_ant], _nest(plain).underground_layer, "queen underground from the start")
