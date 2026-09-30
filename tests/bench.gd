extends SceneTree
## Headless benchmark: runs a scenario and reports time per tick by section,
## plus a timeline of ants per behaviour state and deliveries, and with
## several layers (a nest underground) the ant cost per layer.
##
##   godot --headless --path . -s res://tests/bench.gd -- [scenario] [ticks] [ants_per_colony] [seed] [options]
##
## If ants_per_colony is given, each colony is topped up to that many ants
## (castes by spawn ratio) before timing starts. Options:
##   --by-state      µs per ant update for each behaviour state (native kernel and
##                   GDScript together; "(transit)" is portal transits), and the
##                   nest's own update split by part (Profiler keys)
##   --from=<s>      run <s> simulated seconds untimed first (bench a late colony
##                   without timing the whole run)
##   --load-times    time the scenario build by stage (each scatter on its own) and
##                   bake every scenery prop as the renderer would, by prop type
##   --no-native     GDScript ants only

func _initialize() -> void:
	var args: PackedStringArray = []
	var by_state := false
	var load_times := false
	var from_s := 0.0
	for a in OS.get_cmdline_user_args():
		if a == "--by-state":
			by_state = true
		elif a == "--load-times":
			load_times = true
		elif a.begins_with("--from="):
			from_s = float(a.get_slice("=", 1))
		elif not a.begins_with("--"):
			args.append(a)
	var scenario: String = args[0] if args.size() > 0 else "basic_forage"
	var ticks: int = int(args[1]) if args.size() > 1 else 600
	var ants: int = int(args[2]) if args.size() > 2 else 0
	var seed_value: int = int(args[3]) if args.size() > 3 else -1

	var config := load("res://sim/default_config.tres") as SimConfig
	Profiler.on = load_times
	var t_load := Time.get_ticks_usec()
	var p := Profiler.start()
	var registry := Registry.create_default()
	if load_times:
		CoreRenderers.register(registry)
	Profiler.stop("load: registry", p)
	var sim := ScenarioLoader.load_simulation(scenario, registry, config, seed_value)
	var load_ms := (Time.get_ticks_usec() - t_load) / 1000.0
	if load_times:
		_bake_props(sim)
		_print_load_times(scenario, load_ms)
	Profiler.on = false
	Profiler.reset()
	for colony in sim.colonies:
		if ants > colony.population:
			colony.nest.spawn_ants(sim, ants - colony.population)

	if from_s > 0.0:
		var skip := roundi(from_s * config.tick_rate)
		var t_skip := Time.get_ticks_usec()
		for t in skip:
			sim.step()
			if (t + 1) % (600 * config.tick_rate) == 0:
				print("  fast-forward t=%ds (%d agents)" % [(t + 1) / config.tick_rate, sim.ant_count])
		print("  fast-forwarded %.0f s in %.1f s" % [from_s, (Time.get_ticks_usec() - t_skip) / 1e6])
		for key in sim.profile_usec:
			sim.profile_usec[key] = 0
		sim.profile_layer_usec.fill(0)
		sim.profile_layer_ant_ticks.fill(0)

	if by_state:
		Profiler.on = true
		sim.set_state_profiling(true)
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
	if by_state:
		_print_by_state(sim, ticks)
	quit()

## Per behaviour state: ant updates per tick, µs per update and ms per tick,
## the costliest first; then the Profiler keys (nest parts, step sections).
func _print_by_state(sim: Simulation, ticks: int) -> void:
	var prof := sim.take_state_profile()
	var us: PackedFloat64Array = prof["usec"]
	var n: PackedInt64Array = prof["ticks"]
	var order: Array[int] = []
	for s in us.size():
		if n[s] > 0 or us[s] > 0.0:
			order.append(s)
	order.sort_custom(func(a: int, b: int) -> bool: return us[a] > us[b])
	var sum := 0.0
	print("  by state (%s):          ants/tick  us/update  ms/tick" % ("native + GDScript" if sim.kernel != null else "GDScript"))
	for s in order:
		var state_name := "(transit)" if s == Simulation.STATE_TRANSIT else String(sim.behaviour_ids[s])
		sum += us[s]
		print("    %-24s %9.1f %10.2f %8.3f" % [state_name, float(n[s]) / ticks, us[s] / maxi(1, n[s]), us[s] / 1000.0 / ticks])
	var ants_us: float = sim.profile_usec["ants"]
	print("    %-24s %9s %10s %8.3f  (%.0f%% of ants %.3f; the rest is the loop and kernel calls)" % [
			"sum of states", "", "", sum / 1000.0 / ticks, 100.0 * sum / maxf(ants_us, 1.0), ants_us / 1000.0 / ticks])
	print("  by part (Profiler):                calls/tick  ms/tick")
	for key in Profiler.ranked():
		print("    %-34s %8.2f %8.3f" % [key, float(Profiler.calls[key]) / ticks, Profiler.usec[key] / 1000.0 / ticks])
	sim.set_state_profiling(false)
	Profiler.on = false

## Bakes every scenery prop with its painter, as SceneryRenderer does on the
## first frame, timed by prop type.
func _bake_props(sim: Simulation) -> void:
	var painters := {}
	for prop in sim.scenery.props:
		if not painters.has(prop.type_id):
			var script: Script = sim.registry.renderers.get("prop:" + prop.type_id)
			painters[prop.type_id] = script.new() if script != null else null
		var painter: Object = painters[prop.type_id]
		if painter == null:
			continue
		var p := Profiler.start()
		var b := PropBaker.bake(prop, painter, float(sim.world.cell_size), sim.ground)
		if not b.is_empty():
			ImageTexture.create_from_image(b["body"])
			ImageTexture.create_from_image(b["shadow"])
		Profiler.stop("bake: %s" % prop.type_id, p)

func _print_load_times(scenario: String, load_ms: float) -> void:
	print("%s load: %.0f ms to build (stages below; bakes are extra)" % [scenario, load_ms])
	for key in Profiler.ranked():
		var calls: int = Profiler.calls[key]
		print("  %-40s %8.1f ms%s" % [key, Profiler.usec[key] / 1000.0, "  (%d, %.1f ms each)" % [calls, Profiler.usec[key] / 1000.0 / calls] if calls > 1 else ""])

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
