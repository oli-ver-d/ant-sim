extends SceneTree
## Middens over a run: sites, deposits, mass received / on deposits / in
## the stain / rotted, every `every` simulated seconds.
##   godot --headless --path . -s res://tests/midden_probe.gd -- fungus_farm 3600 300 [seed]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario := args[0] if args.size() > 0 else "fungus_farm"
	var seconds := float(args[1]) if args.size() > 1 else 3600.0
	var every := float(args[2]) if args.size() > 2 else 300.0
	var registry := Registry.create_default()
	var config: SimConfig = load("res://sim/default_config.tres")
	var sim := ScenarioLoader.load_simulation(scenario, registry, config, int(args[3]) if args.size() > 3 else -1)
	var t0 := Time.get_ticks_msec()
	var next := every
	while sim.time() < seconds - 1e-6:
		sim.step()
		if sim.time() >= next - 1e-6:
			next += every
			for colony in sim.colonies:
				var nest := colony.nest
				var line := "t=%5.0f c%d pop=%d loads=%d dumped=%.2f" % [sim.time(), colony.id, colony.total_population(), nest.dumped_items, nest.dumped_mass]
				for m in nest.middens:
					line += " | m%d %s at=(%.0f,%.0f) r=%.0f deps=%d recv=%.2f left=%.2f stain=%.2f rot=%.2f" % [m.index, m.style,
							m.position.x - nest.position.x, m.position.y - nest.position.y, m.radius(), m.count(), m.received,
							m.deposit_mass(sim.time(), registry), m.stain_mass, m.decayed_mass(sim.time(), registry)]
				print(line)
	print("done in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()
