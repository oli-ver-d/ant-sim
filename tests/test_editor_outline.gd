extends TestCase
## M16c: the editor's outline rows and item bounds (EditorOutline) and the
## recent-files list (EditorRecent), both GUI-free.

func _rows(scenario: String) -> Array[Dictionary]:
	return EditorOutline.build(ScenarioLoader.load_data(scenario))

func _labels(rows: Array[Dictionary]) -> Array:
	return rows.map(func(r: Dictionary) -> String: return r["label"])

func test_basic_forage_outline() -> void:
	var rows := _rows("basic_forage")
	var labels := _labels(rows)
	check_eq(labels.slice(0, 4), ["Scenario", "Colonies", "Colony 0: leafcutter @ 540,1500", "Food"])
	for l: String in ["Colony 0: leafcutter @ 540,1500", "Food 0: food_pile @ 300,520", "Food 1: food_pile @ 820,800",
			"Obstacle 0: polyline wall", "Obstacle 1: circle water", "Ground", "Region 0: moss circle",
			"Region 1: litter rect", "Region 3: moss", "Scatter 0: meadow", "Obstacles", "Scenery"]:
		check(labels.has(l), "missing row " + l)
	check(not labels.has("Debris") and not labels.has("Events") and not labels.has("Camera"), "absent sections are not shown")
	var depth: Dictionary = {}
	for r: Dictionary in rows:
		depth[r["label"]] = r["depth"]
	check_eq(depth["Colonies"], 0)
	check_eq(depth["Region 0: moss circle"], 1)
	# Order of sections.
	check(labels.find("Colonies") < labels.find("Food") and labels.find("Food") < labels.find("Obstacles")
			and labels.find("Obstacles") < labels.find("Ground") and labels.find("Ground") < labels.find("Scenery"), "section order")

func test_always_shown_sections() -> void:
	var labels := _labels(EditorOutline.build({}))
	check_eq(labels, ["Scenario", "Colonies", "Food", "Obstacles"])
	var rows := EditorOutline.build({"name": "x", "ground": "sand"})
	check_eq(_labels(rows), ["Scenario", "Colonies", "Food", "Obstacles", "Ground"])
	check_eq(rows[4]["path"], ["ground"])

func test_paths_resolve() -> void:
	for scenario: String in ["basic_forage", "leafcutter_life", "rain_reset", "maze"]:
		var data := ScenarioLoader.load_data(scenario)
		var doc := ScenarioDoc.new(data)
		for r: Dictionary in EditorOutline.build(data):
			var path: Array = r["path"]
			if path.is_empty() or doc.has_at(path):
				continue
			check(path.size() == 1 and ["colonies", "food", "obstacles"].has(path[0]),
					"%s: row %s path %s does not resolve" % [scenario, r["label"], path])

func _every_scenario(fn: Callable) -> void:
	for f: String in DirAccess.get_files_at(ScenarioLoader.SCENARIO_DIR):
		if f.ends_with(".json"):
			fn.call(f.get_basename())

func test_every_scenario_builds_with_bounds() -> void:
	_every_scenario(func(scenario: String) -> void:
		var data := ScenarioLoader.load_data(scenario)
		var rows := EditorOutline.build(data)
		check(rows.size() >= 4, scenario + " has rows")
		for r: Dictionary in rows:
			check(r["label"] is String and not (r["label"] as String).contains("null"), "%s: label %s" % [scenario, r["label"]])
			var path: Array = r["path"]
			if r["depth"] == 1 and path.size() == 2 and (path[0] == "colonies" or path[0] == "food"):
				check(EditorOutline.item_bounds(data, path).has_area(), "%s: no bounds for %s" % [scenario, r["label"]])
			# Never crashes for any row.
			EditorOutline.item_bounds(data, path))

func test_camera_dict_tracks() -> void:
	var data := ScenarioLoader.load_data("colony_founding")
	check(data["camera"] is Dictionary, "colony_founding has a {surface, nest} camera")
	var rows := EditorOutline.build(data)
	var labels := _labels(rows)
	var s := labels.find("Surface camera")
	check(s >= 0, "surface track row")
	check_eq(rows[s]["path"], ["camera", "surface"])
	check_eq(rows[s]["depth"], 1)
	check_eq(rows[s + 1]["depth"], 2)
	check_eq(rows[s + 1]["path"], ["camera", "surface", 0])
	check_eq(rows[s + 1]["label"], "Camera 0: 0s pos 540,1060")
	check(labels.has("Nest camera"), "nest track row")
	check(labels.find("Camera") < s, "Camera section first")

