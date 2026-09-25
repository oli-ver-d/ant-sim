extends SceneTree
## Headless probe of a nest that digs: runs a scenario and every `every`
## simulated seconds prints the colony's size, chambers dug, galleries,
## highways widened and bypasses, open entrances, nav fields, and sim cost
## per tick (for tuning and for comparing underground cell sizes).
##
##   godot --headless --path . -s res://tests/nest_probe.gd -- colony_founding [seconds] [every] [cell_size]
##
## cell_size (optional) overrides the underground layer's cell size.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario: String = args[0] if args.size() > 0 else "colony_founding"
	var seconds := float(args[1]) if args.size() > 1 else 7200.0
	var every := float(args[2]) if args.size() > 2 else 300.0
	var config := load("res://sim/default_config.tres") as SimConfig
	var data := ScenarioLoader.load_data(scenario)
	if args.size() > 3:
		for c: Dictionary in data["colonies"]:
			c["nest_params"]["underground"]["cell_size"] = int(args[3])
	var sim := ScenarioLoader.build(data, Registry.create_default(), config)
	var nest := sim.colonies[0].nest
	var ticks := roundi(seconds * config.tick_rate)
	var per := roundi(every * config.tick_rate)
	var t0 := Time.get_ticks_usec()
	var t_last := t0
	var prof_last := sim.profile_usec.duplicate()
	for t in ticks:
		sim.step()
		if (t + 1) % per == 0:
			var now := Time.get_ticks_usec()
			var open := 0
			for p in nest.extra_portals:
				open += 1 if p.open else 0
			var line := "t=%5ds %6.2f ms/tick  ants %5d" % [roundi(sim.time()), (now - t_last) / 1000.0 / per,
					sim.colonies[0].total_population()]
			if nest is ColonyNest:
				var cn := nest as ColonyNest
				var layout := cn.chambers_layout
				line += "  chambers %2d/%2d  galleries %2d  links %d" % [layout.dug_count(), layout.count(),
						layout.galleries.size(), layout.links.size()]
				line += "  brood %3d  food %6.1f  space %.2f" % [cn.brood.count(), cn.food_stock(), cn.space_pressure()]
			if nest.highways != null:
				line += "  widened %d  bypasses %d" % [nest.highways.widened, nest.highways.bypasses]
			line += "  entrances %d/%d  nav fields %d  dug %d cells" % [1 + open, 1 + nest.extra_portals.size(),
					sim.layers[nest.underground_layer].nav().fields.size(), sim.layers[nest.underground_layer].world.dug_cells]
			# Where the time went: nests (planning, gardens, brood), ants, pheromones.
			line += "  [nests %.1f ants %.1f pher %.1f ms]" % [(sim.profile_usec["nests"] - prof_last["nests"]) / 1000.0 / per,
					(sim.profile_usec["ants"] - prof_last["ants"]) / 1000.0 / per, (sim.profile_usec["pheromones"] - prof_last["pheromones"]) / 1000.0 / per]
			prof_last = sim.profile_usec.duplicate()
			print(line)
			t_last = now
	print("%s: %.2f ms/tick over %d ticks, memory %.0f MB" % [scenario, (Time.get_ticks_usec() - t0) / 1000.0 / ticks,
			ticks, OS.get_static_memory_usage() / 1048576.0])
	quit()
