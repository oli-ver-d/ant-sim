extends SceneTree
## Loads a scenario, then applies its scatter entries one by one and prints
## what each placed, how many blocking props connectivity dropped, and times:
##   godot --headless --path . -s res://tests/scatter_probe.gd -- <scenario> [seed]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario := args[0] if args.size() > 0 else "res://tests/fixtures/scenarios/scatter_demo.json"
	var seed_value := int(args[1]) if args.size() > 1 else -1
	var config: SimConfig = load("res://sim/default_config.tres")
	var registry := Registry.create_default()
	var data := ScenarioLoader.load_data(scenario)
	var scenery: Array = data.get("scenery", [])
	var plain := data.duplicate()
	plain["scenery"] = scenery.filter(func(e: Dictionary) -> bool: return not e.has("scatter"))
	var t := Time.get_ticks_msec()
	var sim := ScenarioLoader.build(plain, registry, config, seed_value)
	print("load without scatter: %d ms" % (Time.get_ticks_msec() - t))
	for k in scenery.size():
		if not scenery[k].has("scatter"):
			continue
		t = Time.get_ticks_msec()
		var result := Scatter.apply(sim, scenery[k]["scatter"], k)
		var counts: Dictionary[String, int] = {}
		var blocking := 0
		for p in result.placed:
			var key := p.type_id + (":" + str(p.detail["kind"]) if p.type_id == "plant" else "")
			counts[key] = counts.get(key, 0) + 1
			if p.blocks:
				blocking += 1
		print("%s: %d props (%d blocking), %d dropped, %d ms %s" % [scenery[k]["scatter"].get("preset", "?"),
				result.placed.size(), blocking, result.dropped, Time.get_ticks_msec() - t, counts])
	quit()