func test_camera_list_and_labels() -> void:
	var data := {"camera": [{"t": 0, "pos": [540, 960]}, {"t": 4, "follow": {"ant": 0}}, {"t": 8.5, "fit": "excavation"}, {"t": 9}, {}]}
	var labels := _labels(EditorOutline.build(data))
	check_eq(labels.slice(labels.find("Camera"), labels.size()),
			["Camera", "Camera 0: 0s pos 540,960", "Camera 1: 4s follow", "Camera 2: 8.5s fit", "Camera 3: 9s", "Camera 4: ?s"])

func test_item_labels() -> void:
	var data := {
		"debris": [{"type": "twig", "pos": [10.0, 20.5]}],
		"events": [{"t": 12.0, "type": "rain"}, {"type": "x"}],
		"scenery": [{"type": "rock", "center": [5, 6], "radius": 40}, {"type": "log", "points": [[1, 2], [3, 4]]}, {"scatter": {}}, {"scatter": {"preset": "rocky"}}, {}],
		"colonies": [{}, 5],
		"obstacles": [{"shape": "rect", "rect": [0, 0, 5, 5]}],
	}
	var labels := _labels(EditorOutline.build(data))
	for l: String in ["Debris 0: twig @ 10,20.5", "Event 0: rain @ 12s", "Event 1: x @ ?s", "Prop 0: rock @ 5,6",
			"Prop 1: log @ 1,2", "Scatter 2: scatter", "Scatter 3: rocky", "Prop 4: ?", "Colony 0: ?", "Colony 1: ?",
			"Obstacle 0: rect"]:
		check(labels.has(l), "missing label " + l)

func test_unknown_top_level_key_is_a_section() -> void:
	var rows := EditorOutline.build({"name": "n", "seed": 1, "mystery": {"a": 1}, "colonies": []})
	var labels := _labels(rows)
	check_eq(labels, ["Scenario", "Colonies", "Food", "Obstacles", "mystery"])
	check_eq(rows[4]["path"], ["mystery"])
	check_eq(rows[4]["depth"], 0)

func test_section_of() -> void:
	check_eq(EditorOutline.section_of(["colonies", 0, "nest_params"]), ["colonies"])
	check_eq(EditorOutline.section_of(["name"]), [])
	check_eq(EditorOutline.section_of(["max_agents", "surface"]), [])
	check_eq(EditorOutline.section_of([]), [])
	check_eq(EditorOutline.section_of(["camera", "nest", 2]), ["camera"])
	check_eq(EditorOutline.section_of(["ground", "regions", 1]), ["ground"])
	check_eq(EditorOutline.section_of(["mystery", "a"]), ["mystery"])

func test_row_for() -> void:
	var data := ScenarioLoader.load_data("colony_founding")
	var rows := EditorOutline.build(data)
	var i := EditorOutline.row_for(rows, ["colonies", 0, "nest_params", "brood"])
	check_eq(rows[i]["path"], ["colonies", 0])
	check_eq(rows[EditorOutline.row_for(rows, ["colonies"])]["label"], "Colonies")
	check_eq(rows[EditorOutline.row_for(rows, ["name"])]["label"], "Scenario")
	check_eq(rows[EditorOutline.row_for(rows, ["camera", "surface", 1, "zoom"])]["path"], ["camera", "surface", 1])
	check_eq(rows[EditorOutline.row_for(rows, ["colonies", 999])]["path"], ["colonies"])
	check_eq(EditorOutline.row_for(rows, ["camera", "surface"]), labels_index(rows, "Surface camera"))
	check_eq(EditorOutline.row_for([] as Array[Dictionary], ["x"]), -1)
	var no_scenario: Array[Dictionary] = [{"label": "C", "path": ["colonies"], "depth": 0}]
	check_eq(EditorOutline.row_for(no_scenario, ["food", 0]), -1)

func labels_index(rows: Array[Dictionary], label: String) -> int:
	return _labels(rows).find(label)

