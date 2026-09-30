extends TestCase
## M16i: ScenarioValidator's schema checks (types, ranges, required keys,
## unknown enum values, the output size), every shipped scenario validating
## cleanly, and the editor's use of it (problems list, outline and preview
## marks, the warning before Save/Run/Record). The scene checks have their own
## tests in test_scene_checks.gd.

const EDITOR := preload("res://scenes/editor.tscn")

var _registry := Registry.create_default()
var _schema := ScenarioSchema.new(_registry)
var _config: SimConfig = load("res://sim/default_config.tres")

## A small valid scenario.
func _data() -> Dictionary:
	return {"name": "t", "seed": 3, "duration": 20,
			"colonies": [{"species": _species(), "nest": [540, 960]}],
			"food": [{"type": "food_pile", "pos": [300, 600], "radius": 20, "amount": 50}]}

func _species() -> String:
	var ids: Array = _registry.species.keys()
	ids.sort()
	return ids[0]

func _issue_at(issues: Array[Dictionary], path: Array, severity: String = ScenarioValidator.ERROR) -> bool:
	for i: Dictionary in issues:
		if i["path"] == path and i["severity"] == severity:
			return true
	return false

func _dump(issues: Array[Dictionary]) -> String:
	var out: PackedStringArray = []
	for i: Dictionary in issues:
		out.append(ScenarioValidator.format(i))
	return "; ".join(out)

func test_valid_data_has_no_schema_issues() -> void:
	var issues := ScenarioValidator.schema_issues(_data(), _schema)
	check(issues.is_empty(), _dump(issues))

func test_wrong_types() -> void:
	var d := _data()
	d["duration"] = "long"
	d["seed"] = 1.5
	d["colonies"][0]["nest"] = [1, 2, 3]
	d["food"][0]["amount"] = true
	var issues := ScenarioValidator.schema_issues(d, _schema)
	check(_issue_at(issues, ["duration"]), "text duration: " + _dump(issues))
	check(_issue_at(issues, ["seed"]), "fractional seed: " + _dump(issues))
	check(_issue_at(issues, ["colonies", 0, "nest"]), "3-element nest: " + _dump(issues))
	check(_issue_at(issues, ["food", 0, "amount"]), "bool amount: " + _dump(issues))

func test_ranges() -> void:
	var d := _data()
	d["seed"] = -4
	d["food"][0]["radius"] = 0
	d["render"] = {"pheromone_opacity": 2.0}
	var issues := ScenarioValidator.schema_issues(d, _schema)
	check(_issue_at(issues, ["seed"]), "negative seed")
	check(_issue_at(issues, ["food", 0, "radius"]), "radius below 1")
	check(_issue_at(issues, ["render", "pheromone_opacity"]), "opacity above 1: " + _dump(issues))

func test_required_keys() -> void:
	var d := _data()
	(d["colonies"][0] as Dictionary).erase("nest")
	(d["food"][0] as Dictionary).erase("pos")
	var issues := ScenarioValidator.schema_issues(d, _schema)
	check(_issue_at(issues, ["colonies", 0]), "colony without nest: " + _dump(issues))
	check(_issue_at(issues, ["food", 0]), "food without pos: " + _dump(issues))

func test_unknown_enum_values() -> void:
	var d := _data()
	d["colonies"][0]["species"] = "no_such_species"
	d["food"][0]["type"] = "no_such_food"
	var issues := ScenarioValidator.schema_issues(d, _schema)
	check(_issue_at(issues, ["colonies", 0, "species"]), "species: " + _dump(issues))
	check(_issue_at(issues, ["food", 0, "type"]), "food type: " + _dump(issues))

func test_unknown_keys_are_warnings() -> void:
	var d := _data()
	d["my_note"] = "kept"
	var issues := ScenarioValidator.schema_issues(d, _schema)
	check(_issue_at(issues, ["my_note"], ScenarioValidator.WARNING), _dump(issues))
	check_eq(ScenarioValidator.count(issues, ScenarioValidator.ERROR), 0, "no errors")

