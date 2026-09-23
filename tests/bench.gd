extends SceneTree
## Headless benchmark: runs a scenario and reports time per tick by section,
## plus a timeline of ants per behaviour state and deliveries.
##
##   godot --headless --path . -s res://tests/bench.gd -- [scenario] [ticks] [ants_per_colony]
##
## If ants_per_colony is given, each colony is topped up to that many ants
## (castes by spawn ratio) before timing starts.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario: String = args[0] if args.size() > 0 else "basic_forage"
	var ticks: int = int(args[1]) if args.size() > 1 else 600
	var ants: int = int(args[2]) if args.size() > 2 else 0

	var config := load("res://sim/default_config.tres") as SimConfig
	var sim := ScenarioLoader.load_simulation(scenario, Registry.create_default(), config)
	for colony in sim.colonies:
		if ants > colony.population:
			colony.nest.spawn_ants(sim, ants - colony.population)

	var t0 := Time.get_ticks_usec()
	for t in ticks:
		sim.step()
		if (t + 1) % 600 == 0:
			print("  t=%3ds %s" % [(t + 1) / 60, _summary(sim)])
	var total_ms := (Time.get_ticks_usec() - t0) / 1000.0

	print("%s: %d ants, %d ticks, %d pheromone channels" % [scenario, sim.ant_count, ticks, sim.pheromones.channel_count()])
	print("  total      %.2f ms/tick" % (total_ms / ticks))
	for key in sim.profile_usec:
		print("  %-10s %.2f ms/tick" % [key, sim.profile_usec[key] / 1000.0 / ticks])
	quit()

func _summary(sim: Simulation) -> String:
	var counts := {}
	for i in sim.high_water:
		if sim.alive[i] != 0:
			var s := sim.state_id(i)
			counts[s] = counts.get(s, 0) + 1
	var delivered := 0
	for colony in sim.colonies:
		delivered += colony.delivered_items
	return "delivered %4d  %s" % [delivered, counts]