func test_bounds() -> void:
	var data := {
		"colonies": [{"nest": [540.0, 1500.0]}, {}],
		"food": [{"pos": [820.0, 800.0], "radius": 22.0}, {"pos": [1, 2]}],
		"obstacles": [
			{"shape": "circle", "center": [220.0, 1250.0], "radius": 60.0},
			{"shape": "polyline", "points": [[360.0, 1050.0], [720.0, 1050.0]], "width": 16.0},
			{"shape": "rect", "rect": [10.0, 20.0, 30.0, 40.0]},
			{"shape": "polygon", "points": [[0.0, 0.0], [100.0, 0.0], [50.0, 80.0]]},
		],
		"ground": {"base": "soil", "regions": [
			{"material": "moss", "shape": "circle", "center": [100.0, 100.0], "radius": 50.0},
			{"material": "moss"},
		]},
		"scenery": [{"scatter": {"rect": [0.0, 0.0, 500.0, 400.0]}}, {"scatter": {}}, {"type": "rock", "center": [50.0, 60.0], "radius": 40.0}],
		"debris": [{"type": "twig", "pos": [5.0, 5.0]}],
		"events": [{"t": 1, "type": "rain", "area": {"center": [300.0, 300.0], "radius": 100.0}}, {"t": 1, "type": "rain"}],
		"camera": {"surface": [{"t": 0, "pos": [540.0, 960.0]}, {"t": 1}]},
	}
	check_eq(EditorOutline.item_bounds(data, ["colonies", 0]), Rect2(480, 1440, 120, 120))
	check_eq(EditorOutline.item_bounds(data, ["colonies", 0, "nest_params", "brood"]), Rect2(480, 1440, 120, 120))
	check(not EditorOutline.item_bounds(data, ["colonies", 1]).has_area(), "colony without nest")
	check_eq(EditorOutline.item_bounds(data, ["food", 0]), Rect2(798, 778, 44, 44))
	check_eq(EditorOutline.item_bounds(data, ["food", 1]), Rect2(-29, -28, 60, 60), "default food radius 30")
	check_eq(EditorOutline.item_bounds(data, ["obstacles", 0]), Rect2(160, 1190, 120, 120))
	check_eq(EditorOutline.item_bounds(data, ["obstacles", 1]), Rect2(352, 1042, 376, 16), "polyline grown by half the width on every side")
	check_eq(EditorOutline.item_bounds(data, ["obstacles", 2]), Rect2(10, 20, 30, 40))
	check_eq(EditorOutline.item_bounds(data, ["obstacles", 3]), Rect2(0, 0, 100, 80))
	check_eq(EditorOutline.item_bounds(data, ["ground", "regions", 0]), Rect2(50, 50, 100, 100))
	check(not EditorOutline.item_bounds(data, ["ground", "regions", 1]).has_area(), "region without shape")
	check_eq(EditorOutline.item_bounds(data, ["scenery", 0]), Rect2(0, 0, 500, 400))
	check(not EditorOutline.item_bounds(data, ["scenery", 1]).has_area(), "scatter over the whole world")
	check_eq(EditorOutline.item_bounds(data, ["scenery", 2]), Rect2(10, 20, 80, 80))
	check(EditorOutline.item_bounds(data, ["debris", 0]).has_area(), "debris")
	check_eq(EditorOutline.item_bounds(data, ["events", 0]), Rect2(200, 200, 200, 200))
	check(not EditorOutline.item_bounds(data, ["events", 1]).has_area(), "whole-world rain")
	check(EditorOutline.item_bounds(data, ["camera", "surface", 0]).has_area(), "camera pos")
	check(not EditorOutline.item_bounds(data, ["camera", "surface", 1]).has_area(), "camera without pos")
	for p: Array in [[], ["name"], ["colonies"], ["colonies", 9], ["nothing", 1], ["ground"], ["food", 0, "pos"]]:
		EditorOutline.item_bounds(data, p)  # no crash
	check(EditorOutline.item_bounds(data, ["food", 0, "pos"]).has_area(), "a path inside an item gives the item's bounds")

# --- EditorRecent ---------------------------------------------------------------------