func test_output_size() -> void:
	for bad: Array in [[1081, 1920], [32, 32], [10000, 1080], [1080.5, 1920]]:
		var d := _data()
		d["output"] = {"size": bad}
		check(_issue_at(ScenarioValidator.schema_issues(d, _schema), ["output", "size"]), "size %s" % [bad])
	var ok := _data()
	ok["output"] = {"size": [1920, 1080], "safe_zones": "youtube_shorts"}
	check(ScenarioValidator.schema_issues(ok, _schema).is_empty(), "landscape is fine")

func test_world_size_errors() -> void:
	for bad: Array in [[1081, 1920], [1080, 1921], [128, 1024], [1024, 8], [4104, 1024], [1024, 8192], [1080.5, 1920]]:
		var d := _data()
		d["world"] = {"size": bad}
		var issues := ScenarioValidator.schema_issues(d, _schema)
		check(_issue_at(issues, ["world", "size"]), "world size %s: %s" % [bad, _dump(issues)])
	for good: Array in [[1920, 1080], [256, 256], [2160, 3840], [4096, 1024]]:
		var d := _data()
		d["world"] = {"size": good}
		var issues := ScenarioValidator.schema_issues(d, _schema)
		check(issues.is_empty(), "world size %s is fine: %s" % [good, _dump(issues)])

func test_large_world_warning() -> void:
	var d := _data()
	d["world"] = {"size": [4096, 4096]}
	var issues := ScenarioValidator.schema_issues(d, _schema)
	check(_issue_at(issues, ["world", "size"], ScenarioValidator.WARNING), "4096x4096 warns: " + _dump(issues))
	check_eq(ScenarioValidator.count(issues, ScenarioValidator.ERROR), 0, "but is valid")
	d["world"] = {"size": [1080, 1920 * int(ScenarioValidator.LARGE_WORLD_AREA_FACTOR)]}
	check(not _issue_at(ScenarioValidator.schema_issues(d, _schema), ["world", "size"], ScenarioValidator.WARNING),
			"exactly the factor does not warn")

func test_malformed_data_does_not_crash() -> void:
	var d := {"colonies": "none", "food": [3, null, {"type": 5}], "camera": 7, "events": [{}],
			"render": [], "output": {"size": "big"}}
	var issues := ScenarioValidator.validate(d, _schema)
	check(ScenarioValidator.count(issues, ScenarioValidator.ERROR) >= 4, _dump(issues))

func test_helpers() -> void:
	var issues: Array[Dictionary] = [ScenarioValidator.issue(["food", 0, "pos"], ScenarioValidator.ERROR, "a"),
			ScenarioValidator.issue(["food", 1], ScenarioValidator.WARNING, "b"),
			ScenarioValidator.issue(["seed"], ScenarioValidator.ERROR, "c")]
	check_eq(ScenarioValidator.summary(issues), "2 errors, 1 warning")
	check_eq(ScenarioValidator.under(issues, ["food"]).size(), 2, "under food")
	check_eq(ScenarioValidator.under(issues, ["food", 0]).size(), 1, "under food/0")
	check_eq(ScenarioValidator.summary([] as Array[Dictionary]), "")

## Every shipped scenario validates cleanly (schema and scene checks, with its sim).
func _check_shipped(names: Array) -> void:
	for n: String in names:
		var data := ScenarioLoader.load_data(n)
		var issues := ScenarioValidator.validate(data, _schema, ScenarioLoader.build(data, _registry, _config))
		check(issues.is_empty(), "%s: %s" % [n, _dump(issues)])

func test_shipped_scenarios_validate_a() -> void:
	_check_shipped(["basic_forage", "chaos_to_highway", "maze", "rain_reset", "trunk_trail", "twig_bridge", "leaf_strip"])

func test_shipped_scenarios_validate_b() -> void:
	_check_shipped(["meadow_forage", "two_species", "fungus_farm", "queen_landing"])

func test_shipped_scenarios_validate_c() -> void:
	_check_shipped(["colony_founding", "harvester_founding"])

func test_shipped_scenarios_validate_d() -> void:
	_check_shipped(["leafcutter_life", "nuptial_flight"])

func test_every_shipped_scenario_is_listed() -> void:
	var listed := ["basic_forage", "chaos_to_highway", "maze", "rain_reset", "trunk_trail", "twig_bridge",
			"leaf_strip", "meadow_forage", "two_species", "fungus_farm", "queen_landing", "colony_founding",
			"harvester_founding", "leafcutter_life", "nuptial_flight"]
	for f: String in DirAccess.get_files_at("res://scenarios"):
		if f.ends_with(".json"):
			check(listed.has(f.get_basename()), "%s is not in a test_shipped_scenarios_validate_* list" % f)

