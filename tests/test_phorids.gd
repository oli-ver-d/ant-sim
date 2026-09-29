extends TestCase
## M17f: phorid flies (nest_params "phorids", PhoridFlies): drawn only. They
## dive at carriers of leaf fragments, hit those without a hitchhiking minim
## and veer off guarded ones, and never touch the simulation.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

## trunk_trail (busy leaf line with hitchhikers), with `phorids` params (null: none).
func _sim(phorids: Variant, seed_value: int = 3) -> Simulation:
	var data := ScenarioLoader.load_data("trunk_trail")
	data["colonies"][0]["nest_params"] = {"phorids": phorids} if phorids is Dictionary else {}
	return ScenarioLoader.build(data, _registry, _config, seed_value)

func _flies(sim: Simulation) -> PhoridFlies:
	var flies := PhoridFlies.new()
	var nest := sim.colonies[0].nest as FungusNest
	flies.setup(nest.phorids, 0, nest.entrance_position())
	return flies

## Steps `seconds`, moving the flies after every tick (as the renderer does per frame).
func _run(sim: Simulation, flies: PhoridFlies, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()
		if flies != null:
			flies.update(sim, sim.time())

func test_flies_hit_unguarded_carriers_and_veer_off_guarded() -> void:
	var sim := _sim({"count": 8})
	var flies := _flies(sim)
	_run(sim, flies, 150.0)
	check(flies.active_count() > 0, "flies about: %d" % flies.active_count())
	check(flies.hits > 0, "carriers without riders hit: %d" % flies.hits)
	check(flies.veered > 0, "dives at guarded carriers broken off: %d" % flies.veered)
	check_eq(flies.hits_guarded, 0, "no guarded carrier hit")

func test_flies_stay_near_carriers() -> void:
	var sim := _sim({"count": 6})
	var flies := _flies(sim)
	_run(sim, flies, 120.0)
	var near := 0
	for f in flies.count:
		if flies.mode[f] == PhoridFlies.Mode.AWAY:
			continue
		for id: int in sim.carried_items:
			var item: Item = sim.items[id]
			if item.layer == 0 and item.carrier >= 0 and flies.pos[f].distance_to(sim.pos[item.carrier]) < 80.0:
				near += 1
				break
	check(near > 0 and near == flies.active_count(), "active flies by a carrier: %d of %d" % [near, flies.active_count()])

func test_flies_change_no_hash() -> void:
	var plain := _sim(null)
	_run(plain, null, 60.0)
	var sim := _sim({"count": 8})
	_run(sim, _flies(sim), 60.0)
	check_eq(sim.state_hash(), plain.state_hash(), "same hash with flies")

func test_flies_are_deterministic() -> void:
	var a := _sim({"count": 5})
	var fa := _flies(a)
	_run(a, fa, 60.0)
	var b := _sim({"count": 5})
	var fb := _flies(b)
	_run(b, fb, 60.0)
	check_eq(fa.pos, fb.pos, "same fly positions")
	check_eq(fa.hits, fb.hits, "same hits")

func test_off_without_params() -> void:
	var sim := _sim(null)
	check(( sim.colonies[0].nest as FungusNest).phorids.is_empty(), "no phorid params")
	var r := PhoridRenderer.new()
	r.bind(sim, sim.colonies[0].nest)
	check(r.flies == null, "renderer has no flies")
	r.free()
