extends SceneTree
## Headless benchmark: runs a scenario and reports time per tick by section,
## plus a timeline of ants per behaviour state and deliveries, and with
## several layers (a nest underground) the ant cost per layer.
##
##   godot --headless --path . -s res://tests/bench.gd -- [scenario] [ticks] [ants_per_colony] [seed]
##
## If ants_per_colony is given, each colony is topped up to that many ants
## (castes by spawn ratio) before timing starts.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario: String = args[0] if args.size() > 0 else "basic_forage"
	var ticks: int = int(args[1]) if args.size() > 1 else 600
	var ants: int = int(args[2]) if args.size() > 2 else 0
	var seed_value: int = int(args[3]) if args.size() > 3 else -1

	var config := load("res://sim/default_config.tres") as SimConfig
	var sim := ScenarioLoader.load_simulation(scenario, Registry.create_default(), config, seed_value)
	for colony in sim.colonies:
		if ants > colony.population:
			colony.nest.spawn_ants(sim, ants - colony.population)

	var t0 := Time.get_ticks_usec()
	var t_last := t0
	for t in ticks:
		sim.step()
		if (t + 1) % (10 * config.tick_rate) == 0:
			var now := Time.get_ticks_usec()
			print("  t=%3ds %.2f ms/tick  %s" % [(t + 1) / config.tick_rate, (now - t_last) / 1000.0 / (10 * config.tick_rate), _summary(sim)])
			t_last = now
	var total_ms := (Time.get_ticks_usec() - t0) / 1000.0

	print("%s: %d ants, %d ticks, %d pheromone channels, %d layers" % [scenario, sim.ant_count, ticks, sim.pheromones.channel_count(), sim.layers.size()])
	print("  total      %.2f ms/tick" % (total_ms / ticks))
	for key in sim.profile_usec:
		print("  %-10s %.2f ms/tick" % [key, sim.profile_usec[key] / 1000.0 / ticks])
	# With several layers: ant updates per layer.
	for l in sim.profile_layer_usec.size():
		var n := maxi(1, sim.profile_layer_ant_ticks[l])
		print("  layer %d (%s): %.2f ms/tick, %.1f us per ant-tick, %d agents now" % [l, sim.layers[l].name,
				sim.profile_layer_usec[l] / 1000.0 / ticks, float(sim.profile_layer_usec[l]) / n, sim.layer_agents[l]])
	for colony in sim.colonies:
		if colony.abstract > 0:
			print("  colony %d: %d ants (%d agents, %d abstract)" % [colony.id, colony.total_population(), colony.population, colony.abstract])
	quit()

func _summary(sim: Simulation) -> String:
	var counts := {}
	for i in sim.high_water:
		if sim.alive[i] != 0:
			var s := sim.state_id(i)
			counts[s] = counts.get(s, 0) + 1
	var remaining := 0.0
	var total := 0.0
	for src in sim.food_sources:
		remaining += src.remaining_mass()
		total += src.remaining_mass() + src.taken_mass
	var delivered: PackedStringArray = []
	for colony in sim.colonies:
		delivered.append("%s %d" % [colony.species.id, colony.delivered_items])
	return "delivered %s  food left %3d%%  %s" % [", ".join(delivered), roundi(100.0 * remaining / maxf(total, 0.001)), counts]