# --- in the editor ---------------------------------------------------------------------

func _dir() -> String:
	var dir := ProjectSettings.globalize_path("user://test_validator".path_join(current_test.get_slice("::", 1)))
	DirAccess.make_dir_recursive_absolute(dir)
	return dir

func _editor(scenario: String, extra: Dictionary = {}) -> ScenarioEditor:
	var ed: ScenarioEditor = EDITOR.instantiate()
	ed.manage_window = false
	ed.settings_path = _dir().path_join("settings.cfg")
	ed.args = extra.duplicate()
	if scenario != "":
		ed.args["scenario"] = scenario
	(Engine.get_main_loop() as SceneTree).root.add_child(ed)
	return ed

func _cleanup(ed: ScenarioEditor) -> void:
	ed.free()
	RecordJob.remove_tree(_dir())

func _outline_item(ed: ScenarioEditor, path: Array) -> TreeItem:
	var row := EditorOutline.row_for(ed.rows, path)
	var stack: Array[TreeItem] = [ed.outline.get_root()]
	while not stack.is_empty():
		var t: TreeItem = stack.pop_back()
		for c: TreeItem in t.get_children():
			if int(c.get_metadata(0)) == row:
				return c
			stack.append(c)
	return null

func test_editor_lists_and_marks_problems() -> void:
	var ed := _editor("basic_forage")
	check(ed.issues.is_empty(), "shipped scenario is clean: " + _dump(ed.issues))
	check_eq(ed.problems.item_count, 0, "empty list")
	ed.doc.set_at(["food", 0, "radius"], 0)
	ed.preview.rebuild()
	check(_issue_at(ed.issues, ["food", 0, "radius"]), "radius issue listed")
	check(ed.problems.item_count >= 1, "in the problems list")
	check(ed.problems_title.text.contains("error"), ed.problems_title.text)
	var item := _outline_item(ed, ["food", 0])
	check(item != null and item.get_tooltip_text(0).contains("range"), "outline row tooltip")
	check(ed.preview.issue_marks.size() >= 1, "marked in the preview")
	# Clicking the problem selects the item.
	ed.problems.select(0)
	ed.problems.item_selected.emit(0)
	check_eq(ed.selected, ["food", 0], "problem selects its item")
	ed.doc.undo()
	ed.preview.rebuild()
	check(ed.issues.is_empty(), "clean after undo")
	check_eq(ed.preview.issue_marks.size(), 0, "marks gone")
	_cleanup(ed)

func test_editor_warns_before_run_with_errors() -> void:
	var ed := _editor("basic_forage")
	var launched: Array = []
	ed.runs_dir = _dir().path_join("runs")
	ed.launch_process = func(exe: String, a: PackedStringArray) -> int:
		launched.append(a)
		return 1073741823
	ed._on_run_menu(ScenarioEditor.RunItem.RUN)
	check_eq(launched.size(), 1, "a clean document runs at once")
	ed.run_pid = -1
	ed.doc.set_at(["colonies", 0, "species"], "no_such_species")
	ed._on_run_menu(ScenarioEditor.RunItem.RUN)
	check_eq(launched.size(), 1, "waits for the warning")
	check(ed._warn.visible, "warning shown")
	check(ed._warn.dialog_text.contains("colonies/0/species"), ed._warn.dialog_text)
	ed._warn.confirmed.emit()
	check_eq(launched.size(), 2, "runs anyway after confirming")
	ed.run_pid = -1
	_cleanup(ed)

func test_editor_remembers_layout_and_last_file() -> void:
	var ed := _editor("basic_forage")
	var split: SplitContainer = ed._splits["outline"]
	split.split_offset = 57
	ed._save_layout()
	ed.free()
	var again := _editor("")
	check_eq((again._splits["outline"] as SplitContainer).split_offset, 57, "split offset restored")
	check_eq(again.doc.file_path, "res://scenarios/basic_forage.json", "last file reopened")
	again.free()
	var fresh := _editor("", {"new": ""})
	check_eq(fresh.doc.file_path, "", "--new starts a new document")
	_cleanup(fresh)
