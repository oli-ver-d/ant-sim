extends SceneTree
## Prints a fingerprint of a run that doesn't depend on the order behaviours
## are registered in (state names instead of indices): for checking that a
## refactor leaves runs unchanged.
##
##   godot --headless --path . -s res://tests/fingerprint_probe.gd -- <scenario> <ticks> [--no-native]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario: String = args[0]
	var ticks := int(args[1])
	var config := load("res://sim/default_config.tres") as SimConfig
	var sim := ScenarioLoader.build(ScenarioLoader.load_data(scenario), Registry.create_default(), config)
	if args.has("--no-native"):
		sim.use_native = false
	for t in ticks:
		sim.step()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(PackedInt64Array([sim.tick_count, sim.ant_count, sim.high_water, sim.rng.state]).to_byte_array())
	ctx.update(sim.alive.slice(0, sim.high_water))
	var names := PackedStringArray()
	for i in sim.high_water:
		names.append(sim.state_id(i) if sim.alive[i] != 0 else "")
	ctx.update(",".join(names).to_utf8_buffer())
	ctx.update(sim.pos.slice(0, sim.high_water).to_byte_array())
	ctx.update(sim.heading.slice(0, sim.high_water).to_byte_array())
	ctx.update(sim.carried.slice(0, sim.high_water).to_byte_array())
	ctx.update(sim.layer.slice(0, sim.high_water))
	for l in sim.layers.size():
		ctx.update(sim.layers[l].world.obstacles)
		ctx.update(sim.layers[l].world.soil.to_byte_array())
		ctx.update(sim.layers[l].pheromones.values.to_byte_array())
	for colony in sim.colonies:
		ctx.update(PackedFloat64Array([colony.delivered_items, colony.delivered_mass, colony.population,
				colony.total_population()]).to_byte_array())
		var nest: Variant = colony.nest
		if "brood" in nest and nest.brood != null:
			ctx.update(PackedInt64Array([nest.brood.count(), nest.brood.eggs_laid, nest.brood.emerged]).to_byte_array())
		if "fungus" in nest:
			ctx.update(PackedFloat64Array([nest.fungus, nest.substrate, nest.waste]).to_byte_array())
	print("FINGERPRINT %s %d %s ants=%d" % [scenario, ticks, ctx.finish().hex_encode(), sim.ant_count])
	quit()