func test_recent_add_dedupe_trim_remove() -> void:
	var r := EditorRecent.new()
	r.add("res://scenarios/a.json")
	r.add("res://scenarios/b.json")
	check_eq(Array(r.files), ["res://scenarios/b.json", "res://scenarios/a.json"])
	r.add("res://scenarios/./x/../a.json")
	check_eq(Array(r.files), ["res://scenarios/./x/../a.json", "res://scenarios/b.json"], "deduped by normalised path, moved to front")
	for i: int in 15:
		r.add("res://s/%d.json" % i)
	check_eq(r.files.size(), EditorRecent.MAX_FILES)
	check_eq(r.files[0], "res://s/14.json")
	check_eq(r.files[EditorRecent.MAX_FILES - 1], "res://s/5.json")
	r.remove("res://s/./14.json")
	check_eq(r.files.size(), EditorRecent.MAX_FILES - 1)
	check_eq(r.files[0], "res://s/13.json")
	r.remove("nothing")
	check_eq(r.files.size(), EditorRecent.MAX_FILES - 1)

func test_recent_save_load_keeps_other_sections() -> void:
	var path := "user://test_editor_recent.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("window", "size", Vector2i(800, 600))
	check_eq(cfg.save(path), OK)
	var r := EditorRecent.new()
	r.add("C:/a/one.json")
	r.add("C:/a/two.json")
	check_eq(r.save_to(path), OK)
	var loaded := EditorRecent.new()
	loaded.load_from(path)
	check_eq(Array(loaded.files), ["C:/a/two.json", "C:/a/one.json"])
	var after := ConfigFile.new()
	check_eq(after.load(path), OK)
	check_eq(after.get_value("window", "size"), Vector2i(800, 600), "other section kept")
	# A missing file loads as empty, and saving creates it.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var empty := EditorRecent.new()
	empty.add("stale")
	empty.load_from(path)
	check_eq(empty.files.size(), 0)
	check_eq(r.save_to(path), OK)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_drop_move_down_and_up() -> void:
	var r := ["ground", "regions", 0]
	# Below/on item 2 of 0: lands at 2 (after removal); above item 2: at 1.
	check_eq(EditorOutline.drop_move(r, ["ground", "regions", 2], 1), {"path": r, "to": 2})
	check_eq(EditorOutline.drop_move(r, ["ground", "regions", 2], 0), {"path": r, "to": 2})
	check_eq(EditorOutline.drop_move(r, ["ground", "regions", 2], -1), {"path": r, "to": 1})
	# Moving up: above item 0 from 2 -> 0; below item 0 -> 1.
	var s := ["ground", "regions", 2]
	check_eq(EditorOutline.drop_move(s, ["ground", "regions", 0], -1), {"path": s, "to": 0})
	check_eq(EditorOutline.drop_move(s, ["ground", "regions", 0], 1), {"path": s, "to": 1})
	check_eq(EditorOutline.drop_move(["food", 0], ["food", 3], 1), {"path": ["food", 0], "to": 3})

func test_drop_move_same_place_is_nothing() -> void:
	var r := ["food", 1]
	check_eq(EditorOutline.drop_move(r, ["food", 1], 0), {})
	check_eq(EditorOutline.drop_move(r, ["food", 1], -1), {})
	check_eq(EditorOutline.drop_move(r, ["food", 1], 1), {})
	check_eq(EditorOutline.drop_move(r, ["food", 0], 1), {})
	check_eq(EditorOutline.drop_move(r, ["food", 2], -1), {})

func test_drop_move_rejects_other_lists_and_sections() -> void:
	check_eq(EditorOutline.drop_move(["food", 0], ["obstacles", 1], 0), {})
	check_eq(EditorOutline.drop_move(["food", 0], ["food"], 0), {})
	check_eq(EditorOutline.drop_move(["ground", "regions", 0], ["ground"], 0), {})
	check_eq(EditorOutline.drop_move(["ground", "regions", 0], ["scenery", 1], 0), {})
	check_eq(EditorOutline.drop_move(["camera", "surface", 0], ["camera", "nest", 1], 0), {})
	check_eq(EditorOutline.drop_move(["camera", "surface", 0], ["camera", "surface", 1], 0), {"path": ["camera", "surface", 0], "to": 1})
	check_eq(EditorOutline.drop_move(["food"], ["food", 1], 0), {})
	check_eq(EditorOutline.drop_move([], [], 0), {})
