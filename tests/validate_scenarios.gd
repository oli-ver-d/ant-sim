extends SceneTree
## Validates scenarios as the editor does (ScenarioValidator: schema and scene
## checks, with the simulation built for the checks against walls) and prints
## one line per issue. Exits with 1 if any scenario has errors (warnings don't
## fail).
##
##   godot --headless --path . -s res://tests/validate_scenarios.gd -- [name|path.json ...]
##
## Without arguments it validates every res://scenarios/*.json.

func _initialize() -> void:
	var names: PackedStringArray = OS.get_cmdline_user_args()
	if names.is_empty():
		for f: String in DirAccess.get_files_at("res://scenarios"):
			if f.ends_with(".json"):
				names.append(f.get_basename())
	var registry := Registry.create_default()
	var schema := ScenarioSchema.new(registry)
	var config := load("res://sim/default_config.tres") as SimConfig
	var failed := 0
	for n: String in names:
		var path := ScenarioLoader.path_for(n)
		if not FileAccess.file_exists(path):
			print("%s: no such scenario (%s)" % [n, path])
			failed += 1
			continue
		var data := ScenarioLoader.load_data(n)
		var sim := ScenarioLoader.build(data, registry, config)
		var issues := ScenarioValidator.validate(data, schema, sim)
		print("%s: %s" % [n, ScenarioValidator.summary(issues) if not issues.is_empty() else "ok"])
		for i: Dictionary in issues:
			print("  " + ScenarioValidator.format(i))
		if ScenarioValidator.count(issues, ScenarioValidator.ERROR) > 0:
			failed += 1
	quit(1 if failed > 0 else 0)
