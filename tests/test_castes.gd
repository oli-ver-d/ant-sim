extends TestCase
## M6: debris / clutter, the generic riding mechanism, caste state overrides,
## and the leafcutter castes (hitchhiking minims, debris-clearing majors).

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _sim() -> Simulation:
	var sim := Simulation.new(_config, _registry, 1)
	sim.add_colony("leafcutter", Vector2(540, 1400))
	return sim

func test_caste_state_overrides() -> void:
	var sim := _sim()
	var colony := sim.colonies[0]
	var follow := sim.behaviour_index["follow_trail"]
	var major := colony.species.caste_index(&"major")
	var media := colony.species.caste_index(&"media")
	check_eq(colony.params_for(major, follow).get("on_arrive"), "patrol_trail", "major override")
	check_eq(colony.params_for(media, follow).get("on_arrive"), "explore", "media uses species params")
	check(colony.params_for(major, follow).has("follow_channel"), "override merged over species params")

func test_debris_clutter_bookkeeping() -> void:
	var sim := _sim()
	var twig := Debris.create(sim, {"type": "twig", "pos": [300, 300], "length": 40})
	var cell := sim.world.cell_at(Vector2(300, 300))
	check(sim.world.clutter[cell] > 0, "debris clutters its cells")
	check(sim.ground_clutter().has(twig.id), "listed as ground clutter")
	var ant := sim.spawn_ant(sim.colonies[0], 2, Vector2(300, 300), 0.0)
	sim.pick_up(ant, twig)
	check_eq(sim.world.clutter[cell], 0, "picked up: cells clear")
	check(not sim.ground_clutter().has(twig.id), "no longer on the ground")
	sim.pos[ant] = Vector2(600, 600)
	sim.drop_item(ant)
	check(sim.world.clutter[sim.world.cell_at(Vector2(600, 600))] > 0, "dropped: new cells cluttered")

func test_clutter_slows_ants() -> void:
	var sim := _sim()
	Debris.create(sim, {"type": "pebble", "pos": [300, 300], "radius": 6})
	var a := sim.spawn_ant(sim.colonies[0], 1, Vector2(300, 300), 0.0)
	var b := sim.spawn_ant(sim.colonies[0], 1, Vector2(700, 700), 0.0)
	var pa := sim.pos[a]
	var pb := sim.pos[b]
	sim.world.ensure_near_blocked(_config.avoid_lookahead)
	Steering.move(sim, a, 0.0, 40.0, sim.dt)
	Steering.move(sim, b, 0.0, 40.0, sim.dt)
	var da := sim.pos[a].distance_to(pa)
	var db := sim.pos[b].distance_to(pb)
	check(absf(da - db * _config.clutter_slowdown) < 0.01, "on clutter: %.3f vs %.3f x %.2f" % [da, db, _config.clutter_slowdown])

func test_riders_follow_and_dismount_on_delivery() -> void:
	var sim := _sim()
	var colony := sim.colonies[0]
	var carrier := sim.spawn_ant(colony, 1, Vector2(540, 1300), -PI / 2)
	var rider := sim.spawn_ant(colony, 0, Vector2(540, 1300), 0.0)
	var item := sim.create_item("leaf_fragment", 1.0)
	item.source_id = 99
	sim.pick_up(carrier, item)
	sim.change_state(carrier, "carry_home")
	sim.mount(rider, item, Vector2(1, 0))
	sim.change_state(rider, "hitchhike")
	for t in 20:
		sim.step()
	var expected := sim.pos[carrier] + Vector2.from_angle(sim.heading[carrier]) * (sim.caste_of(carrier).size * Item.HOLD_OFFSET + 1.0)
	check(sim.pos[rider].distance_to(expected) < 0.01, "rider sits on the item")
	# Walk the carrier home; delivery must dismount the rider.
	sim.pos[carrier] = colony.nest.entrance_position()
	for t in 3:
		sim.step()
	check_eq(sim.riding[rider], -1, "rider dismounted at the nest")
	check(sim.state_id(rider) != "hitchhike", "rider left the hitchhike state")

## Integration: in trunk_trail, debris dropped on the trail gets cleared by
## majors, and minims hitchhike on fragments.
func test_trunk_trail_castes_at_work() -> void:
	var sim := ScenarioLoader.load_simulation("trunk_trail", _registry, _config)
	var food := sim.colonies[0].channels[&"food"]
	var dropped: Dictionary = {}
	var max_riding := 0
	for t in 125 * _config.tick_rate:
		sim.step()
		if t == 105 * _config.tick_rate:
			for id in sim.ground_clutter():
				if sim.pheromones.sample(food, sim.items[id].position) >= 0.35:
					dropped[id] = sim.items[id].position
		if t % 30 == 0:
			var riding := 0
			for i in sim.high_water:
				if sim.alive[i] != 0 and sim.riding[i] >= 0:
					riding += 1
			max_riding = maxi(max_riding, riding)
	check(dropped.size() >= 3, "debris landed on the trail (%d pieces)" % dropped.size())
	var cleared := 0
	for id: int in dropped:
		if sim.items[id].position.distance_to(dropped[id]) > 20.0:
			cleared += 1
	check(cleared >= dropped.size() - 1, "majors moved %d of %d pieces off the trail" % [cleared, dropped.size()])
	check(max_riding >= 3, "minims hitchhiked (max %d riding at once)" % max_riding)
	check(absf(SimChecks.mass_error(sim)) < 0.001, "food mass conserved")
	check_eq(SimChecks.ants_in_obstacles(sim), 0, "no ant in an obstacle")
